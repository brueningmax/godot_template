# Godot Game Template

A starting point for Godot 4 games with the systems almost every project needs: a signal bus, persistent settings, seeded randomness, scene transitions and a data-driven audio manager. They are wired up and ready to use.

- **Godot version:** 4.7 (GL Compatibility renderer, Jolt physics)
- **Language:** GDScript

## What's included

All systems are autoloads, available globally by name:

| Autoload          | File                                            | Purpose                                                          |
| ----------------- | ----------------------------------------------- | ---------------------------------------------------------------- |
| `SignalBus`       | `globals/signalBus/signalBus.gd`                | Global signals for decoupled communication between systems.      |
| `RngManager`      | `globals/rngManager/rngManager.gd`              | Seeded, reproducible random streams and order-independent rolls. |
| `Audio`           | `globals/audioManager/audio_manager_node.tscn`  | Plays sounds by ID (`ui.click`) with pooling and music layers.   |
| `SettingsManager` | `globals/settingsManager/settingsManager.gd`    | Loads, saves and applies user settings (`user://settings.cfg`).  |
| `SceneManager`    | `globals/sceneManager/sceneManager.gd`          | Scene changes with fades and intermediate screens.               |

There are also menus (main, pause, settings), a reusable `UIButton`, and a debug **scene library** that lists every scene in the project and can preview and launch it.

## Quick start

**New project from the template (Windows):**

1. Copy `setup.bat` into an empty folder and run it.
2. Enter your project name. The script pulls the template, starts a fresh Git history and replaces every `godot_game_template` reference with your project name.

**Already cloned or copied the files:** run `rename.bat` in the project folder to do only the renaming.

Then open `project.godot` in Godot 4.7 and press **F5**.

## Project layout

```
assets/      Raw assets (audio, textures, ...)
globals/     Autoloaded systems, one folder per system
resources/   .tres data (audio registries, bus layout, ...)
scenes/      Game scenes, UI and debug tools
test/        Test scenes
docs/        Documentation
```

## Documentation

- **[Template guide](docs/TEMPLATE_GUIDE.md)**: how each system works, how to use it, and the non-obvious parts. Start here.
- [Audio system](globals/audioManager/Readme.md): full reference for the audio manager.

## Roadmap

Planned work is tracked in this repository's issues and on the [project board](https://github.com/users/brueningmax/projects/5).
