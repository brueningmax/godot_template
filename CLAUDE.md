# CLAUDE.md

Guidance for AI coding agents working in this repository. People: see `CONTRIBUTING.md`.

**Project:** a Godot **4.7** game template in GDScript (GL Compatibility, Jolt). Systems are autoloads in `globals/`. How everything works and its gotchas: `docs/TEMPLATE_GUIDE.md`. Read the relevant section before changing a system.

## Commands

```bash
tools/check.sh                       # everything CI runs; must pass before you push
GODOT=/path/to/godot tools/check.sh  # if godot isn't on PATH
godot --headless -s addons/gut/gut_cmdln.gd                              # all tests
godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_game_state     # one file
godot --headless --script res://tools/check_scripts.gd                   # compile every script
gdformat . && gdlint .
```

## Must

- Run `tools/check.sh` and make it pass before committing.
- Add or update tests for behaviour changes (`test/unit/` for pure logic, `test/integration/` + `extends TemplateTest` for anything touching scenes, pause or menus).
- Update `docs/TEMPLATE_GUIDE.md` in the same change when behaviour changes. It must describe the code as it is now.
- Follow `CONTRIBUTING.md` naming: `snake_case` files and folders, `PascalCase` classes and nodes, `CONSTANT_CASE` constants and enum values, past-tense signal names.
- Put start-up navigation in `globals/scene_manager/boot.gd` only.
- Use `GameState` for pause and mouse mode, and `SceneManager` for scene changes.
- Add `SceneKey` values only at the end of the enum.
- Write UI text in English and add every new string to `localization/messages.pot` and each `.po` file (`test_localization.gd` checks scene texts).

## Never

- Never set `get_tree().paused` or `Input.mouse_mode` outside `GameState`.
- Never use `print()`, `push_warning()` or `push_error()` in game code; use `Log.debug/info/warn/error(&"Category", "…")` (tools in `tools/` may print). In tests, assert intended `Log.error()` calls with `assert_push_error()`.
- Never use string-based signals (`connect("name", …)`, `emit_signal("name")`). Use `SignalBus.name.connect(…)`.
- Never edit files in `addons/` (vendored third-party code).
- Never commit `.godot/`, `export_credentials.cfg` or anything under `build/`.

## Gotchas when running Godot headless

- **CI imports from a cold cache.** Code that passes locally can fail there, e.g. `var x := SomeAutoload.some_property` ("Cannot infer the type"). Before pushing a change to scripts, run `rm -rf .godot && tools/check.sh` once. Prefer explicit types (`var x: Node = …`) when reading autoload properties.
- **Godot exits 0 even when resources fail to load.** Check output for `ERROR:` / `SCRIPT ERROR:` lines; don't trust the exit code. `tools/check.sh` does this.
- **`godot --check-only --script file.gd` gives false "Identifier not found" errors** for autoloads. Use `tools/check_scripts.gd` instead.
- **In a `--script` SceneTree harness**, autoload names aren't globals at compile time. Fetch them with `root.get_node("SceneManager")`, and look up enums with `load("res://…/scene_registry.gd").SceneKey`.
- **Always bound a headless run:** wrap it in `timeout`, and give harness scripts a watchdog (`create_timer(N).timeout.connect(quit)`). A runtime error before `quit()` otherwise hangs forever.
- `--script` mode doesn't load the main scene. Instance `globals/scene_manager/main.tscn` yourself to test the boot flow.
- **Headless windows are 64×64 px.** Don't assert pixel sizes of UI in tests; assert anchors/offsets. To *see* UI, render a real frame: `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --audio-driver Dummy --resolution 1152x648 --script <harness>` and save `root.get_viewport().get_texture().get_image()` with `save_png()` after `await RenderingServer.frame_post_draw`.
- Smoke runs need `--fixed-fps 60` so a frame count equals game time. Headless frames otherwise run unthrottled.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. When the answer is under a Markdown heading, `graphify section "<heading>"` prints that section's text, so the .md need not be opened. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, rebuild the graph with `/graphify .` to keep it current. Don't use `graphify update .`: it can't see `.gd`/`.tscn`/`.tres` files (the skill's Part A2 runs `tools/graphify_godot.py` for those), so it would leave Godot changes out.
- The graph is only as good as `tools/graphify_godot.py`'s text rules: it finds calls on `self`, on `class_name` classes and on autoloads, not calls through typed variables. Confirm a missing edge with a grep before concluding there is none.
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
