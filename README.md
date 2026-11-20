# Godot Game Template

A starting point for Godot 4 games with the systems almost every project needs: a signal bus, persistent settings, seeded randomness, scene transitions and a data-driven audio manager. They are wired up and ready to use.

- **Godot version:** 4.7 (GL Compatibility renderer, Jolt physics)
- **Language:** GDScript

## What's included

All systems are autoloads, available globally by name:

| Autoload          | File                                            | Purpose                                                          |
| ----------------- | ----------------------------------------------- | ---------------------------------------------------------------- |
| `Log`             | `globals/log/log.gd`                              | Leveled, categorized logging; also captures engine errors.       |
| `SignalBus`       | `globals/signal_bus/signal_bus.gd`                | Global signals for decoupled communication between systems.      |
| `RngManager`      | `globals/rng_manager/rng_manager.gd`              | Seeded, reproducible random streams and order-independent rolls. |
| `Audio`           | `globals/audio_manager/audio_manager_node.tscn`  | Plays sounds by ID (`ui.click`) with pooling and music layers.   |
| `SettingsManager` | `globals/settings_manager/settings_manager.gd`    | Loads, saves and applies user settings (`user://settings.cfg`).  |
| `GameState`       | `globals/game_state/game_state.gd`                | Menu / playing / paused state; owns pause, the pause menu and mouse mode. |
| `SceneManager`    | `globals/scene_manager/scene_manager.gd`          | Scene changes with fades and intermediate screens.               |
| `Debug`           | `globals/debug/debug.tscn`                        | F1 overlay, ~ console with cheat commands, seed display (debug builds). |

There are also menus (main, pause, settings), a reusable `UIButton`, and a debug **scene library** that lists every scene in the project and can preview and launch it.

## Quick start

1. On GitHub, click **Use this template → Create a new repository**. A one-time workflow names the project after your repository and replaces this README, in one commit.
2. Clone your new repository, open `project.godot` in Godot 4.7, and press **F5**.

Not using GitHub, or want a different name? See [Starting a new game](docs/TEMPLATE_GUIDE.md#starting-a-new-game-from-the-template).

## Tests

```bash
godot --headless -s addons/gut/gut_cmdln.gd
```

59 automated tests (GUT) cover the template's systems. See [Testing](docs/TEMPLATE_GUIDE.md#testing).

`tools/check.sh` runs everything CI runs (format, lint, import, script compile, smoke runs, tests). See [CI](docs/TEMPLATE_GUIDE.md#ci-and-releases).

## Project layout

```
assets/      Raw assets (audio, textures, ...)
globals/     Autoloaded systems, one folder per system
resources/   .tres data (audio registries, bus layout, ...)
scenes/      Game scenes, UI and debug tools
test/        Automated tests (unit, integration) and sandbox scenes
addons/      Third-party plugins (GUT)
docs/        Documentation
```

## Documentation

- **[Template guide](docs/TEMPLATE_GUIDE.md)**: how each system works, how to use it, and the non-obvious parts. Start here.
- [Contributing](CONTRIBUTING.md): folder layout, naming, workflow.
- [Audio system](globals/audio_manager/README.md): full reference for the audio manager.

## Roadmap

Planned work is tracked in this repository's issues and on the [project board](https://github.com/users/brueningmax/projects/5).
