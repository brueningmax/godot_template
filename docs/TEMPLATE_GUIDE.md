# Template Guide

How the template's systems work, how to use them, and what isn't obvious from the code. Every section describes the code **as it is now**. Where a system is still planned, the section links to its issue instead of describing it.

> **Maintaining this file:** any change that adds a system or changes how one behaves updates its section here in the same PR.

## Contents

1. [Starting a new game from the template](#starting-a-new-game-from-the-template)
2. [Overview and boot flow](#overview-and-boot-flow)
3. [Autoloads](#autoloads)
4. [Logging](#logging)
5. [SignalBus](#signalbus)
6. [SettingsManager](#settingsmanager)
7. [SaveManager](#savemanager)
8. [Data definitions](#data-definitions)
9. [Command queue](#command-queue)
10. [RngManager](#rngmanager)
11. [GameState and pausing](#gamestate-and-pausing)
12. [SceneManager and SceneRegistry](#scenemanager-and-sceneregistry)
13. [Audio](#audio)
14. [Menus and UI](#menus-and-ui)
15. [Localization](#localization)
16. [Debug tools](#debug-tools)
17. [Debugging in VS Code](#debugging-in-vs-code)
18. [Testing](#testing)
19. [CI and releases](#ci-and-releases)
20. [Conventions](#conventions)

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

1. `Log`: first, so every other autoload can log from its `_ready()`. It depends on nothing.
2. `SignalBus`: before the rest, because they emit on it from their `_ready()`.
3. `RngManager`
4. `Audio`: a **scene** (`audio_manager_node.tscn`), not a script, so its registries can be assigned in the inspector.
5. `SettingsManager`: loads `user://settings.cfg` and applies volumes, so it must come after the audio bus layout is active (always true) and after `SignalBus`.
6. `GameState`
7. `SaveManager`: after `GameState`, whose state decides when play time counts.
8. `Definitions`: loads and checks all data definitions (`res://data/`), so they're ready before any scene runs.
9. `SceneManager`
10. `Debug`: a **scene** (`globals/debug/debug.tscn`) so its options are editable in the inspector. Last, because it uses all the others.

**Gotcha:** an autoload's name and its script's `class_name` must not be the same, or the global is ambiguous. That's why the scene manager's script is `class_name MainRoot` while the autoload is called `SceneManager`.

## Logging

`globals/log/log.gd`, autoload `Log`. Use it instead of `print()`, `push_warning()` and `push_error()` in game code.

```gdscript
Log.debug(&"Cards", "drew %s" % card.id)
Log.info(&"Scene", "changed to %s" % scene.name)
Log.warn(&"Audio", "unknown id '%s'" % id)
Log.error(&"Save", "can't write %s" % path)
```

The output looks like `[12:03:04.123] [WARN ] [Audio] unknown id 'ui.x'`. The category is any short name, usually the system or feature (`Scene`, `Audio`, `Cards`).

**Where messages go:**

| Level | Sent with | Effect |
| --- | --- | --- |
| `debug`, `info` | `print()` | Output panel, terminal, log file |
| `warn` | `push_warning()` | also yellow in the **Debugger → Errors** tab, with a backtrace |
| `error` | `push_error()` | also red in the Debugger, **fails GUT tests** unless asserted, **fails CI** (`ERROR:` lines) |

Because messages go through Godot's own functions, Godot's **log file** gets them too: `user://logs/godot.log`, the newest 5 runs kept (Project Settings → Debug → File Logging). `user://` is `%APPDATA%\Godot\app_userdata\<project name>\` on Windows, `~/Library/Application Support/Godot/app_userdata/<project name>/` on macOS and `~/.local/share/godot/app_userdata/<project name>/` on Linux.

**Levels and filtering:**

- `debug` and `info` can be filtered; `warn` and `error` are **always** logged, so problems can't be hidden by accident.
- The default minimum level is `DEBUG` in debug builds and `INFO` in release builds (`Log.min_level`).
- Per category: `Log.set_level(&"Audio", Log.Level.WARN)` (quieter) or `Log.Level.DEBUG` (louder); `Log.clear_level(&"Audio")` undoes it.
- From the command line, after `--`, without changing code:
  ```bash
  godot -- --log-level=info
  ```
  ```bash
  godot -- --log=Audio:debug,Scene:warn
  ```
  In VS Code, put the same options in a launch configuration's `additional_options`. Unknown options are reported as a warning.
- To avoid building an expensive message that would be filtered out, check first: `if Log.is_enabled(Log.Level.DEBUG, &"AI"): Log.debug(&"AI", _dump_state())`.

**Recent messages (for in-game consoles):** `Log.recent(n)` returns the last entries, up to 200, oldest first, as dictionaries with `level`, `category`, `message`, `time` and `text`. `Log.message_logged(entry)` fires for each new one, always on the main thread. The buffer also captures **engine** errors and warnings (category `Engine`), e.g. "Cannot open file …" or script runtime errors, so a console shows everything that went wrong, not just what game code logged.

Gotchas:

- In tests, an intended `Log.error()` must be asserted like any `push_error`: `assert_push_error("text")`.
- `Log` is the first autoload and must stay free of references to other autoloads. Its signal lives on `Log` itself, not on `SignalBus`, which loads after it.
- The template's own systems log as `Scene`, `Audio`, `Settings` and `GameState`. The full game logs one `info` line per scene change.

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
| `game_saved` | `SaveManager.save_game()` | `slot: String` |
| `game_loaded` | `SaveManager.load_game()` | `slot: String` |

**Bus or direct signal?** Use the bus when the emitter shouldn't know who listens and the listeners are unrelated: HUD, audio and achievements reacting to the same event, or anything global. Use a normal signal for parent/child communication, e.g. a button telling its menu it was pressed. Passing everything through the bus makes data flow hard to follow.

**Adding a game signal:** put it in the `# --- Game ---` section of `signal_bus.gd` with a `##` doc comment, which shows in the editor's help. Name it in the past tense, `noun_verbed`: `enemy_killed`, `card_played`, `level_completed`.

**Lifetime:** when a node is freed, Godot removes connections to its **methods** automatically, so `SignalBus.x.connect(_on_x)` needs no cleanup. **Lambdas are different.** A lambda stays connected until the object that *created* it is freed. If it only *captures* a node that is later freed, the next emit errors with "Lambda capture … was freed". From nodes that can be freed, connect methods, or disconnect lambdas in `_exit_tree()`.

## SettingsManager

`globals/settings_manager/settings_manager.gd`. Holds user preferences in sections, persists them to `user://settings.cfg` and applies them to the engine.

```gdscript
var vol: float = SettingsManager.get_setting("audio", "master_volume", 0.8)
SettingsManager.set_setting("display", "vsync", false)
```

### All settings

| Section / key | Default | Values | Applied to |
| --- | --- | --- | --- |
| `audio/master_volume` | `0.8` | 0–1 | bus `Master` |
| `audio/music_volume` | `0.7` | 0–1 | bus `Music` |
| `audio/sfx_volume` | `1.0` | 0–1 | bus `SFX` |
| `audio/ambient_volume` | `1.0` | 0–1 | bus `Ambient` |
| `audio/ui_volume` | `1.0` | 0–1 | bus `UI` |
| `display/window_mode` | `"fullscreen"` (release), `"windowed"` (debug builds) | `"windowed"`, `"fullscreen"` (borderless), `"exclusive"` | `DisplayServer.window_set_mode()` |
| `display/resolution` | `Vector2i(1280, 720)` | any `Vector2i` | window size, only while windowed (clamped to the screen, centred) |
| `display/vsync` | `true` | bool | `DisplayServer.window_set_vsync_mode()` |
| `display/max_fps` | `0` | int, 0 = no cap | `Engine.max_fps` |
| `interface/ui_scale` | `1.0` | 0.5–3 (menu: 0.75–2) | `get_tree().root.content_scale_factor` |
| `input/<action>` | *(absent)* | list of bindings, e.g. `["key:74", "joy_button:2"]` | `InputMap`, see [Controls and rebinding](#controls-and-rebinding) |
| `interface/language` | `""` | `""` = system language, or a locale like `"de"` | `TranslationServer.set_locale()` |

Non-obvious behaviour:

- **Defaults live in the `DEFAULTS` constant** at the top of the script, and `SettingsManager.defaults()` returns them for the running build. On load, values from the file are merged over the defaults, so new keys you add appear automatically for existing players. `reset_to_defaults()` puts everything back (without saving).
- **Debug builds start windowed.** Editor runs and debug exports use `"windowed"` as the default window mode, so running from the editor doesn't take over the screen. Release builds default to borderless fullscreen. A value saved in the settings file wins in both.
- **Borderless vs. exclusive fullscreen:** borderless (`"fullscreen"`) alt-tabs instantly and is the better default. Exclusive can give slightly lower latency on Windows.
- **UI scale** sets the root window's `content_scale_factor`, so it scales everything drawn on canvas layers (UI and 2D), not 3D. If a 2D game needs its world at a fixed size, scale only the UI's theme instead.
- **Schema version:** the file stores `[meta] version` (`SCHEMA_VERSION`, currently 2). Adding a key needs no bump. When you **rename** a key or change what its value means, bump `SCHEMA_VERSION` and convert old files in `_migrate()`. Version 1 had `display/fullscreen` (bool); it's converted to `window_mode` (`true` → `"exclusive"`, which is what it did).
- The file is `settings_path` (default `user://settings.cfg`). Tests point it at a temporary file so they never touch the player's settings.
- **`set_setting()` applies and saves immediately** by default, writing the whole file. Pass `persist = false` to apply without saving (`set_setting("audio", "music_volume", v, false)`), e.g. while a slider is dragged, and call `save_settings()` when you're done.
- `snapshot()` returns a deep copy of every setting, and `restore(snapshot)` applies one again without saving. The settings menu uses these to revert.
- It then emits `SignalBus.setting_changed(section, key, value)`.
- The `audio`, `display`, `interface` and `input` sections are applied to the engine. Other sections are stored and saved, but you have to apply them yourself.
- Volumes are **linear 0–1**. They're converted to dB, and the bus is muted at ≤ 0.001. `VOLUME_BUSES` maps each key to its bus.

### Settings menu

`scenes/ui/menus/settings_menu/`, opened by **Options** in the main menu and **Settings** in the pause menu, both through `GameState.open_settings()`.

- **Preview, Apply, Back:** every change applies immediately, so you hear and see it, but it isn't saved. **Apply** saves and closes. **Back** or Esc restores the values from when the menu opened. This includes display changes like the window mode.
- The rows are built at runtime from the `ROWS` list at the top of `settings_menu.gd`, grouped into tabs by each row's `tab` (tabs appear in the order of their first row).
- **Row types:**
  - `SLIDER`: optional `min`, `max`, `step` (default 0–1 in steps of 0.05) and `format` (`"percent"`, the default, `"x"` for `1.25x`, or `"int"`).
  - `TOGGLE`: a switch for a bool.
  - `BINDING`: a keyboard and a controller [rebind button](#controls-and-rebinding) for the action in `key` (section `input`).
  - `OPTION`: a dropdown. `options` is a list of `[value, "Label"]` pairs, or the name of a method on the menu that returns one (used for window sizes and languages, which are only known at runtime). A saved value that isn't in the list, e.g. a window size edited into the file, is added to the list so it still shows.

### Adding a setting end to end

1. **Default:** add the key to `DEFAULTS` in `settings_manager.gd`, e.g. `"interface": {..., "subtitles": true}`. Existing players get the default automatically.
2. **Apply:** handle the key in the matching `_apply_<section>()` (or a new one added to the `match` in `_apply_setting()`), e.g. `"subtitles": Subtitles.enabled = value`.
3. **Menu:** add one entry to `ROWS` in `settings_menu.gd`: `{tab = "Interface", section = "interface", key = "subtitles", label = "Subtitles", type = RowType.TOGGLE}`.
4. **Test:** extend `test/unit/test_settings_manager.gd` (applying) and, for a new row type, `test/integration/test_settings_menu.gd`.

## SaveManager

`globals/save_manager/save_manager.gd`, autoload `SaveManager`. Saves **game state** in slots under `user://saves/`. Player preferences belong in [SettingsManager](#settingsmanager), not here.

```gdscript
SaveManager.save_game("slot_1", {"gold": gold, "level": level}, {"chapter": 2})
var data := SaveManager.load_game("slot_1")     # {} if missing or unreadable
for info in SaveManager.list_saves():            # newest first
	print(info.slot, info.saved_at, info.playtime, info.get("chapter"))
SaveManager.delete_save("slot_1")
```

**What gets saved** is up to you, in one of two ways:

- **Explicit dictionary:** build a `Dictionary` and pass it to `save_game()`. This is the clearest approach for most games: one place decides what a save contains.
- **The `persist` group:** add nodes to the group `persist` and give them `save_state() -> Dictionary` and `load_state(state: Dictionary)`. `save_persist(slot)` collects every node's state, and `load_persist(slot)` hands it back. Nodes are matched by their `persist_id` property if they have one, otherwise by their node path. Give nodes a `persist_id` if their path can change. Only nodes that exist when you load are restored. Spawned objects (dropped items, enemies) need an explicit list in some parent's state.

**Slots** are names made of letters, digits, `_` and `-` (`slot_1`, `autosave`), so they're safe as file names. `list_saves()` / `get_save_info(slot)` return each slot's metadata: `slot`, `version`, `saved_at` (Unix seconds), `playtime` (seconds), plus whatever you passed as `meta`. Keep `meta` small, since a slot list reads it for every save.

**Play time:** `SaveManager.playtime` counts seconds while `GameState` is `PLAYING`, so menus and pauses don't count. It's written into every save and restored by `load_game()`.

**Autosave:** `SaveManager.autosave()` saves the persist group to the `autosave` slot. Call it at checkpoints, or set `SaveManager.autosave_interval` (seconds, 0 = off) for a timer that runs only while playing.

**Writes are atomic:** the file is written as `<slot>.save.tmp` and then renamed over `<slot>.save`. A crash or power loss mid-write leaves the previous save intact, and a leftover `.tmp` is ignored.

### Versions and migrations

Every save stores the format `version` it was written with (`SAVE_VERSION`, currently 1). When you change what a save contains in a way old saves don't match:

1. Bump `SAVE_VERSION` in `save_manager.gd`.
2. Add one migration in `_register_migrations()` that upgrades data from the previous version by **one** step:
   ```gdscript
   func _register_migrations() -> void:
   	register_migration(1, func(data: Dictionary) -> Dictionary:
   		data["gold"] = data.get("coins", 0)   # v2 renamed coins to gold
   		data.erase("coins")
   		return data)
   ```
3. Add a fixture: keep a real save of the old version in `test/fixtures/saves/` and a test that loads it. `test/unit/test_save_manager.gd` shows how, with `v1_slot.save`.

On load, migrations run in order from the file's version up to the current one (v1 → v2 → v3), so each step only has to know about its neighbour. Never edit an old migration after release, since players' files depend on it. A save from a **newer** game version, or one with a missing step, isn't loaded and logs an error.

### File format

A save is a **JSON** file. The outer object is readable (`version`, `meta`, `data`). `meta` and `data` are encoded with `JSON.from_native()`, which keeps Godot types: ints stay ints (plain JSON turns every number into a float), and `Vector2`, `Color`, `StringName` and the like survive. Objects and resources are **never** decoded, so a save file can't run code. That makes it safe to load save files players share.

| Format | For | Against |
| --- | --- | --- |
| **JSON + `from_native`** (used) | text: diffable, easy to inspect and fix by hand; type-safe; safe to load | bigger and slower than binary; typed values are verbose to read |
| `var_to_bytes` | compact and fast; keeps all types | binary, so not inspectable; needs care with objects (`bytes_to_var_with_objects` can run code) |
| plain `JSON.stringify` | the most readable | loses types (ints become floats, vectors become strings) |

If saves get large (big worlds), switch `_write_atomic()` / `_read()` to `var_to_bytes` / `bytes_to_var` and keep the envelope the same.

**Where saves live:** `user://` is named after the project's `config/name`. Renaming the game after release moves every save, so players would lose theirs (see [Starting a new game](#starting-a-new-game-from-the-template)).

**Seeds:** if a run should continue with the same randomness, put `RngManager.get_seed()` into the save and call `RngManager.set_seed()` after loading.

**Tests** set `SaveManager.saves_dir` to a temporary folder, so they never touch real saves.

## Data definitions

`globals/definitions/`: the `Definition` base resource and the `Definitions` autoload (class `DefinitionRegistry`). Use them for game content that is data rather than code: cards, items, enemies, levels. Each piece of content is a `.tres` file you edit in the inspector.

```gdscript
var strike := Definitions.get_definition(CardDefinition, &"strike") as CardDefinition
for card in Definitions.with_tag(CardDefinition, &"starter"):
	deck.append(card)
Definitions.all(CardDefinition)   # every card, sorted by id
Definitions.ids(CardDefinition)   # [&"defend", &"strike", &"strike_plus"]
```

The template ships one example type, `CardDefinition` (`data/cards/`), with three cards. Replace or delete it.

### Defining a new data type

1. Write a subclass with a `class_name`, next to its data, e.g. `data/enemies/enemy_definition.gd`:
   ```gdscript
   class_name EnemyDefinition
   extends Definition

   @export var display_name := ""
   @export var health := 10
   @export var drops: StringName   # id of an ItemDefinition, "" = none

   func _validate(problems: PackedStringArray, registry: DefinitionRegistry) -> void:
   	if health <= 0:
   		problems.append("health must be positive")
   	check_ref(problems, registry, "drops", ItemDefinition, drops)
   ```
2. In the FileSystem dock: **right-click `data/enemies/` → New Resource… → EnemyDefinition**, and save it as `wolf.tres`. The file name is the `id` unless you set `id` yourself.
3. Use it: `Definitions.get_definition(EnemyDefinition, &"wolf")`.

What the registry does:

- **Finds everything under `res://data/`** (`Definitions.definitions_dir`), in any subfolder, at startup. Other resources in those folders are ignored.
- **Indexes by type and id.** A definition is listed under its own `class_name` and under every parent class up to `Definition`: with `WeaponDefinition extends ItemDefinition`, `all(ItemDefinition)` includes the weapons. Types can be passed as the class (`CardDefinition`) or its name (`&"CardDefinition"`).
- **Validates at startup:** duplicate ids within a type, a missing id, and every definition's own `_validate()` checks: required fields, ranges, and references to other definitions by id (`check_ref()`). Each problem is logged with the type, id and file. In debug builds they're `Log.error`, so a broken data file **fails the tests and CI**. In release builds they're warnings. `get_definition()` with an unknown id returns `null` and logs a warning.
- **Debug console:** `defs` lists types, `defs CardDefinition` lists ids, `def CardDefinition strike` shows one definition's fields.

**References between definitions:** store the other definition's **id** (`StringName`) and check it with `check_ref()`, as above. You can also export a typed resource (`@export var drops: ItemDefinition`) and drag the file in. That's type-safe, but a moved or deleted file then shows up as a load error instead of a readable validation message.

### Exported builds

When a game is exported, Godot converts `.tres` files to binary and stores them as `strike.tres.remap` plus a converted file. A plain `DirAccess` folder scan in an exported game finds only the `.remap` names and would load nothing. The registry lists folders with `ResourceLoader.list_directory()`, which returns the original names in the editor and in exports alike.

Checked by exporting a pack (`godot --headless --export-pack Linux game.pck`) and running it with `godot --headless --main-pack game.pck`: the log shows `[Data] 3 definitions loaded`.

Other pitfalls:

- Keep definitions in the export: the presets export **all resources** except `addons/gut`, `test`, `tools` and `docs`. A filter that exports only scenes would drop the `.tres` files, because nothing `preload()`s them.
- Definitions are shared, cached resources. **Don't change them at runtime**, since every user of `strike` would see the change. Keep runtime state (a card's current cost after a buff) in your own objects, or `duplicate()` the definition.
- Everything under `res://data/` is loaded at startup. For thousands of large definitions, split them into folders and scan on demand with a separate `DefinitionRegistry.new().scan("res://data/levels")`.

## Command queue

`globals/command_queue/`: `Command` and `CommandQueue`. These are classes, **not an autoload**: create a queue where you need one, e.g. one per combat. Use them when game actions must resolve **one after another** and each may wait for animations, input or other actions: card effects, turn-based combat, chained abilities.

A `Command` is one step. Override `execute()`, which may `await`. The queue starts the next command only after the current one has returned.

```gdscript
var queue := CommandQueue.new("Combat")
queue.enqueue(PlayCard.new(card, target))
await queue.run()   # returns when the queue is empty
```

### Order

| Call | Runs |
| --- | --- |
| `queue.enqueue(c)` | after everything already queued |
| `queue.push_front(c)` | **next**, before everything already queued |

Several `push_front()` calls in a row keep their order, and the rules apply the same way to commands added while one runs. That makes **reactions** work naturally: whatever a command pushes to the front runs right after it, in the order it was pushed, before anything that was already waiting. Reactions to those reactions run before the next one, depth-first.

### Example: a card with triggered effects

```gdscript
class PlayCard:
	extends Command
	var card: CardDefinition
	var target: Unit

	func _init(c: CardDefinition, t: Unit) -> void:
		card = c
		target = t

	func execute() -> void:
		await Hand.animate_play(card)
		queue.push_front(DealDamage.new(target, 6))
		for relic in Player.relics_triggered_by(card):   # e.g. "whenever you play an attack"
			queue.push_front(relic.make_command())
		queue.enqueue(Discard.new(card))                 # after everything already queued


class DealDamage:
	extends Command
	var target: Unit
	var amount: int

	func _init(t: Unit, a: int) -> void:
		target = t
		amount = a

	func execute() -> void:
		target.health -= amount
		await target.play_hit()
		if target.health <= 0:
			queue.push_front(Die.new(target))             # resolves before the relic effects
```

Playing a card with a relic resolves as: `PlayCard` → `DealDamage` → (`Die` if lethal) → relic command → whatever was queued before → `Discard`.

### API

- `enqueue(c)`, `enqueue_all([...])`, `push_front(c)`.
- `run()` runs until empty. Calling it while it's already running does nothing (the running loop picks up new commands), so it's safe to call from anywhere. With `auto_run = true`, adding to an idle queue starts it.
- `cancel()` drops every waiting command and sets `cancelled` on the running one, which can check it after an `await` and return early. `clear()` only drops the waiting ones.
- Signals: `command_started(command)`, `command_finished(command)`, `queue_empty`.
- `is_running()`, `current()`, `pending()`, `size()`.
- **History and undo:** finished commands are kept in `history` (the last `history_limit`, 50 by default). A command that overrides `can_undo()` (return `true`) and `undo()` can be undone with `await queue.undo_last()`, when the queue isn't running.
- **Debugging:** every command is logged as `[Commands] ▶ DealDamage` at `debug` level. Turn just those on with `-- --log=Commands:debug`. The console command `queue` shows every live queue with its running, pending and recent commands. Override `describe()` for a more useful name, e.g. `"DealDamage 6 → Wolf"`.

Good to know:

- `command.queue` is set only while the command runs, and cleared afterwards, so finished commands in the history don't keep the queue alive.
- Commands are `RefCounted`, not nodes. To wait for something, await a signal of a node (`await tween.finished`, `await get_tree().create_timer(0.3).timeout` through `Engine.get_main_loop()`).
- `execute()` runs to its first `await` immediately inside `run()`. Code after `queue.enqueue()` doesn't run "after" the command unless you `await queue.run()`.

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

`globals/game_state/game_state.gd`. Tracks whether the player is in a menu, playing, paused or loading, and is the **only** code that sets `get_tree().paused` and `Input.mouse_mode`. It's also the only handler of the `pause` action.

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
| during a scene transition (including `LOADING`) | ignored | ignored |

**`LOADING`:** `SceneManager` sets it (through `GameState.begin_loading()` / `end_loading()`) while it waits for a scene to load from disk, and restores the state from before when the load finishes. The new scene's `_ready()` then declares its own state as usual. `pause()` does nothing while `LOADING`, since it only acts in `PLAYING`. Scenes that are already in memory skip this state.

**Mouse mode:** the mode passed to `enter_gameplay()` is restored on every resume. Menus always get a visible cursor. Don't set `Input.mouse_mode` anywhere else, or the two will fight.

`GameState.pause(show_menu := true)`: pass `false` to freeze gameplay without opening the pause menu. The debug console does this.

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

To add a scene, add a value to `SceneKey` and its file path to `PATHS` in `scene_registry.gd`. Add new keys at the **end** of the enum: exported `SceneKey` values, e.g. `start_scene` on `main.tscn`, are stored as numbers, so inserting a key in the middle shifts them.

`SceneRegistry` holds **paths, not scenes**, so nothing is loaded at startup and any script may use it, including autoloads and registered scenes themselves. `SceneRegistry.path_of(key)` returns the path (`""` for an unknown key) and `SceneRegistry.key_name(key)` the key's name. A path that doesn't exist fails `test_scene_registry.gd`, so a moved scene file is caught by the tests. (Godot doesn't update paths inside strings when you move a file in the editor.)

### Loading and the loading screen

Scenes load on a **background thread** (`ResourceLoader.load_threaded_request`):

1. `change_scene()` starts the load straight away, so it runs while the old scene fades out.
2. The old scene stays until the new one has loaded. If loading takes longer than `SceneManager.loading_screen_delay` (0.3 s by default), the **loading screen** appears on top of everything, with a progress bar.
3. When the load is done, the loading screen is removed, the old scene is freed and the new one is added (and faded in).

A scene that is already in memory (still referenced somewhere, or preloaded) is used directly, without the `LOADING` state or a loading screen. During `change_scene_with_screen()`, the next scene loads while the screen (splash) is shown, so the loading screen only appears if it's still not ready when the screen time ends.

- **The loading screen** is the registered scene `SceneKey.LOADING_SCREEN` (`scenes/ui/loading_screen/`). Restyle it freely. `SceneManager` only calls its `set_progress(value: float)` (0–1), if it has one. Set `SceneManager.loading_screen_key = -1` to never show one. `loading_screen_delay = 0` shows it for every load from disk, which is handy for checking how it looks.
- **Preloading:** `SceneManager.preload_scene(SceneRegistry.SceneKey.GAME_SCENE)` starts loading in the background, e.g. the next level while the player is in a menu or near the end of this one. The later change then starts instantly. A preloaded scene stays in memory until you change to it.
- **Quitting during a load** waits for the load to finish (`SceneManager._exit_tree()`). Godot reports an aborted load as errors, which would fail CI's smoke runs. Those count frames, not seconds, so they can end while a scene is still loading.
- The loading screen itself is loaded when `SceneManager` starts, so showing it never has to wait for a load.
- **Failures** are logged with `Log.error` (so they fail tests and CI) and the old scene stays. Load times are logged at `debug` level: `[Scene] loaded res://… in 12 ms`.
- **Making a scene load well:** it's loaded off the main thread, so its resources must be loadable there. Plain scenes and resources are fine. Don't do heavy work in `_init()` of scripts that a scene's *resources* use. A scene's `_ready()` runs on the main thread as usual, after loading, and may still cause a hitch. Spread heavy setup over several frames there if needed.
- **Web builds** are exported without threads (see [Exporting](#exporting-and-releases)), so loads there don't run in parallel with the game. They still work, but the loading screen may not animate while a big scene loads.

### Non-obvious behaviour

- **Don't use `get_tree().change_scene_to_file()`.** The manager keeps the active scene under `/root/SceneManager/SceneHolder`, and `get_tree().current_scene` is empty after boot. Use `SceneManager.current_scene` to get the active scene. (When you run a scene with F6, it is the tree's current scene until the first `change_scene()` takes it over. Setting `SceneManager.adopt_standalone = false` disables that; the test base class does so, so GUT's own runner scene is never taken over.)
- **Calls during a transition are silently ignored.** You don't get an error. Check `SceneManager.is_changing()` if it matters. A transition includes the time spent loading.
- The old scene is removed from the tree **before** the new one is added, so a reloaded scene keeps its node name (`HelloWorld`, not `@HelloWorld@2`) and node paths stay valid.
- Fades, screen timers and loading keep running even if the tree is paused.
- **Payloads:** if the new scene has an `apply_payload(payload: Dictionary)` method, it's called **deferred**, after the scene's `_ready()`. Don't read payload data in `_ready()`.
- Intermediate screens (splash) and the loading screen are added to the manager's `Overlay` CanvasLayer (layer 100), above the game. Intermediate screens are loaded on the spot (not threaded), so keep them small.
- Every change emits `SignalBus.scene_change_started` / `scene_change_finished`, and `SceneManager.scene_changed`.

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
- **`UIButton`** (`scenes/ui/components/ui_button/`): a `Button` wrapper with a hover lift and `ui.hover` / `ui.click` sounds through `Audio`. Set its label with the `text` property. Listen to the wrapper's `pressed` / `button_down` / `button_up` signals, not the inner button's. Hover also triggers on keyboard/controller focus, so moving focus to a button plays `ui.hover`. Automatic focus (a menu opening and focusing its `default_focus`) only shows the lift, without the sound.

**Making a new menu:**

1. Create a `Control` scene and attach a script that `extends MenuBase`.
2. Expose user actions as signals (`signal resume_pressed`) instead of acting directly. Whoever opens the menu decides what they do, so the same menu works from the main menu and in-game.
3. Set `default_focus` in `_ready()` (e.g. `default_focus = btn_resume.get_path()`).
4. Call `open()` / `close()` rather than toggling `visible`, so the fade and focus run.

`default_focus` may point at a wrapper such as a `UIButton`. The first focusable control inside it gets focus.

`PauseMenu` and `SettingsMenu` are opened by [`GameState`](#gamestate-and-pausing) as overlay menus. They only emit signals and contain no pause or input logic of their own.

**Back / Esc in overlay menus:** if the menu on top has a `cancel()` method, Esc calls it, and the menu closes itself by emitting its back signal. The settings menu reverts its changes there. Menus without `cancel()` are simply closed.

Menu texts are English source text, translated automatically. See [Localization](#localization).

### Keyboard and controller navigation

Every menu works without a mouse. Focus moves with the arrow keys, D-pad or left stick (`ui_up` / `ui_down` / `ui_left` / `ui_right`). **A** / Enter activates (`ui_accept`), and **B** / Esc goes back (`ui_cancel`, handled by `GameState`). **Start** pauses. In the settings menu, **LB / RB** (PageUp / PageDown, actions `ui_tab_previous` / `ui_tab_next`) switch tabs.

Godot's built-in `ui_accept` and `ui_cancel` have no controller buttons, so `project.godot` overrides both to add A and B.

How focus is kept:

- `MenuBase.open()` focuses `default_focus`. The main menu is a `MenuBase` too and focuses **Play** when it appears.
- When the last overlay menu closes (e.g. Back from Options), `GameState` gives focus back to the menu scene underneath.
- **Lost focus is recovered:** if nothing visible has focus (e.g. after a mouse click on empty space), the first navigation or accept press focuses `default_focus` instead of doing nothing.
- Switching settings tabs moves focus to the first control of the new tab.

Each new menu gets all of this by extending `MenuBase` and setting `default_focus`. The debug scene library is mouse-oriented and not covered.

### Controls and rebinding

The player-rebindable actions are listed in `InputBindings.REBINDABLE` (`globals/settings_manager/input_bindings.gd`): `up`, `down`, `left`, `right`, `jump`, `pause`, plus `debug_overlay` and `debug_console`. Each has a **keyboard** and a **controller** binding, shown on the settings menu's **Controls** tab. The two debug rows have `debug_only = true`, so they're hidden in release builds.

- **Rebinding:** press a binding's button, then the new key, mouse button (not left), controller button or stick direction. Esc or a left click cancels. Like every setting it's a preview until **Apply**, and **Back** reverts it.
- **Conflicts swap:** binding a key that another rebindable action uses gives that action the old key instead, so no action ends up unbound by accident.
- **Reset controls** (on the tab) or `SettingsManager.reset_controls()` returns every action to Project Settings → Input Map.
- **Storage:** only changed actions are saved, in the `input` section of `settings.cfg`, as readable text: `left=["key:74", "joy_axis:0:-"]` (physical key code, mouse button, controller button, or axis and direction). Actions without an entry use the Input Map, so changing a default in the project reaches every player who hasn't rebound that action.
- **Keys are physical positions,** like the project's defaults: WASD stays in the same place on AZERTY or QWERTZ keyboards. The button shows the key's label on the player's layout (`DisplayServer.keyboard_get_label_from_physical()`), so the debug console key shows as `^` on a German keyboard.
- A saved binding for an action that no longer exists is ignored with a `Log.warn` (category `Input`).
- Bindings ignore modifier keys (Shift, Ctrl), and controller bindings apply to every connected controller.

**Adding a rebindable action:**

1. Create the action in **Project Settings → Input Map** with a keyboard and a controller event.
2. Add its name to `InputBindings.REBINDABLE`.
3. Add a row to `ROWS` in `settings_menu.gd`: `{tab = "Controls", section = "input", key = "dash", label = "Dash", type = RowType.BINDING}`, and add `"Dash"` to the `.po` files.

`RebindButton` (`scenes/ui/components/rebind_button/`) also works on its own: set `action` and `device`, and `persist = true` to save immediately.

## Localization

UI text is written in **English in the scenes and scripts** and translated through **gettext PO files** in `localization/`:

```
localization/
  messages.pot   template: every translatable English string (msgid)
  en.po          English: only LANGUAGE_NAME; everything else falls back to the source text
  de.po          German, the example second language
```

Both `.po` files are registered in **Project Settings → Localization → Translations** (`internationalization/locale/translations` in `project.godot`), and `en` is the fallback locale.

**Why PO and not CSV:** Godot loads `.po` files directly. A CSV is first *imported* into generated `.translation` files, which shouldn't be committed. On a fresh clone (and in CI) Godot then tries to load the registered `.translation` files before it has imported them, and logs errors on every cold start. PO also has plural forms and context, Godot can generate the template for you, and translators know the tools (Poedit, Weblate, Crowdin). The price is one file per language instead of one table.

**How text gets translated:**

- **Controls translate themselves.** A `Label`, `Button`, `OptionButton` item, tab title or `placeholder_text` whose text matches a msgid shows the translation, and updates **live** when the language changes. Most UI needs no code at all.
- **Text built in code** uses `tr()`: `label.text = tr("Seed: %s") % seed`. It does **not** update by itself when the language changes. Rebuild it on `NOTIFICATION_TRANSLATION_CHANGED`, as `hello_world.gd` does. Set `auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED` on such labels, so the already translated text isn't looked up again.
- **The language setting** (`interface/language`) calls `TranslationServer.set_locale()`. `""` follows the system language: a German system (`de_DE`) gets `de.po`.

### Adding a string

1. Write it in English in the scene or in a `tr("…")` call.
2. Add it to the `.pot` and each `.po`. Either by hand (a `msgid` / `msgstr` pair), or let Godot regenerate the template: **Project Settings → Localization → POT Generation** lists the files to scan (already filled in), then **Generate POT**. Merge the new template into each language with Poedit (Catalog → Update from POT file) or `msgmerge -U de.po messages.pot`.
3. Translate it in `de.po`. `test/integration/test_localization.gd` fails if a text in a template scene or a settings row has no German translation.

### Adding a language

1. Copy `de.po` to e.g. `fr.po`, set `"Language: fr\n"` in its header, and translate every `msgstr`. Set `LANGUAGE_NAME` to the language's own name (`Français`): the language dropdown shows that, so players can find their language.
2. Add the file in **Project Settings → Localization → Translations**.
3. It appears in the language dropdown automatically.

### Pitfalls

- **Formatting:** translate the whole sentence with its placeholder, then format: `tr("Seed: %s") % seed`. Never glue translated pieces together (`tr("Seed") + ": " + seed`), because word order differs between languages. Use `%s` / `%d` placeholders, and keep their number and order in every translation.
- **Plurals:** `tr_n("%d coin", "%d coins", n) % n`. Each `.po` file's `Plural-Forms` header defines how many forms the language has.
- **Same English, different meaning:** give a context, `tr("Back", "navigation")`, which becomes `msgctxt` in the `.po` file.
- **Text that must not be translated** (player names, numbers, debug output): set `auto_translate_mode` to `Disabled` on the control. Otherwise a name that happens to equal a msgid gets translated.
- **Longer text:** German is often 30 % longer than English. Leave room in layouts, and check them in the longest language.
- The **project name** on the splash screen isn't translated. Godot's `application/config/name_localized` setting does that if you need it.
- The **debug overlay and console** stay in English on purpose. They're developer tools, and their output ends up in bug reports.

## Debug tools

**Scene library** (`scenes/debug/scene_library/`): opened from the main menu's **Debug** button. It lists every `.tscn` under `res://scenes`, previews the selected one in a viewport (3D scenes get an orbit camera) and launches it.

Gotcha: previewing **instantiates** the scene, so its `_ready()` runs, along with any side effects (sounds, autoload calls, changing the mouse mode).

### Debug overlay and console

Autoload `Debug` (`globals/debug/`). In debug builds (editor runs, debug exports) it gives you:

| Key | What |
| --- | --- |
| **F1** (`debug_overlay`) | Overlay, top-right: FPS and frame time, draw calls and objects, current scene and `SceneKey`, `GameState` state, time scale, seed, errors and warnings logged so far. |
| **The key left of 1** (`debug_console`) | Console: the recent log (colored by level, including engine errors, see [Logging](#logging)) and a command line. ↑/↓ browse history, **Tab** completes command names and scene keys, **Esc** or the same key closes it. |
| — | The **seed** is always shown small in the bottom-right corner, so it's in every screenshot. Click it to copy. |

The console key is bound by **physical position**, the key left of `1`: `~` on US keyboards, `^` on German ones, `²` on French ones. It's an input action, so it can be rebound like any other.

**The console pauses the game while it's open.** Games usually read movement by polling (`Input.get_vector()` in `_process`), and GUI focus doesn't block polling, so typing `wasd` would move the player. The console calls `GameState.pause(false)`, which pauses without the pause menu, and resumes on close **only if it paused**. Opening it over the pause menu leaves the game paused.

**Built-in commands:** `help [command]`, `clear`, `seed [value]` (shows and copies, or sets), `scene <SCENE_KEY>`, `reload`, `timescale <x>`, `log <Category> <level>`, `pause`, `resume`, `quit`.

**Adding your own (cheats, test helpers):**

```gdscript
func _ready() -> void:
	Debug.register_command("gold", _cmd_gold, "Add gold", "<amount>")

func _cmd_gold(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_int():
		return "usage: gold <amount>"
	gold += args[0].to_int()
	return "gold: %d" % gold
```

- The callable always receives a `PackedStringArray`. Words are split on spaces, and `"double quotes"` keep words together.
- Return a `String` to print it, or nothing.
- Validate the arguments yourself. A runtime error inside a command is reported like any script error (and in the editor the debugger stops on it), so commands can't crash a debug session silently, but they don't get special error handling either.
- A command whose object was freed reports "no longer valid" instead of crashing. `Debug.unregister_command("gold")` removes one.
- `Debug.execute("gold 50")` runs a line from code, which is handy in tests.

**Release builds:** the tools are **off**. No UI is created, and `register_command()` / `execute()` do nothing, so game code needs no `if`. To turn them on for testers, start the game with `-- --debug-tools`, or tick **Enabled In Release** on `globals/debug/debug.tscn`. **Enabled In Debug** and **Show Seed** are on the same node.

Layering: the tools draw on canvas layer **120**, above `GameState`'s menus (50) and `SceneManager`'s fades (100). They run with `PROCESS_MODE_ALWAYS`, so they work while paused.

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
  unit/            pure logic: RngManager, SettingsManager, SaveManager, SceneRegistry
  integration/     real autoloads: scene changes, pause, menus, audio, boot
  sandbox/         click-through scenes for poking at things by hand (F6)
  fixtures/        files tests load (e.g. an old save to migrate); never run
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

**CI starts from a fresh checkout with no `.godot/` cache**, and some problems only show up then. For example, `var x := SomeAutoload.some_property` can fail to infer its type on a cold import, while a warm local cache hides it. If CI fails where your machine passes, reproduce it with `rm -rf .godot && tools/check.sh`. Writing explicit types (`var x: Node = …`) for values read from autoloads avoids this case.

The last form is for when `godot` isn't on your PATH. It works on Linux and macOS, and on Windows in Git Bash. A full run takes about 20 seconds.

### Bumping the Godot version

The version is pinned in several places that must agree:

1. `GODOT_VERSION` in `.github/workflows/ci.yml` **and** `.github/workflows/release.yml`.
2. `config/features` in `project.godot` (Godot updates it when you open the project in the new editor).
3. **GUT:** replace `addons/gut/` with the GUT release built for that Godot version (GUT's README has a table).
4. If you use a cloud dev environment, the Godot version in its setup script.

### Exporting and releases

`export_presets.cfg` has three release presets. All of them export to `build/` (git-ignored):

| Preset | Output | Notes |
| --- | --- | --- |
| **Windows Desktop** | `build/windows/<name>.exe` + `.pck` | x86_64. The `.exe` keeps Godot's icon and version info (`application/modify_resources` is off, so no `rcedit` is needed). To brand it, install `rcedit`, set its path in Editor Settings → Export → Windows, and turn the option on. |
| **Linux** | `build/linux/<name>.x86_64` + `.pck` | x86_64. |
| **Web** | `build/web/index.html` + `.js`/`.wasm`/`.pck` | **No threads** (`variant/thread_support=false`), so it runs on any static host: GitHub Pages, itch.io. Threaded web builds need COOP/COEP headers, which those hosts don't send by default. |

`<name>` is `config/name` in lowercase with dashes, e.g. `my-deckbuilder`.

**Excluded from every build:** `addons/gut/*`, `test/*`, `tools/*`, `docs/*`. The test framework and dev tools never ship. A packed build is about 200 KB, compared to 2.5 MB for GUT alone. Keep the filter when you add presets.

**Export templates** are needed once per Godot version: in the editor, **Editor → Manage Export Templates → Download and Install**. On the command line, extract the `templates/` folder of `Godot_v<version>_export_templates.tpz` into `~/.local/share/godot/export_templates/<version>/` (Linux), `%APPDATA%\Godot\export_templates\<version>\` (Windows) or `~/Library/Application Support/Godot/export_templates/<version>/` (macOS). `<version>` is the content of its `version.txt`, e.g. `4.7.stable`.

**Exporting from the command line:**

```bash
tools/export.sh
```
```bash
tools/export.sh Linux Web
```

This exports every preset (or only the named ones), zips each as `build/<name>-<platform>.zip`, and fails on export errors. Godot exits 0 even when an export has errors, so the script scans the logs.

**Cutting a release:** push a version tag.

```bash
git tag v0.1.0 && git push origin v0.1.0
```

`.github/workflows/release.yml` then runs all checks, exports the three presets and creates a **GitHub Release** for the tag, with generated notes and the three zips attached. Godot and the three needed templates are cached per version; the full template bundle is about 1.3 GB.

**Adding a platform:**

- **macOS** needs a signing identity and notarization (an Apple developer account), so it isn't preset. Add it in the editor (**Project → Export → Add → macOS**), put signing secrets in `export_credentials.cfg` (git-ignored), and add the template file to `release.yml`'s extract list.
- **Android** needs the Android SDK, a keystore and the Android build template.
- In every case, add the new preset's name to the `case` in `tools/export.sh`.

## Conventions

Folder layout, naming rules, the rules that keep the template working, and the issue → branch → PR workflow are in **[CONTRIBUTING.md](../CONTRIBUTING.md)**. AI coding agents get the same rules, plus headless-testing gotchas, in **[CLAUDE.md](../CLAUDE.md)**. Issues use the bug or feature forms, and PRs use `.github/pull_request_template.md`.

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

- **Godot:** the `.godot/` cache, generated `*.translation` files (in case a game switches to CSV translations), and `export_credentials.cfg` (export signing keys and passwords, which must never be committed).
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

