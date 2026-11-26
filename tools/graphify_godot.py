#!/usr/bin/env python3
"""Extract a graphify code graph from Godot files (.gd, .tscn, .tres, project.godot).

graphify parses code with tree-sitter but has no GDScript or Godot scene
parser, so on this repo its AST pass sees no game code. This script fills that
gap: it reads the Godot files with plain text rules and writes nodes and edges
in graphify's extraction format, which the graphify skill merges into its own
AST output (see .claude/skills/graphify/SKILL.md, Step 3 Part A).

What it extracts (every edge is EXTRACTED: read directly from the source):
  - one node per .gd/.tscn/.tres file and per `class_name`
  - functions and signals of each script (`contains`)
  - `extends` to a project class or script (`inherits`)
  - preload()/load() of res:// paths (`imports`)
  - uses of project classes and autoloads in a script (`uses`)
  - calls to functions of the same script, of a project class or of an
    autoload (`calls`), and `<Autoload>.<signal>.connect/emit` (`connects`/`emits`)
  - a scene's or resource's ext_resources: scripts (`attaches_script`),
    sub-scenes (`instances`), other files (`references`)
  - editor signal connections in scenes, to the receiving function (`connects`)
  - autoloads and the main scene in project.godot (`autoloads`, `main_scene`)

Engine classes (Node, RefCounted, ...) are not nodes: they would only add hubs.

After the AST and doc passes are merged, `--link-docs` connects the two halves:
a doc concept named like a project class_name gets a `references` edge to it.

Usage:
  python3 tools/graphify_godot.py [ROOT] [-o OUTPUT] [--exclude DIR ...]
  python3 tools/graphify_godot.py --link-docs graphify-out/.graphify_extract.json
"""

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_EXCLUDED_DIRS = ["addons", ".godot", "build", "graphify-out"]
GODOT_SUFFIXES = {".gd", ".tscn", ".tres"}

