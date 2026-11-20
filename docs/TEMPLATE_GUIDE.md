# Template Guide

How the template's systems work, how to use them, and what isn't obvious from the code. Every section describes the code **as it is now**. Where a system is still planned, the section links to its issue instead of describing it.

> **Maintaining this file:** any change that adds a system or changes how one behaves updates its section here in the same PR.

## Contents

0. [Starting a new game from the template](#starting-a-new-game-from-the-template)
1. [Overview and boot flow](#overview-and-boot-flow)
2. [Autoloads](#autoloads)
3. [SignalBus](#signalbus)
4. [SettingsManager](#settingsmanager)
5. [RngManager](#rngmanager)
6. [GameState and pausing](#gamestate-and-pausing)
6. [SceneManager and SceneRegistry](#scenemanager-and-sceneregistry)
7. [Audio](#audio)
8. [Menus and UI](#menus-and-ui)
9. [Debug tools](#debug-tools)
10. [Debugging in VS Code](#debugging-in-vs-code)
11. [Testing](#testing)
12. [CI and releases](#ci-and-releases)
13. [Conventions](#conventions)

---

## Starting a new game from the template

### With GitHub ("Use this template")

1. On the template's GitHub page, click **Use this template → Create a new repository**.
2. The new repository's first push runs `.github/workflows/template-setup.yml` once:
   - sets `config/name` in `project.godot` to the repository name (e.g. `my-deckbuilder`)
   - replaces the template README with a short stub
   - commits both as **"Set up project from template"**
3. Pull that commit, then open the project in Godot.

The workflow does nothing on later pushes: it only acts while `project.godot` still has the template's name. You can delete the file afterwards. It can't delete itself, because GitHub's built-in token isn't allowed to change workflow files. It never runs in the template repository itself or in forks.

### Without GitHub (or to choose a different name)

```bash
git clone --depth 1 https://github.com/brueningmax/godot_template.git my-game
```
```bash
cd my-game && rm -rf .git && git init
```
```bash
godot --headless --script res://tools/rename_project.gd -- "My Game"
```

The last command is the cross-platform rename tool. It works on Windows too (`godot` being your Godot executable), and you can rerun it any time to rename a project. It changes only the `config/name` line of `project.godot`.

**Rename before the first real run.** The project name also decides the **user data folder** that `user://` points to, which holds settings, saves and logs. Renaming later starts the game with empty user data, because the old folder keeps the old name. After renaming, delete the `.godot/` folder (editor cache) and reopen the project.

## Overview and boot flow

```
F5 / exported game                        F6 / "run current scene"
──────────────────                        ────────────────────────
autoloads _ready()                        autoloads _ready()
main.tscn (boot.gd)                       your scene, on its own
  ├─ show_splash? ─ yes ─► SPLASH_SCREEN    (no boot, no menu, no redirect)
  │                          │ (timer or any input)
  └────── no ───────────────►┴► start_scene (MAIN_MENU)
                                 └─ Play ─► GAME_SCENE (hello_world)
```

- **Full game (F5):** the main scene `globals/scene_manager/main.tscn` runs `boot.gd`, which hands over to `SceneManager` and then removes itself. Change the start flow by selecting the root node of `main.tscn` and editing its exports:
  - `start_scene`: which `SceneKey` to start in, e.g. `GAME_SCENE` to skip the menu while developing.
  - `show_splash`, `splash_scene`, `splash_time`.
- **Single scene (F6):** `main.tscn` never loads, so the boot flow never runs, and the `SceneManager` autoload doesn't do anything on its own. Your scene runs exactly as it is. If it calls `SceneManager.change_scene()`, for example "back to menu", the manager takes the running scene over and replaces it normally.

**Rule:** never put start-up navigation in an autoload's `_ready()`. Autoloads also run for F6, so it would redirect every scene you try to debug. Start-up navigation belongs in `boot.gd`.

The **hello-world scene** (`scenes/game/hello_world/`) is a placeholder game showing input actions, an RNG stream, `Audio` and `GameState` (Esc pauses) in about 60 lines. Replace it with your game by pointing `SceneKey.GAME_SCENE` at your scene in `scene_registry.gd`.

## Autoloads

Autoloads are created in the order listed in **Project Settings → Globals → Autoload**, and each one's `_ready()` runs in that order:

1. `SignalBus`: first, because other autoloads emit on it from their `_ready()`.
2. `RngManager`
3. `Audio`: a **scene** (`audio_manager_node.tscn`), not a script, so its registries can be assigned in the inspector.
4. `SettingsManager`: loads `user://settings.cfg` and applies volumes, so it must come after the audio bus layout is active (always true) and after `SignalBus`.
5. `GameState`
6. `SceneManager`

**Gotcha:** an autoload's name and its script's `class_name` must not be the same, or the global is ambiguous. That's why the scene manager's script is `class_name MainRoot` while the autoload is called `SceneManager`.

## SignalBus

`globals/signal_bus/signal_bus.gd`. Holds signals that several unrelated systems care about, so they don't need references to each other.

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
| `game_state_changed` | `GameState` | `new_state, old_state: int` (`GameState.State`) |
| `pause_toggled` | `GameState.pause()` / `resume()` | `is_paused: bool` |

**Bus or direct signal?** Use the bus when the emitter shouldn't know who listens and the listeners are unrelated: HUD, audio and achievements reacting to the same event, or anything global. Use a normal signal for parent/child communication, e.g. a button telling its menu it was pressed. Passing everything through the bus makes data flow hard to follow.

**Adding a game signal:** put it in the `# --- Game ---` section of `signal_bus.gd` with a `##` doc comment, which shows in the editor's help. Name it in the past tense, `noun_verbed`: `enemy_killed`, `card_played`, `level_completed`.

**Lifetime:** when a node is freed, Godot removes connections to its **methods** automatically, so `SignalBus.x.connect(_on_x)` needs no cleanup. **Lambdas are different.** A lambda stays connected until the object that *created* it is freed. If it only *captures* a node that is later freed, the next emit errors with "Lambda capture … was freed". From nodes that can be freed, connect methods, or disconnect lambdas in `_exit_tree()`.

**Trap: only `SceneManager` may read `SceneRegistry.SCENES`.** `SCENES` `preload()`s every registered scene, and those scenes' scripts use the autoloads. If an autoload or a scene script reads `SCENES`, Godot sees a cycle and every affected script fails with "Could not resolve member \"SCENES\": Cyclic reference". Using the enum (`SceneRegistry.SceneKey.MAIN_MENU`) is fine anywhere. ([#22](https://github.com/brueningmax/godot_template/issues/22) removes the cause by storing paths instead of preloads.)

## SettingsManager

`globals/settings_manager/settings_manager.gd`. Holds user preferences in sections, persists them to `user://settings.cfg` and applies them to the engine.

```gdscript
var vol: float = SettingsManager.get_setting("audio", "master_volume", 0.8)
SettingsManager.set_setting("display", "vsync", false)
```

Non-obvious behaviour:

- **Defaults live in the `DEFAULTS` constant** at the top of the script. On load, values from the file are merged over the defaults, so new keys you add there appear automatically for existing players. `reset_to_defaults()` puts everything back to `DEFAULTS` (without saving).
- The file is `settings_path` (default `user://settings.cfg`). Tests point it at a temporary file so they never touch the player's settings.
- **`set_setting()` applies and saves immediately** by default, writing the whole file. Pass `persist = false` to apply without saving (`set_setting("audio", "music_volume", v, false)`), e.g. while a slider is dragged, and call `save_settings()` when you're done.
- `snapshot()` returns a deep copy of every setting, and `restore(snapshot)` applies one again without saving. The settings menu uses these to revert.
- It then emits `SignalBus.setting_changed(section, key, value)`.
- Only the `audio` and `display` sections are applied to the engine. Other sections are stored and saved, but you have to apply them yourself.
- Volumes are **linear 0–1**. They're converted to dB, and the bus is muted at ≤ 0.001.
- `fullscreen` defaults to `true`, which uses exclusive fullscreen.

### Settings menu

`scenes/ui/menus/settings_menu/`, opened by **Options** in the main menu and **Settings** in the pause menu, both through `GameState.open_settings()`.

- **Preview, Apply, Back:** every change applies immediately, so you hear and see it, but it isn't saved. **Apply** saves and closes. **Back** or Esc restores the values from when the menu opened.
- The rows are built at runtime from the `ROWS` list at the top of `settings_menu.gd`.

### Adding a setting end to end

1. **Default:** add the key to `DEFAULTS` in `settings_manager.gd`, e.g. `"display": {..., "max_fps": 0}`. Existing players get the default automatically.
2. **Apply:** handle the key in `_apply_display()` (or a new `_apply_<section>()` added to the `match` in `_apply_setting()`), e.g. `"max_fps": Engine.max_fps = value`.
3. **Menu:** add one entry to `ROWS` in `settings_menu.gd`: `{section = "display", key = "max_fps", label = "FPS cap", type = RowType.SLIDER}`. Sliders currently cover 0–1. A different range or a dropdown needs a new `RowType`.

> Planned: more settings (window mode, resolution, UI scale, language, FPS cap) in [#17](https://github.com/brueningmax/godot_template/issues/17).

## RngManager

`globals/rng_manager/rng_manager.gd` and `rng_stream.gd`. All gameplay randomness should come from here, so a run can be reproduced from its seed.

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

## GameState and pausing

`globals/game_state/game_state.gd`. Tracks whether the player is in a menu, playing, or paused, and is the **only** code that sets `get_tree().paused` and `Input.mouse_mode`. It's also the only handler of the `pause` action.

```
             enter_menu()                  enter_gameplay(mouse_mode)
   ┌──────┐ ◄───────────── ┌─────────┐ ◄─────────────────────────────
   │ MENU │                │ PLAYING │ ── Esc (pause) ──► ┌────────┐
   └──────┘ ─────────────► └─────────┘ ◄── Esc / Resume ── │ PAUSED │
                                                          └────────┘
```

**Every scene declares its state in `_ready()`:**

```gdscript
func _ready() -> void:
	GameState.enter_gameplay(Input.MOUSE_MODE_CAPTURED)  # a gameplay scene
	# or
	GameState.enter_menu()                               # a menu scene
```

This works the same when the scene is run on its own (F6), because `GameState` is an autoload and doesn't depend on the boot flow. A scene that declares nothing stays in whatever state the previous scene left (`MENU` at start-up), so Esc does nothing there.

**What Esc does:**

| State | `pause` (Esc) | `ui_cancel` (Esc, gamepad B) |
| --- | --- | --- |
| `PLAYING` | pause: tree paused, cursor shown, pause menu opened | nothing (B is often a gameplay button) |
| `PAUSED` | back one step: settings → pause menu → resume | same |
| `MENU` with an overlay menu open | close it | same |
| during a scene transition | ignored | ignored |

**Mouse mode:** the mode passed to `enter_gameplay()` is restored on every resume. Menus always get a visible cursor. Don't set `Input.mouse_mode` anywhere else, or the two will fight.

**Pause menu buttons:** Resume → `resume()`, Settings → the [settings menu](#settings-menu) (overlay), Restart → `SceneManager.reload_current()`, Quit → main menu. Starting any scene change also unpauses and closes overlays, so a paused tree never leaks into the next scene.

**Overlay menus:** `GameState.push_menu(menu)` / `pop_menu()` show menus over the current scene on a `CanvasLayer` (layer 50, below the scene fade). They show a dimmer and handle back navigation. Menus are reused: popping hides a menu rather than freeing it. `GameState.open_settings()` opens the shared settings menu.

**`process_mode` rules for a paused tree:**

- Default (`INHERIT` → `PAUSABLE`): the node freezes while paused. That's right for gameplay.
- `WHEN_PAUSED`: runs only while paused, for pause-only UI.
- `ALWAYS`: never freezes. Use it for things like music fades and debug overlays. Overlay menus pushed through `GameState` are set to `ALWAYS`.
- Tweens follow the node that created them. Use `create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` for tweens that must run while paused (as `MenuBase` and the scene fades do).
- Timers: `get_tree().create_timer(sec, true)` keeps running while paused. The default is to pause with the tree.

## SceneManager and SceneRegistry

`globals/scene_manager/scene_manager.gd` (autoload `SceneManager`, class `MainRoot`) and `scene_registry.gd` (class `SceneRegistry`, **not** an autoload).

Scenes are referred to by enum key, never by path:

```gdscript
SceneManager.change_scene(SceneRegistry.SceneKey.MAIN_MENU)
SceneManager.change_scene(SceneRegistry.SceneKey.GAME_SCENE, {"level": 2}, true)  # payload, fade
SceneManager.change_scene_with_screen(SceneRegistry.SceneKey.MAIN_MENU, SceneRegistry.SceneKey.SPLASH_SCREEN, 2.0)
SceneManager.reload_current()   # restart the current scene from its file
```

To add a scene, add a value to `SceneKey` and an entry in `SCENES` in `scene_registry.gd`. Add new keys at the **end** of the enum: exported `SceneKey` values, e.g. `start_scene` on `main.tscn`, are stored as numbers, so inserting a key in the middle shifts them.

**Intermediate screens** (splash, "chapter 2" cards) are shown by `change_scene_with_screen()` for `screen_time` seconds. To make a screen skippable, give its root script a `signal skipped` and emit it, e.g. on any input. The manager listens from the moment the screen is added, so a skip during its fade-in also counts. `scenes/ui/splash_screen/splash_screen.gd` is the example.

Non-obvious behaviour:

- **Don't use `get_tree().change_scene_to_file()`.** The manager keeps the active scene under `/root/SceneManager/SceneHolder`, and `get_tree().current_scene` is empty after boot. Use `SceneManager.current_scene` to get the active scene. (When you run a scene with F6, it is the tree's current scene until the first `change_scene()` takes it over. Setting `SceneManager.adopt_standalone = false` disables that; the test base class does so, so GUT's own runner scene is never taken over.)
- **Calls during a transition are silently ignored.** You don't get an error. Check `SceneManager.is_changing()` if it matters.
- The old scene is removed from the tree **before** the new one is added, so a reloaded scene keeps its node name (`HelloWorld`, not `@HelloWorld@2`) and node paths stay valid.
- Fades and screen timers keep running even if the tree is paused.
- **Payloads:** if the new scene has an `apply_payload(payload: Dictionary)` method, it's called **deferred**, after the scene's `_ready()`. Don't read payload data in `_ready()`.
- Intermediate screens (splash, loading) are added to the manager's `Overlay` CanvasLayer (layer 100), above the game.
- Every scene in `SCENES` is `preload()`ed, so all of them load at startup.

- Every change emits `SignalBus.scene_change_started` / `scene_change_finished`, and `SceneManager.scene_changed`.

> Planned: lazy, threaded loading with a loading screen is tracked in [#22](https://github.com/brueningmax/godot_template/issues/22).

## Audio

`globals/audio_manager/`. The full reference is the [audio system README](../globals/audio_manager/README.md). In short:

```gdscript
Audio.play(&"ui.click")
Audio.play_at(&"sfx.explosion", global_position)
Audio.music_layer_to(&"base", &"music.flow.base", 1.5)
```

There are two ways to refer to a sound.

**By ID:** for shared sounds used in many places (UI clicks, footsteps). An ID is `<registry namespace>.<set id>`, plus `.<cue id>` to address a single named variation. Registries are `.tres` files in `resources/audio/audio_registries/`. To use one, add it to the `registries` array on `audio_manager_node.tscn`.

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

- **`MenuBase`** (`scenes/ui/menus/menu_base.gd`): base class for menus. `open()` / `close()` fade the menu in and out, and the tweens keep running while the game is paused. Set `default_focus` so keyboard and controller users land on a control. Override `_on_open()` / `_on_close()` for menu-specific behaviour.
- **`UIButton`** (`scenes/ui/components/ui_button/`): a `Button` wrapper with a hover lift and `ui.hover` / `ui.click` sounds through `Audio`. Set its label with the `text` property. Listen to the wrapper's `pressed` / `button_down` / `button_up` signals, not the inner button's. Hover also triggers on keyboard/controller focus, so focusing a button plays `ui.hover`.

**Making a new menu:**

1. Create a `Control` scene and attach a script that `extends MenuBase`.
2. Expose user actions as signals (`signal resume_pressed`) instead of acting directly. Whoever opens the menu decides what they do, so the same menu works from the main menu and in-game.
3. Set `default_focus` in `_ready()` (e.g. `default_focus = btn_resume.get_path()`).
4. Call `open()` / `close()` rather than toggling `visible`, so the fade and focus run.

`default_focus` may point at a wrapper such as a `UIButton`. The first focusable control inside it gets focus.

`PauseMenu` and `SettingsMenu` are opened by [`GameState`](#gamestate-and-pausing) as overlay menus. They only emit signals and contain no pause or input logic of their own.

**Back / Esc in overlay menus:** if the menu on top has a `cancel()` method, Esc calls it, and the menu closes itself by emitting its back signal. The settings menu reverts its changes there. Menus without `cancel()` are simply closed.

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

The template is set up for the **godot-tools** extension (`geequlim.godot-tools`, version 2.x). VS Code launches the game itself and acts as its debugger: breakpoints, stepping, the call stack, variables, and `print()` output in the Debug Console. The Godot editor doesn't need to be open for debugging.

### One-time setup

1. Install the recommended extension. VS Code offers it when you open the folder; it's listed in `.vscode/extensions.json`.
2. Set your Godot 4 executable in your VS Code **User** settings (Ctrl+, → User → search "godot editor path"):
   ```json
   "godotTools.editorPath.godot4": "C:/Tools/Godot/Godot_v4.7-stable_win64.exe"
   ```
   Don't put it in the workspace `.vscode/settings.json`. That file is committed, and a workspace value overrides every developer's own path.
3. Optional, so the Godot editor opens scripts in VS Code: in Godot go to **Editor Settings → Text Editor → External**, enable **Use External Editor**, set **Exec Path** to VS Code, and set **Exec Flags** to `{project} --goto {file}:{line}:{col}`. Also enable **Text Editor → Behavior → Files → Auto Reload Scripts on External Change**.

### Configurations (Run and Debug panel)

| Configuration | Runs | Use it for |
| --- | --- | --- |
| **Godot: Run game** | the main scene, so the full [boot flow](#overview-and-boot-flow) | Playing through splash → menu → game. |
| **Godot: Run current scene** | the scene open in the editor (or the scene belonging to the open `.gd`) | Debugging one scene. Like F6: no boot flow and no menu redirect. Works for scenes in subfolders. |
| **Godot: Run pinned scene** | the scene you pinned with the extension's "Pin scene" command | Repeatedly launching one scene while editing other files. |
| **Godot: Attach** | nothing; connects to a game that's already running | A game started with `--remote-debug tcp://127.0.0.1:6010`. |

### Language server (completion, go-to-definition)

The language server is provided by the **Godot editor**, so keep the project open in Godot. `.vscode/settings.json` sets `godotTools.lsp.serverPort` to **6005**, the Godot editor's default (**Editor Settings → Network → Language Server → Remote Port**). If you change one, change both.

Alternatively, set `"godotTools.lsp.headless": true` in your User settings, and the extension starts its own windowless Godot for the language server.

### Pitfalls

- **Port 6007 clash:** the Godot editor's own debugger listens on 6007, the extension's default. The template's configurations use **6010** so they work with the editor open. Keep it that way if you add configurations.
- **No completion / "Couldn't connect to the GDScript language server":** the Godot editor isn't running, or the LSP ports don't match (see above).
- **"Run current scene" ran the wrong thing:** it uses the file focused in VS Code. Focus the `.tscn`, or the `.gd` attached to it, before pressing F5.
- **Breakpoints in `@tool` scripts** only trigger in the running game, not while the script runs in the editor.
- Autoloads run for every configuration, including the single-scene ones, which is why start-up navigation lives in `boot.gd` and not in an autoload.

## Testing

Automated tests use **[GUT](https://github.com/bitwes/Gut) 9.7.1** (the GUT release for Godot 4.7), vendored in `addons/gut/`.

```
test/
  unit/            pure logic: RngManager, SettingsManager, SceneRegistry
  integration/     real autoloads: scene changes, pause, menus, audio, boot
  sandbox/         click-through scenes for poking at things by hand (F6)
  template_test.gd base class for integration tests
.gutconfig.json    which folders run, test_ prefix, exit when done
```

### Running tests

| Where | How |
| --- | --- |
| Command line | `godot --headless -s addons/gut/gut_cmdln.gd` (all tests; exit code 1 if any fail) |
| One file | add `-gselect=test_game_state` |
| One test | add `-gselect=test_game_state -gunit_test_name=test_pause_and_resume` |
| VS Code | **Terminal → Run Task → Run all tests** (or **Run tests in current file**). Uses your `godotTools.editorPath.godot4` User setting. |
| Godot editor | the **GUT** panel at the bottom (the plugin is enabled in Project Settings → Plugins) |

The suite runs headless in about 10 seconds.

### Writing a test

Create `test/unit/test_<thing>.gd` (pure logic) or `test/integration/test_<thing>.gd` (needs scenes or the pause state). Every function starting with `test_` is a test.

```gdscript
extends GutTest   # integration tests: extends TemplateTest

func test_seed_reproduces() -> void:
	RngManager.set_seed("abc")
	var first := RngManager.keyed_u32("x")
	RngManager.set_seed("abc")
	assert_eq(RngManager.keyed_u32("x"), first)
```

- **Autoloads** (`RngManager`, `SettingsManager`, `GameState`, …) are available in tests by name, exactly as in game code.
- **`await` works in tests.** Use `await wait_process_frames(n)`, `await wait_seconds(t)` or `await wait_until(func(): return cond, max_seconds)`. Never use a bare `await get_tree().process_frame` loop without a limit, because a broken test would then hang the whole run.
- **Errors fail tests:** GUT counts engine errors and `push_error()` as failures. If a test triggers one on purpose, assert it with `assert_push_error("text")`. Warnings don't fail tests.
- **Free what you create:** `autofree(Node.new())` or `add_child_autofree(node)`, so nodes don't leak into later tests.

### `TemplateTest` (integration tests)

`test/template_test.gd` resets global state **after each test**: it waits for any scene transition, unpauses, closes overlay menus, `GameState.enter_menu()`, and frees `SceneManager.current_scene`. It also provides helpers:

- `await goto(SceneRegistry.SceneKey.MAIN_MENU)`: change scene and wait for it.
- `await press("pause")`: send an input action.
- `overlay_menu("PauseMenu")`: find a menu opened by `GameState`.
- `await wait_for_transition()`.

Two things it handles that you'd otherwise trip over:

1. **Pausing doesn't freeze the tests.** GUT's own nodes would stop with `get_tree().paused = true`, and every following `wait_*()` would never return. `TemplateTest` runs GUT with `PROCESS_MODE_ALWAYS`.
2. **GUT's runner scene is never "adopted"** by `SceneManager` (`adopt_standalone = false`). The adoption tests turn it on deliberately.

If you override `before_all()`, `after_all()` or `after_each()` in a `TemplateTest`, call the `super` version (`await super.after_each()`).

### Sandbox scenes

`test/sandbox/signals_sandbox.tscn` and `settings_sandbox.tscn` are interactive. Run one with F6 to watch bus signals or tweak settings by hand. They aren't part of the automated run.

## CI and releases

### What CI checks

`.github/workflows/ci.yml` runs on every pull request and on every push to `main`. It installs gdtoolkit and Godot (cached between runs) and then runs **`tools/check.sh`**, which runs these steps in order and stops at the first failure:

| Step | Fails when |
| --- | --- |
| Tool versions | gdtoolkit in `requirements-dev.txt` differs from `rev:` in `.pre-commit-config.yaml` |
| `gdformat --check .` | a script isn't formatted (fix: `gdformat .`) |
| `gdlint .` | a lint rule is broken |
| Import (`--import`) | the import log has `ERROR:` / `SCRIPT ERROR:` lines (missing files, broken references) |
| `tools/check_scripts.gd` | a script doesn't compile |
| Smoke run: full game | the boot → splash → main menu run logs an error |
| Smoke run: `hello_world.tscn` | running that scene on its own logs an error |
| Tests (GUT) | any test fails |

**Why the log scanning:** Godot exits with code 0 even when scenes or resources fail to load. The problems only appear as `ERROR:` lines in its output. `tools/check.sh` therefore scans the logs instead of trusting the exit code.

The smoke runs use `--fixed-fps 60`, so "N frames" means a fixed amount of game time. Headless Godot would otherwise run frames as fast as it can, and finish before the 2-second splash is over.

Logs and a JUnit test report (`junit.xml`) end up in `.godot/check-logs/`, which CI uploads as the **check-logs** artifact of each run.

### Running the same checks locally

```bash
pip install -r requirements-dev.txt
```
```bash
tools/check.sh
```
```bash
GODOT=/path/to/godot tools/check.sh
```

The last form is for when `godot` isn't on your PATH. It works on Linux and macOS, and on Windows in Git Bash. A full run takes about 20 seconds.

### Bumping the Godot version

The version is pinned in several places that must agree:

1. `GODOT_VERSION` in `.github/workflows/ci.yml`.
2. `config/features` in `project.godot` (Godot updates it when you open the project in the new editor).
3. **GUT:** replace `addons/gut/` with the GUT release built for that Godot version (GUT's README has a table).
4. If you use a cloud dev environment, the Godot version in its setup script.

> Planned: exports and releases in [#10](https://github.com/brueningmax/godot_template/issues/10).

## Conventions

### Code style

Scripts follow the [official GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html), enforced by [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) (version pinned in `requirements-dev.txt`):

```bash
pip install -r requirements-dev.txt
```
```bash
gdformat .          # format all scripts in place
```
```bash
gdlint .            # lint; "Success: no problems found" is the goal
```

`gdlintrc` holds the lint rules. They're gdtoolkit's defaults, except that private signals may start with an underscore (`signal _screen_finished`), like private functions and variables.

Rules that aren't obvious:

- **Order of declarations in a script:** `@tool` → `class_name` → `extends` → doc comment → signals → enums → constants → static vars → `@export` vars → public vars → private (`_`) vars → `@onready` vars → functions.
- **Names:** `snake_case` functions and variables, `PascalCase` classes and enum names, `CONSTANT_CASE` constants and **enum values** (`SceneKey.MAIN_MENU`).
- **Lines** are at most 100 characters. For long node paths, mark the node **Access as Unique Name** in the scene and use `%NodeName` instead of `$A/B/C/NodeName`.
- `gdformat` joins argument lists back onto one line when they fit, so don't hand-wrap short signatures; it will undo it.
- `@export_category()` only groups **exported** properties in the inspector. Use `# --- Section ---` comments to divide code.

### Pre-commit hooks (optional)

`.pre-commit-config.yaml` runs gdtoolkit's official hooks on the `.gd` files you commit. Third-party code in `addons/` is skipped.

```bash
pip install -r requirements-dev.txt
```
```bash
pre-commit install
```
```bash
pre-commit install --hook-type pre-push
```

The second command enables the per-commit hooks. The third is optional: it also runs the full `tools/check.sh` before every push (about 20 s, needs Godot on `PATH` or `GODOT=`).

| Hook | When | What happens |
| --- | --- | --- |
| `gdformat` | commit | Formats the staged scripts **in place**. If it changed anything, the commit stops: review the change, `git add` and commit again. |
| `gdlint` | commit | Reports lint errors and blocks the commit until they're fixed. |
| `full-check` | push (opt-in) | Runs `tools/check.sh`, the same checks as CI. |

- Skip the hooks once with `git commit --no-verify` (or `git push --no-verify`). CI still runs everything.
- Run them on every file: `pre-commit run --all-files`.
- **Updating gdtoolkit:** change the version in **both** `requirements-dev.txt` and `rev:` in `.pre-commit-config.yaml`. `tools/check.sh` (and so CI) fails if the two differ.
- **Windows:** commit from a terminal where Python and `pre-commit` are on `PATH`. A GUI client that can't find them reports the hook as failed.

### Repository hygiene

`.gitignore` is grouped and commented. In short, Git ignores:

- **Godot:** the `.godot/` cache, generated `*.translation` files, and `export_credentials.cfg` (export signing keys and passwords, which must never be committed).
- **Builds:** `/build/`, where exports go.
- **OS and editor clutter:** `.DS_Store`, `Thumbs.db`, `.idea/`, swap files, and everything in `.vscode/` **except** the four shared files (`launch.json`, `settings.json`, `extensions.json`, `tasks.json`).
- **Python dev tools:** `__pycache__/`, `.venv/`.

Commit `*.import` and `*.uid` files: Godot needs them to keep resource IDs and import settings stable for everyone.

`.gitattributes` normalises text files to LF line endings and marks images, audio, fonts and models as **binary**, so Git never diffs them or converts their line endings.

### Enabling Git LFS in your game

[Git LFS](https://git-lfs.com) stores large binary files (music, textures, models) outside the normal Git history. The repository holds small pointer files, and each checkout downloads only the versions it needs. The template doesn't enable it, since its assets are about 100 KB. Turn it on in a game once real assets start arriving. Early is easier than late.

1. Install Git LFS once per machine: `git lfs install`.
2. In `.gitattributes`, uncomment the lines in the Git LFS block, by hand or with the command below (on macOS write `sed -i '' -E ...`), then commit `.gitattributes`.
   ```bash
   sed -i -E 's/^# (\*\.[a-z0-9]+ filter=lfs .*)$/\1/' .gitattributes
   ```
3. Move assets that are already committed into LFS. **This rewrites history.** Do it before others clone, or coordinate a re-clone:
   ```bash
   git lfs migrate import --everything --include="*.png,*.jpg,*.webp,*.exr,*.psd,*.kra,*.aseprite,*.ogg,*.wav,*.mp3,*.glb,*.blend,*.fbx"
   ```
   Then push with `git push --force-with-lease`.
4. Check: `git lfs ls-files` lists the tracked files.

Good to know:

- Everyone who clones needs Git LFS installed. Without it they get pointer files instead of assets, and Godot reports import errors (CI's import step would catch that).
- CI already checks out with `lfs: true`.
- GitHub limits free LFS storage and download bandwidth. Check your plan's quota if the project has many large assets or CI runs.

> Planned: folder and file naming, contribution flow: [#14](https://github.com/brueningmax/godot_template/issues/14).
