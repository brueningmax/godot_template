"""Rebuild the graphify knowledge graph without an LLM: code from source, docs from cache.

The full /graphify pipeline (.claude/skills/graphify/SKILL.md) needs Claude for two
steps: extracting docs (subagents) and naming communities. This script runs every
other step, so a session can have a fresh graph in seconds at start-up:

  - code: graphify's own AST pass plus tools/graphify_godot.py (always current);
  - docs: replayed from graphify-out/cache/semantic, which /graphify fills and which
    is committed. A doc that changed since its last extraction is left out and
    listed; run /graphify . to extract it;
  - community names: taken from graphify-out/community_names.json (committed,
    written by --save-names after a /graphify run). A new community keeps the name
    of the old one most of its nodes came from; one with no match is named after
    its most connected class and folder.

Outputs (git-ignored): graphify-out/graph.json, GRAPH_REPORT.md, manifest.json.

Run it through tools/graphify_rebuild.sh, which finds graphify's Python:
  tools/graphify_rebuild.sh               # rebuild
  tools/graphify_rebuild.sh --html        # also write graph.html
  tools/graphify_rebuild.sh --save-names  # store the current graph's community names
"""

import argparse
import collections
import json
import subprocess
import sys
from pathlib import Path

from graphify.analyze import god_nodes, suggest_questions, surprising_connections
from graphify.build import build_from_json
from graphify.cache import check_semantic_cache
from graphify.cli import _stamped_manifest_files
from graphify.cluster import cluster, score_all
from graphify.detect import detect, save_manifest
from graphify.export import to_json
from graphify.extract import collect_files, extract
from graphify.paths import out_path
from graphify.report import generate
from graphify.watch import _read_build_excludes, _read_build_gitignore

sys.path.insert(0, str(Path(__file__).resolve().parent))
from graphify_godot import GodotExtractor, DEFAULT_EXCLUDED_DIRS, link_docs_to_classes  # noqa: E402

OUTPUT_DIR = Path("graphify-out")
NAMES_FILE = OUTPUT_DIR / "community_names.json"
EXTRACTION_SPEC = Path(".claude/skills/graphify/references/extraction-spec.md")
# A new community takes an old name when at least this share of its nodes had it.
NAME_MATCH_SHARE = 0.5


def log(message: str) -> None:
    print(f"[graphify rebuild] {message}")


def code_extraction(root: Path, detection: dict) -> dict:
    code_files = []
    for code_path in detection["files"].get("code", []):
        path = Path(code_path)
        code_files.extend(collect_files(path) if path.is_dir() else [path])
    result = extract(code_files, cache_root=root, root=root) if code_files else {"nodes": [], "edges": []}
    godot = GodotExtractor(root, DEFAULT_EXCLUDED_DIRS).run()
    known_ids = {node["id"] for node in result["nodes"]}
    nodes = result["nodes"] + [node for node in godot["nodes"] if node["id"] not in known_ids]
    log(f"code: {len(nodes)} nodes ({len(godot['nodes'])} from Godot files)")
    return {"nodes": nodes, "edges": result["edges"] + godot["edges"]}


def cached_doc_extraction(root: Path, detection: dict) -> tuple[dict, list[str]]:
    doc_files = [path for kind in ("document", "paper", "image") for path in detection["files"].get(kind, [])]
    nodes, edges, hyperedges, uncached = check_semantic_cache(
        doc_files, root=str(root), prompt_file=str((root / EXTRACTION_SPEC).resolve())
    )
    for item in nodes + edges:
        item.setdefault("_origin", "semantic")
    unique_nodes = list({node["id"]: node for node in nodes}.values())
    log(f"docs: {len(doc_files) - len(uncached)} of {len(doc_files)} from cache, {len(unique_nodes)} nodes")
    return {"nodes": unique_nodes, "edges": edges, "hyperedges": hyperedges}, uncached


def saved_names() -> list[dict]:
    if not NAMES_FILE.exists():
        return []
    return json.loads(NAMES_FILE.read_text(encoding="utf-8"))


def fallback_name(members: list[str], nodes: dict, degree: collections.Counter) -> str:
    """Most connected named node, plus the folder most members come from."""
    folders = collections.Counter()
    for member in members:
        parent = Path(nodes[member].get("source_file", "")).parent.parts
        folders["/".join(parent[-2:]) if parent else "repo root"] += 1
    folder = folders.most_common(1)[0][0] if folders else ""

    def importance(member: str) -> tuple:
        label = nodes[member]["label"]
        is_named = member.endswith("_gd_class") or not label.endswith(("()", ".gd"))
        return (is_named, degree[member])

    head = nodes[max(members, key=importance)]["label"].replace(".gd", "").replace("()", "")
    head = head if len(head) <= 40 else head[:38] + "…"
    return f"{head} ({folder})" if folder and folder.lower() not in head.lower() else head


