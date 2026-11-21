# Contributing

Thanks for helping. This page covers the rules that keep the template consistent and working. How each system works is in the **[Template Guide](docs/TEMPLATE_GUIDE.md)**.

## Setup

1. Install [Godot 4.7](https://godotengine.org/download) and Python 3.
2. Install the dev tools:
   ```bash
   pip install -r requirements-dev.txt
   ```
3. Optionally, install the git hooks (format and lint on commit):
   ```bash
   pre-commit install
   ```
4. For VS Code, see [Debugging in VS Code](docs/TEMPLATE_GUIDE.md#debugging-in-vs-code).

## Workflow

1. **Issue first.** Use the bug or feature form, so the work shows up on the project board.
2. **Branch** off `main`.
3. **Run the checks** before pushing. They're the same checks CI runs:
   ```bash
   tools/check.sh
   ```
4. **Open a PR** using the template. Reference the issue (`Fixes #12`) and say how you verified the change.
5. **Update `docs/TEMPLATE_GUIDE.md` in the same PR** when you add a system or change how one behaves. The guide describes the code as it is, never as it's planned to be.

## Folder layout

| Folder | What goes there |
| --- | --- |
| `globals/<system>/` | Autoloaded systems, one folder each (script, scenes, resources it owns). |
| `scenes/` | Everything that's instanced: `game/`, `ui/menus/`, `ui/components/`, `debug/`. One folder per scene, holding its `.tscn`, script and scene-local assets (sounds, textures). |
| `resources/` | Shared `.tres` data, e.g. audio registries and the bus layout. |
| `assets/` | Shared raw assets (audio, textures, fonts) used by several scenes. |
| `test/` | `unit/`, `integration/` (automated, GUT), `sandbox/` (click-through scenes). |
| `tools/` | Developer scripts (`check.sh`, `check_scripts.gd`, `rename_project.gd`). |
| `addons/` | Third-party plugins, unmodified. Excluded from lint and format. |

## Naming

| What | Style | Example |
| --- | --- | --- |
| Folders and files | `snake_case` | `scenes/ui/menus/pause_menu/pause_menu.tscn` |
| Scene files | named after their root node, in `snake_case` | root `PauseMenu` → `pause_menu.tscn` |
| Classes (`class_name`), nodes | `PascalCase` | `PauseMenu`, `SceneHolder` |
| Autoloads | `PascalCase`, not equal to the script's `class_name` | `SceneManager` (class `MainRoot`) |
| Functions, variables, signals | `snake_case`, private ones with a leading `_` | `open_settings()`, `_stack` |
| Constants, enum values | `CONSTANT_CASE` | `MENU_LAYER`, `SceneKey.MAIN_MENU` |
| Signals | past tense, `noun_verbed` | `scene_change_finished`, `card_played` |

Code style is enforced by `gdformat` and `gdlint`. See [Code style](docs/TEMPLATE_GUIDE.md#code-style).

## Rules that keep the template working

- **Start-up navigation lives in `boot.gd` only**, never in an autoload's `_ready()`. Autoloads also run when a single scene is started (F6), so it would hijack scene debugging.
- **`GameState` owns pausing and the mouse mode.** Scenes call `GameState.enter_gameplay(...)` or `GameState.enter_menu()` in `_ready()`. Nothing else sets `get_tree().paused` or `Input.mouse_mode`.
- **Change scenes through `SceneManager`**, never `get_tree().change_scene_to_*()`.
- **Add new `SceneKey` values at the end** of the enum. Exported values are stored as numbers.
- **Logging:** use `Log.debug/info/warn/error(&"Category", "…")` in game code, not `print()` or `push_*()`.
- **SignalBus:** typed signals only (`SignalBus.x.connect(...)`, `.emit(...)`), with a `##` doc comment.
- **Tests:** new behaviour comes with a test. Integration tests extend `TemplateTest`.

## Commits and PRs

- One logical change per commit. Keep mechanical changes (formatting, renames) in their own commits.
- Write commit messages as `Imperative summary` + a blank line + why. Reference issues with `Fixes #N` or `Refs #N`.
- A PR should be reviewable: say what changed, how you verified it, what a reviewer should try by hand, and whether anything breaks.