CLASS_NAME_PATTERN = re.compile(r"^class_name\s+(\w+)", re.MULTILINE)
EXTENDS_PATTERN = re.compile(r"^extends\s+(\"[^\"]+\"|'[^']+'|[\w.]+)", re.MULTILINE)
FUNCTION_PATTERN = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(", re.MULTILINE)
SIGNAL_PATTERN = re.compile(r"^signal\s+(\w+)", re.MULTILINE)
RESOURCE_LOAD_PATTERN = re.compile(r"\b(?:preload|load)\s*\(\s*[\"']((?:res|uid)://[^\"']+)[\"']")
IDENTIFIER_PATTERN = re.compile(r"\b[A-Z]\w*\b")
MEMBER_CALL_PATTERN = re.compile(r"\b([A-Z]\w*)\.(\w+)\s*\(")
LOCAL_CALL_PATTERN = re.compile(r"(?<![\w.])(?:self\.)?(\w+)\s*\(")
SIGNAL_USE_PATTERN = re.compile(r"\b([A-Z]\w*)\.(\w+)\.(connect|emit)\s*\(")
HEADER_UID_PATTERN = re.compile(r"^\[gd_(?:scene|resource)[^\]]*\buid=\"(uid://[^\"]+)\"")
EXT_RESOURCE_PATTERN = re.compile(r"^\[ext_resource\s+([^\]]*)\]", re.MULTILINE)
NODE_HEADER_PATTERN = re.compile(r"^\[node\s+([^\]]*)\]")
CONNECTION_PATTERN = re.compile(r"^\[connection\s+([^\]]*)\]", re.MULTILINE)
ATTRIBUTE_PATTERN = re.compile(r"(\w+)=(\"[^\"]*\"|\S+)")
SCRIPT_PROPERTY_PATTERN = re.compile(r"^script\s*=\s*ExtResource\(\s*\"([^\"]+)\"\s*\)")
INSTANCE_PATTERN = re.compile(r"ExtResource\(\s*\"([^\"]+)\"\s*\)")
AUTOLOAD_LINE_PATTERN = re.compile(r"^(\w+)=\"\*?([^\"]+)\"")
MAIN_SCENE_PATTERN = re.compile(r"^run/main_scene=\"([^\"]+)\"", re.MULTILINE)

GDSCRIPT_KEYWORDS = {
    "if", "elif", "else", "for", "while", "match", "return", "func", "print",
    "assert", "await", "preload", "load", "super", "len", "range", "str",
    "int", "float", "bool", "typeof", "is_instance_valid",
}


def make_node_id(*parts: str) -> str:
    """Lower-case word characters joined by single underscores, as graphify ids are."""
    joined = "_".join(part for part in parts if part)
    return re.sub(r"_+", "_", re.sub(r"[^\w]+", "_", joined)).strip("_").lower()


def file_node_id(relative_path: str) -> str:
    # The suffix stays in the id: foo.gd and foo.tscn are different nodes.
    return make_node_id(relative_path)


def parse_attributes(attribute_text: str) -> dict:
    return {name: value.strip("\"") for name, value in ATTRIBUTE_PATTERN.findall(attribute_text)}


def strip_comment(line: str) -> str:
    """Drop a trailing # comment, ignoring # inside string literals."""
    quote = ""
    for index, character in enumerate(line):
        if quote:
            if character == quote and line[index - 1] != "\\":
                quote = ""
        elif character in "\"'":
            quote = character
        elif character == "#":
            return line[:index]
    return line


def strip_strings(line: str) -> str:
    return re.sub(r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'", "\"\"", line)


class GodotExtractor:
    def __init__(self, root: Path, excluded_dirs: list[str]):
        self.root = root
        self.excluded_dirs = set(excluded_dirs)
        self.nodes: dict[str, dict] = {}
        self.edges: list[dict] = []
        self.edge_keys: set[tuple] = set()
        self.uid_to_path: dict[str, str] = {}
        self.class_to_script: dict[str, str] = {}
        self.autoload_to_path: dict[str, str] = {}
        self.script_functions: dict[str, dict[str, int]] = {}
        self.script_signals: dict[str, dict[str, int]] = {}
        self.scene_root_scripts: dict[str, str | None] = {}

    # --- discovery -----------------------------------------------------------

    def is_excluded(self, path: Path) -> bool:
        relative_parts = path.relative_to(self.root).parts
        return any(part in self.excluded_dirs for part in relative_parts[:-1])

    def godot_files(self) -> list[Path]:
        found = []
        for path in sorted(self.root.rglob("*")):
            if path.suffix in GODOT_SUFFIXES and path.is_file() and not self.is_excluded(path):
                found.append(path)
        return found

    def relative(self, path: Path) -> str:
        return path.relative_to(self.root).as_posix()

    def resolve_resource_path(self, resource_path: str) -> str | None:
        """Map res:// or uid:// to a repository-relative path, or None."""
        if resource_path.startswith("uid://"):
            resource_path = self.uid_to_path.get(resource_path, "")
        if resource_path.startswith("res://"):
            return resource_path[len("res://"):]
        return None

    # --- graph building ------------------------------------------------------

    def add_node(self, node_id: str, label: str, source_file: str, line_number: int, **extra) -> None:
        if node_id not in self.nodes:
            self.nodes[node_id] = {
                "id": node_id,
                "label": label,
                "file_type": "code",
                "source_file": source_file,
                "source_location": f"L{line_number}",
                "_origin": "ast",
                **extra,
            }

    def add_edge(self, source: str, target: str, relation: str, source_file: str, line_number: int,
                 context: str = "") -> None:
        key = (source, target, relation)
        if source == target or key in self.edge_keys:
            return
        self.edge_keys.add(key)
        edge = {
            "source": source,
            "target": target,
            "relation": relation,
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": source_file,
            "source_location": f"L{line_number}",
            "weight": 1.0,
            "_origin": "ast",
        }
        if context:
            edge["context"] = context
        self.edges.append(edge)

    def class_node_id(self, script_path: str) -> str:
        return file_node_id(script_path) + "_class"

    def script_target_id(self, script_path: str) -> str:
        """The node that stands for a script: its class_name node, else its file node."""
        class_id = self.class_node_id(script_path)
        return class_id if class_id in self.nodes else file_node_id(script_path)

    def file_target_id(self, relative_path: str) -> str | None:
        if relative_path.endswith(".gd"):
            return self.script_target_id(relative_path)
        target_id = file_node_id(relative_path)
        if target_id in self.nodes:
            return target_id
        if (self.root / relative_path).is_file() and not self.is_excluded(self.root / relative_path):
            self.add_node(target_id, Path(relative_path).name, relative_path, 1)
            return target_id
        return None

    # --- passes --------------------------------------------------------------

    def index_uids(self, files: list[Path]) -> None:
        for uid_file in self.root.rglob("*.uid"):
            if self.is_excluded(uid_file):
                continue
            uid = uid_file.read_text(encoding="utf-8", errors="replace").strip()
            self.uid_to_path[uid] = "res://" + self.relative(uid_file)[: -len(".uid")]
        for path in files:
            if path.suffix in (".tscn", ".tres"):
                with path.open(encoding="utf-8", errors="replace") as handle:
                    header_match = HEADER_UID_PATTERN.match(handle.readline())
                if header_match:
                    self.uid_to_path[header_match.group(1)] = "res://" + self.relative(path)

    def index_scripts(self, files: list[Path]) -> None:
        """First pass: file, class, function and signal nodes, so later passes can resolve names."""
        for path in files:
            relative_path = self.relative(path)
            file_id = file_node_id(relative_path)
            self.add_node(file_id, path.name, relative_path, 1)
            if path.suffix != ".gd":
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            class_match = CLASS_NAME_PATTERN.search(text)
            if class_match:
                class_name = class_match.group(1)
                line_number = text.count("\n", 0, class_match.start()) + 1
                self.class_to_script[class_name] = relative_path
                self.add_node(self.class_node_id(relative_path), class_name, relative_path, line_number)
                self.add_edge(file_id, self.class_node_id(relative_path), "defines", relative_path, line_number)
            owner_id = self.script_target_id(relative_path)
            functions: dict[str, int] = {}
            for function_match in FUNCTION_PATTERN.finditer(text):
                name = function_match.group(1)
                line_number = text.count("\n", 0, function_match.start()) + 1
                functions.setdefault(name, line_number)
                function_id = make_node_id(file_id, name)
                self.add_node(function_id, f"{name}()", relative_path, line_number, _callable=True)
                self.add_edge(owner_id, function_id, "contains", relative_path, line_number)
            signals: dict[str, int] = {}
            for signal_match in SIGNAL_PATTERN.finditer(text):
                name = signal_match.group(1)
                line_number = text.count("\n", 0, signal_match.start()) + 1
                signals.setdefault(name, line_number)
                signal_id = make_node_id(file_id, "signal", name)
                self.add_node(signal_id, f"signal {name}", relative_path, line_number)
                self.add_edge(owner_id, signal_id, "contains", relative_path, line_number)
            self.script_functions[relative_path] = functions
            self.script_signals[relative_path] = signals

    def read_project(self) -> None:
        project_file = self.root / "project.godot"
        if not project_file.is_file():
            return
        text = project_file.read_text(encoding="utf-8", errors="replace")
        project_id = file_node_id("project.godot")
        self.add_node(project_id, "project.godot", "project.godot", 1)
        in_autoload_section = False
        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.startswith("["):
                in_autoload_section = line.strip() == "[autoload]"
                continue
            if not in_autoload_section:
                continue
            autoload_match = AUTOLOAD_LINE_PATTERN.match(line)
            if not autoload_match:
                continue
            autoload_name, resource_path = autoload_match.groups()
            relative_path = self.resolve_resource_path(resource_path)
            if not relative_path:
                continue
            self.autoload_to_path[autoload_name] = relative_path
            target_id = self.file_target_id(relative_path)
            if target_id:
                self.add_edge(project_id, target_id, "autoloads", "project.godot", line_number, autoload_name)
        main_scene_match = MAIN_SCENE_PATTERN.search(text)
        if main_scene_match:
            relative_path = self.resolve_resource_path(main_scene_match.group(1))
            target_id = self.file_target_id(relative_path) if relative_path else None
            if target_id:
                line_number = text.count("\n", 0, main_scene_match.start()) + 1
                self.add_edge(project_id, target_id, "main_scene", "project.godot", line_number)

    def autoload_script(self, autoload_name: str) -> str | None:
        """The script behind an autoload (for a scene autoload, the scene's root script)."""
        relative_path = self.autoload_to_path.get(autoload_name)
        if relative_path and relative_path.endswith(".tscn"):
            return self.scene_root_script(relative_path)
        return relative_path

    def scene_root_script(self, scene_path: str) -> str | None:
        if scene_path in self.scene_root_scripts:
            return self.scene_root_scripts[scene_path]
        root_script = None
        scene_file = self.root / scene_path
        if scene_file.is_file():
            text = scene_file.read_text(encoding="utf-8", errors="replace")
            _, node_scripts = self.scene_nodes(text, self.ext_resources(text))
            root_script = node_scripts.get(".")
        self.scene_root_scripts[scene_path] = root_script
        return root_script

    def class_or_autoload_script(self, name: str) -> str | None:
        return self.class_to_script.get(name) or self.autoload_script(name)

    def read_script(self, path: Path) -> None:
        relative_path = self.relative(path)
        file_id = file_node_id(relative_path)
        owner_id = self.script_target_id(relative_path)
        own_functions = self.script_functions.get(relative_path, {})
        text = path.read_text(encoding="utf-8", errors="replace")

        extends_match = EXTENDS_PATTERN.search(text)
        if extends_match:
            base = extends_match.group(1).strip("\"'")
            line_number = text.count("\n", 0, extends_match.start()) + 1
            base_path = self.resolve_resource_path(base) if "://" in base else self.class_to_script.get(base)
            if base_path:
                self.add_edge(owner_id, self.script_target_id(base_path), "inherits", relative_path, line_number)
            else:
                self.nodes[owner_id]["extends"] = base

        current_function_id = owner_id
        for line_number, raw_line in enumerate(text.splitlines(), start=1):
            for load_match in RESOURCE_LOAD_PATTERN.finditer(raw_line):
                target_path = self.resolve_resource_path(load_match.group(1))
                target_id = self.file_target_id(target_path) if target_path else None
                if target_id:
                    self.add_edge(owner_id, target_id, "imports", relative_path, line_number)
            line = strip_strings(strip_comment(raw_line))
            function_match = FUNCTION_PATTERN.match(line)
            if function_match:
                current_function_id = make_node_id(file_id, function_match.group(1))
                continue
            if line and not line[0].isspace():
                current_function_id = owner_id
            if not line.strip() or line.startswith(("extends", "class_name")):
                # extends is already an inherits edge; class_name declares, not uses.
                continue

            for signal_match in SIGNAL_USE_PATTERN.finditer(line):
                holder, signal_name, action = signal_match.groups()
                holder_script = self.class_or_autoload_script(holder)
                if holder_script and signal_name in self.script_signals.get(holder_script, {}):
                    signal_id = make_node_id(file_node_id(holder_script), "signal", signal_name)
                    relation = "emits" if action == "emit" else "connects"
                    self.add_edge(current_function_id, signal_id, relation, relative_path, line_number)

            for call_match in MEMBER_CALL_PATTERN.finditer(line):
                holder, method_name = call_match.groups()
                holder_script = self.class_or_autoload_script(holder)
                if holder_script and method_name in self.script_functions.get(holder_script, {}):
                    callee_id = make_node_id(file_node_id(holder_script), method_name)
                    self.add_edge(current_function_id, callee_id, "calls", relative_path, line_number)

            for call_match in LOCAL_CALL_PATTERN.finditer(line):
                name = call_match.group(1)
                if name in own_functions and name not in GDSCRIPT_KEYWORDS:
                    callee_id = make_node_id(file_id, name)
                    self.add_edge(current_function_id, callee_id, "calls", relative_path, line_number)

            for identifier in IDENTIFIER_PATTERN.findall(line):
                target_script = self.class_or_autoload_script(identifier)
                if target_script and target_script != relative_path:
                    target_id = self.script_target_id(target_script)
                    self.add_edge(owner_id, target_id, "uses", relative_path, line_number)

    def ext_resources(self, text: str) -> dict[str, tuple[str, str, int]]:
        """ext_resource id -> (type, repository-relative path, line number)."""
        resources = {}
        for resource_match in EXT_RESOURCE_PATTERN.finditer(text):
            attributes = parse_attributes(resource_match.group(1))
            resource_path = attributes.get("path") or attributes.get("uid", "")
            relative_path = self.resolve_resource_path(resource_path)
            if not relative_path and attributes.get("uid"):
                relative_path = self.resolve_resource_path(attributes["uid"])
            if relative_path and "id" in attributes:
                line_number = text.count("\n", 0, resource_match.start()) + 1
                resources[attributes["id"]] = (attributes.get("type", ""), relative_path, line_number)
        return resources

    def scene_nodes(self, text: str, resources: dict) -> tuple[dict[str, str], dict[str, str]]:
        """Node path -> instanced scene path, and node path -> attached script path."""
        node_instances: dict[str, str] = {}
        node_scripts: dict[str, str] = {}
        current_node_path = None
        for line in text.splitlines():
            header_match = NODE_HEADER_PATTERN.match(line)
            if header_match:
                attributes = parse_attributes(header_match.group(1))
                parent = attributes.get("parent")
                name = attributes.get("name", "")
                if parent is None:
                    current_node_path = "."
                elif parent == ".":
                    current_node_path = name
                else:
                    current_node_path = f"{parent}/{name}"
                instance_match = INSTANCE_PATTERN.search(attributes.get("instance", ""))
                if instance_match and instance_match.group(1) in resources:
                    node_instances[current_node_path] = resources[instance_match.group(1)][1]
                continue
            if line.startswith("["):
                current_node_path = None
                continue
            script_match = SCRIPT_PROPERTY_PATTERN.match(line)
            if script_match and current_node_path and script_match.group(1) in resources:
                node_scripts[current_node_path] = resources[script_match.group(1)][1]
        return node_instances, node_scripts

    def read_scene_or_resource(self, path: Path) -> None:
        relative_path = self.relative(path)
        file_id = file_node_id(relative_path)
        text = path.read_text(encoding="utf-8", errors="replace")
        resources = self.ext_resources(text)
        for resource_type, target_path, line_number in resources.values():
            target_id = self.file_target_id(target_path)
            if not target_id:
                continue
            if resource_type == "Script":
                relation = "attaches_script"
            elif resource_type == "PackedScene":
                relation = "instances"
            else:
                relation = "references"
            self.add_edge(file_id, target_id, relation, relative_path, line_number)

        if path.suffix != ".tscn":
            return
        node_instances, node_scripts = self.scene_nodes(text, resources)
        for connection_match in CONNECTION_PATTERN.finditer(text):
            attributes = parse_attributes(connection_match.group(1))
            receiver_script = node_scripts.get(attributes.get("to", ""))
            if not receiver_script:
                instanced_scene = node_instances.get(attributes.get("to", ""))
                receiver_script = self.scene_root_script(instanced_scene) if instanced_scene else None
            method_name = attributes.get("method", "")
            if receiver_script and method_name in self.script_functions.get(receiver_script, {}):
                line_number = text.count("\n", 0, connection_match.start()) + 1
                method_id = make_node_id(file_node_id(receiver_script), method_name)
                self.add_edge(file_id, method_id, "connects", relative_path, line_number,
                              f"{attributes.get('from', '')}.{attributes.get('signal', '')}")

    def run(self) -> dict:
        files = self.godot_files()
        self.index_uids(files)
        self.index_scripts(files)
        self.read_project()
        for path in files:
            if path.suffix == ".gd":
                self.read_script(path)
            else:
                self.read_scene_or_resource(path)
        return {
            "nodes": list(self.nodes.values()),
            "edges": self.edges,
            "input_tokens": 0,
            "output_tokens": 0,
        }


def link_docs_to_classes(extraction_path: Path) -> int:
    """Add doc concept -> class_name edges to a merged graphify extraction, in place.

    Semantic (doc) extraction names classes it reads about ("SceneRegistry")
    but gives them doc-local ids, so docs and code end up as two unconnected
    halves. A doc node whose label, without backticks, a trailing "()" or a
    parenthetical, is exactly a project class_name gets a `references` edge to
    that class. INFERRED 0.95: a named cross-file reference, matched by name.
    Returns the number of edges added.
    """
    extraction = json.loads(extraction_path.read_text(encoding="utf-8"))
    class_ids = {}
    for node in extraction["nodes"]:
        if node.get("_origin") == "ast" and node["id"].endswith("_gd_class"):
            class_ids[node["label"]] = node["id"]
    existing = {(edge["source"], edge["target"]) for edge in extraction["edges"]}
    added = 0
    for node in extraction["nodes"]:
        if node.get("_origin") != "semantic":
            continue
        name = re.sub(r"\s*\(.*\)\s*$", "", node["label"].replace("`", "")).strip()
        class_id = class_ids.get(name)
        if not class_id or (node["id"], class_id) in existing:
            continue
        existing.add((node["id"], class_id))
        extraction["edges"].append({
            "source": node["id"],
            "target": class_id,
            "relation": "references",
            "confidence": "INFERRED",
            "confidence_score": 0.95,
            "source_file": node.get("source_file", ""),
            "source_location": node.get("source_location"),
            "weight": 1.0,
            "_origin": "semantic",
        })
        added += 1
    extraction_path.write_text(json.dumps(extraction, indent=2, ensure_ascii=False), encoding="utf-8")
    return added


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", nargs="?", default=".", help="Godot project root (default: current directory)")
    parser.add_argument("-o", "--output", default="graphify-out/.graphify_godot.json")
    parser.add_argument("--exclude", nargs="*", default=DEFAULT_EXCLUDED_DIRS,
                        help="directory names to skip (default: %(default)s)")
    parser.add_argument("--link-docs", metavar="EXTRACTION_JSON",
                        help="instead of extracting, link doc concepts to classes in a merged extraction")
    arguments = parser.parse_args()

    if arguments.link_docs:
        added = link_docs_to_classes(Path(arguments.link_docs))
        print(f"Godot: linked {added} doc concepts to classes")
        return 0

    root = Path(arguments.root).resolve()
    extraction = GodotExtractor(root, arguments.exclude).run()
    output_path = Path(arguments.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(extraction, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Godot: {len(extraction['nodes'])} nodes, {len(extraction['edges'])} edges -> {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