def community_names(communities: dict, extraction: dict) -> dict[int, str]:
    nodes = {node["id"]: node for node in extraction["nodes"]}
    degree = collections.Counter()
    for edge in extraction["edges"]:
        degree[edge["source"]] += 1
        degree[edge["target"]] += 1
    old_name_of_node = {}
    for saved in saved_names():
        for member in saved["members"]:
            old_name_of_node[member] = saved["name"]

    names: dict[int, str] = {}
    reused = 0
    for community_id, members in communities.items():
        known = [member for member in members if member in nodes]
        votes = collections.Counter(old_name_of_node[member] for member in known if member in old_name_of_node)
        if votes:
            name, count = votes.most_common(1)[0]
            if count / max(len(known), 1) >= NAME_MATCH_SHARE and name not in names.values():
                names[community_id] = name
                reused += 1
                continue
        names[community_id] = fallback_name(known, nodes, degree) if known else f"Community {community_id}"
    log(f"communities: {len(communities)}, {reused} kept their saved name")
    return names


def save_names_from_graph() -> int:
    graph = json.loads((OUTPUT_DIR / "graph.json").read_text(encoding="utf-8"))
    members_by_name = collections.defaultdict(list)
    for node in graph["nodes"]:
        if node.get("community_name"):
            members_by_name[node["community_name"]].append(node["id"])
    saved = [{"name": name, "members": sorted(members)} for name, members in sorted(members_by_name.items())]
    NAMES_FILE.write_text(json.dumps(saved, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    log(f"saved {len(saved)} community names to {NAMES_FILE}")
    return 0


def rebuild(write_html: bool) -> int:
    root = Path.cwd().resolve()
    OUTPUT_DIR.mkdir(exist_ok=True)
    # The skill's later steps and graphify's hooks read these.
    (OUTPUT_DIR / ".graphify_python").write_text(sys.executable, encoding="utf-8")
    (OUTPUT_DIR / ".graphify_root").write_text(str(root), encoding="utf-8")

    detection = detect(root, extra_excludes=_read_build_excludes(out_path()), gitignore=_read_build_gitignore(out_path()))
    code = code_extraction(root, detection)
    docs, uncached = cached_doc_extraction(root, detection)

    known_ids = {node["id"] for node in code["nodes"]}
    extraction = {
        "nodes": code["nodes"] + [node for node in docs["nodes"] if node["id"] not in known_ids],
        "edges": code["edges"] + docs["edges"],
        "hyperedges": docs["hyperedges"],
        "input_tokens": 0,
        "output_tokens": 0,
    }
    extraction_path = OUTPUT_DIR / ".graphify_extract.json"
    extraction_path.write_text(json.dumps(extraction, ensure_ascii=False), encoding="utf-8")
    linked = link_docs_to_classes(extraction_path)
    extraction = json.loads(extraction_path.read_text(encoding="utf-8"))
    extraction_path.unlink()
    log(f"linked {linked} doc concepts to classes")

    graph = build_from_json(extraction, root=str(root), directed=False)
    if graph.number_of_nodes() == 0:
        log("ERROR: the graph is empty; nothing written")
        return 1
    communities = cluster(graph)
    cohesion = score_all(graph, communities)
    names = community_names(communities, extraction)
    gods = god_nodes(graph)
    surprises = surprising_connections(graph, communities)
    questions = suggest_questions(graph, communities, names)
    # force: graph.json is a local build output, not a committed graph to protect.
    to_json(graph, communities, str(OUTPUT_DIR / "graph.json"), force=True, community_labels=names)
    report = generate(graph, communities, cohesion, names, gods, surprises, detection,
                      {"input": 0, "output": 0}, str(root), suggested_questions=questions)
    (OUTPUT_DIR / "GRAPH_REPORT.md").write_text(report, encoding="utf-8")

    corpus = detection["files"]
    stamped = _stamped_manifest_files(corpus, extraction, root, partial_source_files=set(uncached))
    save_manifest(stamped, root=str(root), scan_corpus={path for paths in corpus.values() for path in paths})

    needs_update = OUTPUT_DIR / ".needs_update"
    if uncached:
        needs_update.write_text("\n".join(uncached), encoding="utf-8")
        log(f"{len(uncached)} doc(s) not in the cache, left out of the graph (run /graphify . to add them):")
        for path in uncached:
            log(f"  {Path(path).relative_to(root)}")
    else:
        needs_update.unlink(missing_ok=True)
    if write_html:
        subprocess.run([sys.executable, "-m", "graphify", "export", "html"], check=False)
    log(f"graph: {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges -> {OUTPUT_DIR}/graph.json")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--html", action="store_true", help="also write graphify-out/graph.html")
    parser.add_argument("--save-names", action="store_true",
                        help="store the community names of graphify-out/graph.json for later rebuilds")
    arguments = parser.parse_args()
    if arguments.save_names:
        return save_names_from_graph()
    return rebuild(arguments.html)


if __name__ == "__main__":
    sys.exit(main())
