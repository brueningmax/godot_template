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

## Never

- Never set `get_tree().paused` or `Input.mouse_mode` outside `GameState`.
- Never read `SceneRegistry.SCENES` outside `SceneManager` (cyclic reference: it preloads every scene).
- Never use string-based signals (`connect("name", …)`, `emit_signal("name")`). Use `SignalBus.name.connect(…)`.
- Never edit files in `addons/` (vendored third-party code).
- Never commit `.godot/`, `export_credentials.cfg` or anything under `build/`.

## Gotchas when running Godot headless

- **Godot exits 0 even when resources fail to load.** Check output for `ERROR:` / `SCRIPT ERROR:` lines; don't trust the exit code. `tools/check.sh` does this.
- **`godot --check-only --script file.gd` gives false "Identifier not found" errors** for autoloads. Use `tools/check_scripts.gd` instead.
- **In a `--script` SceneTree harness**, autoload names aren't globals at compile time. Fetch them with `root.get_node("SceneManager")`, and look up enums with `load("res://…/scene_registry.gd").SceneKey`.
- **Always bound a headless run:** wrap it in `timeout`, and give harness scripts a watchdog (`create_timer(N).timeout.connect(quit)`). A runtime error before `quit()` otherwise hangs forever.
- `--script` mode doesn't load the main scene. Instance `globals/scene_manager/main.tscn` yourself to test the boot flow.
- Smoke runs need `--fixed-fps 60` so a frame count equals game time. Headless frames otherwise run unthrottled.
