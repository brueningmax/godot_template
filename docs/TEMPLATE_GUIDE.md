# Template Guide

How the template's systems work, how to use them, and what isn't obvious from the code. Every section describes the code **as it is now**. Where a system is still planned, the section links to its issue instead of describing it.

> **Maintaining this file:** any change that adds a system or changes how one behaves updates its section here in the same PR.

## Contents

1. [Overview and boot flow](#overview-and-boot-flow)
2. [Autoloads](#autoloads)
3. [SignalBus](#signalbus)
4. [SettingsManager](#settingsmanager)
5. [RngManager](#rngmanager)
6. [SceneManager and SceneRegistry](#scenemanager-and-sceneregistry)
7. [Audio](#audio)
8. [Menus and UI](#menus-and-ui)
9. [Debug tools](#debug-tools)
10. [Debugging in VS Code](#debugging-in-vs-code)
11. [Testing](#testing)
12. [CI and releases](#ci-and-releases)
13. [Conventions](#conventions)

---

## Overview and boot flow

```
F5 / exported game                        F6 / "run current scene"
──────────────────                        ────────────────────────
autoloads _ready()                        autoloads _ready()
Main.tscn (boot.gd)                       your scene, on its own
  ├─ show_splash? ─ yes ─► SplashScreen     (no boot, no menu, no redirect)
  │                          │ (timer or any input)
  └────── no ───────────────►┴► start_scene (MainMenu)
                                 └─ Play ─► GameScene (hello_world)
```

- **Full game (F5):** the main scene `globals/sceneManager/Main.tscn` runs `boot.gd`, which hands over to `SceneManager` and then removes itself. Change the start flow by selecting the root node of `Main.tscn` and editing its exports:
  - `start_scene`: which `SceneKey` to start in, e.g. `GameScene` to skip the menu while developing.
  - `show_splash`, `splash_scene`, `splash_time`.
- **Single scene (F6):** `Main.tscn` never loads, so the boot flow never runs, and the `SceneManager` autoload doesn't do anything on its own. Your scene runs exactly as it is. If it calls `SceneManager.change_scene()`, for example "back to menu", the manager takes the running scene over and replaces it normally.

**Rule:** never put start-up navigation in an autoload's `_ready()`. Autoloads also run for F6, so it would redirect every scene you try to debug. Start-up navigation belongs in `boot.gd`.

The **hello-world scene** (`scenes/game/hello_world/`) is a placeholder game showing input actions, an RNG stream, `Audio` and `SceneManager` in about 60 lines. Replace it with your game by pointing `SceneKey.GameScene` at your scene in `scene_registry.gd`.

## Autoloads

Autoloads are created in the order listed in **Project Settings → Globals → Autoload**, and each one's `_ready()` runs in that order:

1. `SignalBus`: first, because other autoloads emit on it from their `_ready()`.
2. `RngManager`
3. `Audio`: a **scene** (`audio_manager_node.tscn`), not a script, so its registries can be assigned in the inspector.
4. `SettingsManager`: loads `user://settings.cfg` and applies volumes, so it must come after the audio bus layout is active (always true) and after `SignalBus`.
5. `SceneManager`

**Gotcha:** an autoload's name and its script's `class_name` must not be the same, or the global is ambiguous. That's why the scene manager's script is `class_name MainRoot` while the autoload is called `SceneManager`.

## SignalBus

`globals/signalBus/signalBus.gd`. Holds signals that several unrelated systems care about, so they don't need references to each other.

```gdscript
# Listen
SignalBus.scene_change_finished.connect(_on_scene_change_finished)
# Emit
SignalBus.pause_toggled.emit(true)
```

Always use this typed form, never `connect("name", ...)` or `emit_signal("name")`. A typo then fails when the script is parsed instead of silently doing nothing.

| Signal | Emitted by | Arguments |
| --- | --- | --- |
| `scene_change_started` | `SceneManager` | `to_scene_key: int` (a `SceneRegistry.SceneKey`) |
| `scene_change_finished` | `SceneManager` | `new_scene: Node` |
| `setting_changed` | `SettingsManager.set_setting()` | `section, key, value` |
| `pause_toggled` | (game code; see [#23](https://github.com/brueningmax/godot_template/issues/23)) | `is_paused: bool` |

**Bus or direct signal?** Use the bus when the emitter shouldn't know who listens and the listeners are unrelated: HUD, audio and achievements reacting to the same event, or anything global. Use a normal signal for parent/child communication, e.g. a button telling its menu it was pressed. Passing everything through the bus makes data flow hard to follow.

**Adding a game signal:** put it in the `# --- Game ---` section of `signalBus.gd` with a `##` doc comment, which shows in the editor's help. Name it in the past tense, `noun_verbed`: `enemy_killed`, `card_played`, `level_completed`.

**Lifetime:** when a node is freed, Godot removes connections to its **methods** automatically, so `SignalBus.x.connect(_on_x)` needs no cleanup. **Lambdas are different.** A lambda stays connected until the object that *created* it is freed. If it only *captures* a node that is later freed, the next emit errors with "Lambda capture … was freed". From nodes that can be freed, connect methods, or disconnect lambdas in `_exit_tree()`.

**Trap: keep `signalBus.gd` free of references to `SceneRegistry` or game classes.** `SignalBus` is the first autoload, so whatever it references is compiled before the other autoloads exist. `SceneRegistry` `preload()`s every scene, so referencing it would compile every scene script too early, and they'd all fail with "Identifier not found: Audio" etc. That's why scene keys on the bus are typed as `int`.

## SettingsManager

`globals/settingsManager/settingsManager.gd`. Holds user preferences in sections, persists them to `user://settings.cfg` and applies them to the engine.

```gdscript
var vol: float = SettingsManager.get_setting("audio", "master_volume", 0.8)
SettingsManager.set_setting("display", "vsync", false)
```

Non-obvious behaviour:

- **Defaults live in the `_settings` dictionary** at the top of the script. On load, values from the file are merged over the defaults, so new keys you add to the dictionary appear automatically for existing players.
- **`set_setting()` applies and saves immediately**, writing the whole file on every call. Don't call it every frame, e.g. from a slider's `value_changed` while dragging, if that matters to you.
- It then emits `SignalBus.setting_changed(section, key, value)`.
- Only the `audio` and `display` sections are applied to the engine. Other sections are stored and saved, but you have to apply them yourself.
- Volumes are **linear 0–1**. They're converted to dB, and the bus is muted at ≤ 0.001.
- `fullscreen` defaults to `true`, which uses exclusive fullscreen.

> Planned: the settings menu wiring is tracked in [#4](https://github.com/brueningmax/godot_template/issues/4), and more settings in [#17](https://github.com/brueningmax/godot_template/issues/17).

## RngManager

`globals/rngManager/rngManager.gd` and `rngStream.gd`. All gameplay randomness should come from here, so a run can be reproduced from its seed.

Everything derives from one human-readable `seed_string`. There are two ways to draw numbers:

| Kind | API | Same seed ⇒ same result when… |
| --- | --- | --- |
| **Stream** | `RngManager.get_stream("loot").rand_int(1, 6)` | …the same calls happen on that stream in the same order. |
| **Keyed** | `RngManager.keyed_int_range("chest:3", 1, 6)` | …always. The result depends only on seed and key, not on call order. |

Use a separate stream per system (`"loot"`, `"map"`, `"ai"`), so adding a roll in one system doesn't shift every other system's results. Use keyed values for things that must not depend on order, e.g. "what's in chest 3", whichever chest is opened first.

**Seeding:**

```gdscript
RngManager.set_seed(seed_input.text)   # empty or whitespace -> random seed
var shown: String = RngManager.get_seed()  # e.g. "3FA9C01E": display it, save it
```

A random seed is also picked at startup, so randomness always works, even if nothing sets a seed. Generated seeds are 8 hex characters, so players can read them out in bug reports. Any text works as a seed.

`set_seed()` clears all cached streams. Streams fetched before the call keep their old state, so fetch streams again after reseeding instead of caching them across a reseed.

**Per-object streams:**

| API | Key | Use for |
| --- | --- | --- |
| `get_seeded_stream_for(obj, stable_id)` | the object's class/script + `stable_id` | Reproducible per-entity randomness, e.g. `stable_id = "chunk:42:enemy:3"`. Two objects of the same type with the same `stable_id` share one stream. |
| `get_unstable_stream_for(obj)` | the object's instance ID | Independent randomness per copy, where reproducing a run doesn't matter. Not stable across runs. |

All values are derived with 32-bit FNV-1a hashing of `seed + "|" + key`, so a given seed produces the same results on every platform.

## SceneManager and SceneRegistry

`globals/sceneManager/sceneManager.gd` (autoload `SceneManager`, class `MainRoot`) and `scene_registry.gd` (class `SceneRegistry`, **not** an autoload).

Scenes are referred to by enum key, never by path:

```gdscript
SceneManager.change_scene(SceneRegistry.SceneKey.MainMenu)
SceneManager.change_scene(SceneRegistry.SceneKey.GameScene, {"level": 2}, true)  # payload, fade
SceneManager.change_scene_with_screen(SceneRegistry.SceneKey.MainMenu, SceneRegistry.SceneKey.SplashScreen, 2.0)
```

To add a scene, add a value to `SceneKey` and an entry in `SCENES` in `scene_registry.gd`. Add new keys at the **end** of the enum: exported `SceneKey` values, e.g. `start_scene` on `Main.tscn`, are stored as numbers, so inserting a key in the middle shifts them.

**Intermediate screens** (splash, "chapter 2" cards) are shown by `change_scene_with_screen()` for `screen_time` seconds. To make a screen skippable, give its root script a `signal skipped` and emit it, e.g. on any input. The manager listens from the moment the screen is added, so a skip during its fade-in also counts. `scenes/ui/splash_screen/splash_screen.gd` is the example.

Non-obvious behaviour:

- **Don't use `get_tree().change_scene_to_file()`.** The manager keeps the active scene under `/root/SceneManager/SceneHolder`, and `get_tree().current_scene` is empty after boot. Use `SceneManager.current_scene` to get the active scene. (When you run a scene with F6, it is the tree's current scene until the first `change_scene()` takes it over.)
- **Calls during a transition are silently ignored**, because of the `_changing` flag. You don't get an error.
- **Payloads:** if the new scene has an `apply_payload(payload: Dictionary)` method, it's called **deferred**, after the scene's `_ready()`. Don't read payload data in `_ready()`.
- Intermediate screens (splash, loading) are added to the manager's `Overlay` CanvasLayer (layer 100), above the game.
- Every scene in `SCENES` is `preload()`ed, so all of them load at startup.

- Every change emits `SignalBus.scene_change_started` / `scene_change_finished`, and `SceneManager.scene_changed`.

> Planned: lazy, threaded loading with a loading screen is tracked in [#22](https://github.com/brueningmax/godot_template/issues/22).

## Audio

`globals/audioManager/`. The full reference is the [audio system README](../globals/audioManager/Readme.md). In short:

```gdscript
Audio.play(&"ui.click")
Audio.play_at(&"sfx.explosion", global_position)
Audio.music_layer_to(&"base", &"music.flow.base", 1.5)
```

There are two ways to refer to a sound.

**By ID:** for shared sounds used in many places (UI clicks, footsteps). An ID is `<registry namespace>.<set id>`, plus `.<cue id>` to address a single named variation. Registries are `.tres` files in `resources/audio/audioRegistries/`. To use one, add it to the `registries` array on `audio_manager_node.tscn`.

**By direct reference:** for sounds that belong to one scene. Keep the files next to the scene and play the resource itself, with no registry entry:

```
scenes/enemies/wolf/
  wolf.tscn
  wolf.gd
  howl.ogg
  bites.tres      # optional AudioSet with several bite variations
```

```gdscript
# wolf.gd
const HOWL := preload("howl.ogg")       # relative to this script
@export var bite_sounds: AudioSet       # or assign in the inspector

func howl() -> void:
	Audio.play_sound_at(HOWL, global_position)

func bite() -> void:
	Audio.play_sound(bite_sounds)       # picks a random variation
```

`play_sound`, `play_sound_at` and `play_sound_follow` accept an `AudioStream`, an `AudioCue` (adds volume, pitch and random-pitch settings) or an `AudioSet` (random variations). The bus is the set's bus, or `SFX` for streams and cues. You can override it with the last `bus` argument. Direct sounds share the same voice pools and limits as ID-based sounds.

Gotchas:

- Unknown IDs only log a warning, so a typo plays silence. A direct reference can't have that problem: a wrong `preload()` path fails when the script is parsed.
- Bus names are plain strings and must match `resources/audio/bus_layout.tres` exactly (`UI`, `SFX`, `Ambient`, `Music`).
- **Removing a registry:** delete it from the `registries` array on `audio_manager_node.tscn` **before** deleting the `.tres`. Otherwise the autoload logs load errors on every start.
- 3D playback uses `Vector3` / `Node3D`. There's no 2D positional (`AudioStreamPlayer2D`) variant yet.

## Menus and UI

- **`MenuBase`** (`scenes/ui/Menus/menu_base.gd`): base class for menus. `open()` / `close()` fade the menu in and out, and the tweens keep running while the game is paused. Set `default_focus` so keyboard and controller users land on a control. Override `_on_open()` / `_on_close()` for menu-specific behaviour.
- **`UIButton`** (`scenes/ui/components/ui_button/`): a `Button` wrapper with a hover lift and `ui.hover` / `ui.click` sounds through `Audio`. Set its label with the `text` property. Listen to the wrapper's `pressed` / `button_down` / `button_up` signals, not the inner button's. Hover also triggers on keyboard/controller focus, so focusing a button plays `ui.hover`.

**Making a new menu:**

1. Create a `Control` scene and attach a script that `extends MenuBase`.
2. Expose user actions as signals (`signal resume_pressed`) instead of acting directly. Whoever opens the menu decides what they do, so the same menu works from the main menu and in-game.
3. Set `default_focus` in `_ready()` (e.g. `default_focus = btn_resume.get_path()`).
4. Call `open()` / `close()` rather than toggling `visible`, so the fade and focus run.

`PauseMenu` and `SettingsMenu` follow this pattern but aren't opened anywhere yet. Wiring is tracked in [#4](https://github.com/brueningmax/godot_template/issues/4) (settings) and [#23](https://github.com/brueningmax/godot_template/issues/23) (pause and global state).

> Planned: controller support in [#16](https://github.com/brueningmax/godot_template/issues/16).

## Debug tools

**Scene library** (`scenes/debug/scene_library/`): opened from the main menu's **Debug** button. It lists every `.tscn` under `res://scenes`, previews the selected one in a viewport (3D scenes get an orbit camera) and launches it.

Gotcha: previewing **instantiates** the scene, so its `_ready()` runs, along with any side effects (sounds, autoload calls, changing the mouse mode).

> Planned: a debug overlay and console are tracked in [#20](https://github.com/brueningmax/godot_template/issues/20), and logging in [#19](https://github.com/brueningmax/godot_template/issues/19).

### Script checker

`tools/check_scripts.gd` compiles every `.gd` file in the project (skipping `addons/`) and lists the ones that fail. Its exit code is the number of failures:

```bash
godot --headless --script res://tools/check_scripts.gd
```

Use it instead of `godot --check-only --script file.gd`. That mode doesn't create the autoloads, so every script that uses `SignalBus`, `Audio`, etc. reports a false "Identifier not found" error.

## Debugging in VS Code

> Planned: [#5](https://github.com/brueningmax/godot_template/issues/5).

## Testing

`test/` contains manual test scenes (`test_settings.tscn`, `test_signals.tscn`). Run one with **F6** in the editor.

> Planned: automated headless tests are tracked in [#8](https://github.com/brueningmax/godot_template/issues/8).

## CI and releases

> Planned: lint and format in [#7](https://github.com/brueningmax/godot_template/issues/7), CI in [#9](https://github.com/brueningmax/godot_template/issues/9), exports and releases in [#10](https://github.com/brueningmax/godot_template/issues/10).

## Conventions

> Planned: [#14](https://github.com/brueningmax/godot_template/issues/14).
