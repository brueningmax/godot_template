# Graph Report - godot_template  (2026-11-26)

## Corpus Check
- Corpus is ~17,734 words - fits in a single context window. You may not need a graph.

## Summary
- 1003 nodes · 1926 edges · 48 communities (43 shown, 5 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 30 edges (avg confidence: 0.89)
- Token cost: 199,448 input · 0 output

## Community Hubs (Navigation)
- Settings Manager and Persistence
- GameState Menus and Pause
- Debug Console Overlay
- RNG Manager and Streams
- Definitions Registry and Cards
- Graphify Godot Extractor
- Save Manager
- Command Queue and Undo
- Input Bindings and Rebinding
- Log Autoload
- CI Workflow
- Release Workflow
- Scene Manager Core
- Contributor and Agent Rules
- Settings Menu Tests
- Audio Resources and Sounds
- Template Setup Workflow
- Audio Manager Players
- Guide: Definitions and Commands
- Guide: GameState and Menus
- Loading Screen Progress
- Guide: Checks and Tooling
- Audio Playback Tests
- Debug Scene Library
- Bug Report Template
- Feature Request Template
- Scene Registry Keys
- Pre-commit Hooks Config
- Guide: Saves and Signals
- Audio System Concepts
- SignalBus Sandbox
- Never Rules and Ownership
- Guide: Boot and Audio
- Boot Flow
- GameState Integration Tests
- Guide: Settings and Localization
- Debug 3D Launcher
- Audio Cue Playback API
- TemplateTest Base Class
- check.sh Pipeline
- Export Script and Presets
- Guide: RNG Concepts
- Issue Template Config
- Script Checker Tool
- Project Rename Tool

## God Nodes (most connected - your core abstractions)
1. `MainRoot` - 51 edges
2. `AudioManager` - 40 edges
3. `SettingsMenu` - 27 edges
4. `CommandQueue` - 25 edges
5. `set_setting()` - 25 edges
6. `GodotExtractor` - 23 edges
7. `DefinitionRegistry` - 23 edges
8. `RNGManager` - 23 edges
9. `Template Guide` - 21 edges
10. `SceneRegistry` - 18 edges

## Surprising Connections (you probably didn't know these)
- `Command` --references--> `Command`  [INFERRED]
  docs/TEMPLATE_GUIDE.md → globals/command_queue/command.gd
- `RebindButton` --references--> `RebindButton`  [INFERRED]
  docs/TEMPLATE_GUIDE.md → scenes/ui/components/rebind_button/rebind_button.gd
- `UIButton` --references--> `UIButton`  [INFERRED]
  docs/TEMPLATE_GUIDE.md → scenes/ui/components/ui_button/ui_button.gd
- `CommandQueue` --references--> `CommandQueue`  [INFERRED]
  docs/TEMPLATE_GUIDE.md → globals/command_queue/command_queue.gd
- `test_debug_command_lists_queues()` --calls--> `execute()`  [EXTRACTED]
  test/unit/test_command_queue.gd → globals/debug/debug.gd

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Pause and mouse-mode ownership through GameState** — docs_template_guide_gamestate, docs_template_guide_overlay_menus, docs_template_guide_pause_menu, docs_template_guide_debug, docs_template_guide_process_mode_rules [EXTRACTED 1.00]
- **Scene change flow** — docs_template_guide_scenemanager, docs_template_guide_sceneregistry, docs_template_guide_scenekey, docs_template_guide_threaded_loading, docs_template_guide_loading_screen, docs_template_guide_scene_payloads, docs_template_guide_signalbus [EXTRACTED 1.00]
- **CI check pipeline** — docs_template_guide_ci_workflow, docs_template_guide_check_sh, docs_template_guide_code_style, docs_template_guide_check_scripts, docs_template_guide_smoke_runs, docs_template_guide_gut [EXTRACTED 1.00]
- **Audio content hierarchy: Registry -> Set -> Cue resolved by AudioManager** — globals_audio_manager_readme_audioregistry, globals_audio_manager_readme_audioset, globals_audio_manager_readme_audiocue, globals_audio_manager_readme_audiomanager, globals_audio_manager_readme_audio_id_scheme [EXTRACTED 1.00]
- **Rules that keep the template working** — contributing_boot_navigation_rule, contributing_gamestate_owns_pause, contributing_scenemanager_scene_changes, contributing_scenekey_append_only, contributing_logging_rule, contributing_signalbus_typed_signals, contributing_tests_rule [EXTRACTED 1.00]
- **Pre-merge verification flow** — contributing_workflow, readme_check_sh, _github_pull_request_template_pr_checklist, readme_gut_tests, requirements_dev_gdtoolkit [INFERRED 0.85]

## Communities (48 total, 5 thin omitted)

### Community 0 - "Settings Manager and Persistence"
Cohesion: 0.05
Nodes (69): apply_all(), _apply_audio(), _apply_display(), _apply_interface(), _apply_setting(), _apply_window_size(), defaults(), get_setting() (+61 more)

### Community 1 - "GameState Menus and Pause"
Cohesion: 0.06
Nodes (52): _register_builtins(), back(), begin_loading(), _clear_menus(), _close(), _close_top(), end_loading(), enter_gameplay() (+44 more)

### Community 2 - "Debug Console Overlay"
Cohesion: 0.07
Nodes (44): _box(), _browse_history(), _build_ui(), close_console(), _cmd_log(), _cmd_reload(), _cmd_scene(), _complete() (+36 more)

### Community 3 - "RNG Manager and Streams"
Cohesion: 0.07
Nodes (39): _cmd_seed(), RNGManager, _derive_seed(), _fnv1a_32(), _generate_random_seed(), get_seed(), get_seeded_stream_for(), get_stream() (+31 more)

### Community 4 - "Definitions Registry and Cards"
Cohesion: 0.07
Nodes (29): CardDefinition, Definition, all(), DefinitionRegistry, _cmd_def(), _cmd_defs(), count(), _find_resources() (+21 more)

### Community 5 - "Graphify Godot Extractor"
Cohesion: 0.11
Nodes (8): file_node_id(), GodotExtractor, link_docs_to_classes(), main(), make_node_id(), parse_attributes(), strip_comment(), strip_strings()

### Community 6 - "Save Manager"
Cohesion: 0.11
Nodes (42): error(), apply_persist_state(), autosave(), collect_persist_state(), delete_save(), get_save_info(), has_save(), _is_valid_slot() (+34 more)

### Community 7 - "Command Queue and Undo"
Cohesion: 0.06
Nodes (17): Command, cancel(), CommandQueue, clear(), enqueue(), enqueue_all(), _init(), _maybe_auto_run() (+9 more)

### Community 8 - "Input Bindings and Rebinding"
Cohesion: 0.12
Nodes (32): apply(), bind(), InputBindings, default_events(), deserialize(), device_of(), display_name(), event_for() (+24 more)

### Community 9 - "Log Autoload"
Cohesion: 0.13
Nodes (30): apply_cmdline_args(), clear_level(), clear_recent(), debug(), get_level(), info(), _init(), is_enabled() (+22 more)

### Community 10 - "CI Workflow"
Cohesion: 0.06
Nodes (30): name, runs-on, steps, timeout-minutes, concurrency, cancel-in-progress, group, env (+22 more)

### Community 11 - "Release Workflow"
Cohesion: 0.07
Nodes (29): env, GH_TOKEN, GODOT_VERSION, jobs, release, name, on, push (+21 more)

### Community 12 - "Scene Manager Core"
Cohesion: 0.12
Nodes (22): _adopt_standalone_scene(), _apply_payload(), _await_scene(), _change_to(), MainRoot, _fade_in(), _fade_out(), _finish_change() (+14 more)

### Community 13 - "Contributor and Agent Rules"
Cohesion: 0.11
Nodes (17): graphify skill (/graphify trigger), Pull Request Template, CLAUDE.md agent guidance, CI cold-cache import type inference failure, Folder layout conventions, Contributing guide, Contribution workflow (issue, branch, check, PR), Modular Audio System (+9 more)

### Community 14 - "Settings Menu Tests"
Cohesion: 0.20
Nodes (21): _file_value(), _key(), _menu(), _music_db(), _rebind(), _send_key(), _slider(), test_apply_saves() (+13 more)

### Community 15 - "Audio Resources and Sounds"
Cohesion: 0.12
Nodes (3): AudioCue, AudioRegistry, AudioSet

### Community 16 - "Template Setup Workflow"
Cohesion: 0.10
Nodes (19): REPO_NAME, jobs, setup, name, on, push, permissions, contents (+11 more)

### Community 17 - "Audio Manager Players"
Cohesion: 0.15
Nodes (14): _apply_cue_to_player_2d(), _as_set(), _bus_exists(), AudioManager, _get_bus_limits(), _get_voice_2d(), _init_music_layers(), _init_voice_pools() (+6 more)

### Community 18 - "Guide: Definitions and Commands"
Cohesion: 0.15
Nodes (15): Direct audio references (AudioStream/AudioCue/AudioSet), CardDefinition example, check_ref() reference validation, Command, Command history and undo, CommandQueue, Debug autoload (overlay and console), Debug console commands (register_command) (+7 more)

### Community 19 - "Guide: GameState and Menus"
Cohesion: 0.19
Nodes (15): Keyboard and controller navigation, GameState states (MENU/PLAYING/PAUSED/LOADING), GameState, Loading screen, MenuBase, Overlay menus (push_menu/pop_menu), PauseMenu, Scene preloading (+7 more)

### Community 20 - "Loading Screen Progress"
Cohesion: 0.14
Nodes (7): is_changing(), signal game_state_changed, LoadingScreen, test_change_during_transition_is_ignored(), test_load_enters_and_leaves_loading_state(), test_missing_file_errors_and_keeps_scene(), test_unknown_key_errors()

### Community 21 - "Guide: Checks and Tooling"
Cohesion: 0.20
Nodes (14): Script checker (check_scripts.gd), tools/check.sh, CI workflow (ci.yml), CLAUDE.md, Code style (gdtoolkit gdformat/gdlint), CONTRIBUTING.md, Git LFS, Godot version pinning (+6 more)

### Community 22 - "Audio Playback Tests"
Cohesion: 0.21
Nodes (13): play_follow(), play_sound(), play_sound_at(), play_sound_follow(), _playing(), test_follow_player_reused_and_cleaned_up(), test_play_by_id_uses_registry_bus(), test_play_sound_at_positions_voice() (+5 more)

### Community 23 - "Debug Scene Library"
Cohesion: 0.22
Nodes (11): _check_3d_support(), _clear_preview(), _filter_tree(), _on_item_selected(), _on_search_changed(), _populate_tree(), _ready(), _scan_dir() (+3 more)

### Community 24 - "Bug Report Template"
Cohesion: 0.15
Nodes (12): description, label, placeholder, body, attributes, id, type, validations (+4 more)

### Community 25 - "Feature Request Template"
Cohesion: 0.15
Nodes (12): description, label, placeholder, body, attributes, id, type, validations (+4 more)

### Community 26 - "Scene Registry Keys"
Cohesion: 0.23
Nodes (10): preload_scene(), _request(), SceneRegistry, key_name(), path_of(), test_loading_screen_progress(), test_preload_then_change(), test_every_key_is_registered() (+2 more)

### Community 27 - "Pre-commit Hooks Config"
Cohesion: 0.15
Nodes (12): exclude, always_run, entry, id, language, name, pass_filenames, stages (+4 more)

### Community 28 - "Guide: Saves and Signals"
Cohesion: 0.17
Nodes (8): Autosave, persist group, Play time tracking, rename_project.gd tool, SaveManager, SignalBus, Template setup workflow (template-setup.yml), user:// data folder

### Community 29 - "Audio System Concepts"
Cohesion: 0.20
Nodes (8): Audio ID scheme <namespace>.<set_id>[.<cue_id>], AudioBusConfig, AudioManager (autoload Audio), Direct resource playback (play_sound*), Follow emitters (play_follow, not pooled), Layered music and stingers, Per-bus voice limiting and pooling, AudioBusConfig

### Community 30 - "SignalBus Sandbox"
Cohesion: 0.26
Nodes (10): _ready(), signal scene_change_finished, signal scene_change_started, test_bus_signals_in_order(), _log(), _on_pause_toggled(), _on_scene_finished(), _on_scene_started() (+2 more)

### Community 31 - "Never Rules and Ownership"
Cohesion: 0.20
Nodes (5): AudioCue, AudioRegistry, AudioSet, Audio bus layout (bus_layout.tres), Autoload systems table (Log, SignalBus, RngManager, Audio, SettingsManager, GameState, SceneManager, Debug)

### Community 32 - "Guide: Boot and Audio"
Cohesion: 0.22
Nodes (10): Audio manager, Audio bus layout, Audio system README, Audio registries, Hello-world scene, Single scene run (F6), Smoke runs (--fixed-fps 60), Standalone scene adoption (adopt_standalone) (+2 more)

### Community 33 - "Boot Flow"
Cohesion: 0.18
Nodes (4): _start(), change_scene_with_screen(), goto_menu(), test_screen_is_skippable()

### Community 35 - "Guide: Settings and Localization"
Cohesion: 0.24
Nodes (8): InputBindings / rebinding, Localization (gettext PO), RebindButton, Settings DEFAULTS constant, Settings menu, Settings ROWS and row types, SettingsManager, tr() / tr_n() translation in code

### Community 36 - "Debug 3D Launcher"
Cohesion: 0.22
Nodes (6): change_scene(), _input(), _on_back_pressed(), _update_camera(), _on_back_pressed(), test_pause_ignored_during_transition()

### Community 37 - "Audio Cue Playback API"
Cohesion: 0.25
Nodes (9): _get_set_or_warn(), music_stinger(), play(), play_at(), _play_set_3d(), _resolve_bus(), _process(), _on_pressed() (+1 more)

### Community 38 - "TemplateTest Base Class"
Cohesion: 0.28
Nodes (4): after_each(), TemplateTest, goto(), wait_for_transition()

### Community 39 - "check.sh Pipeline"
Cohesion: 0.67
Nodes (6): fail(), godot_run(), limit(), scan_log(), check.sh script, step()

### Community 40 - "Export Script and Presets"
Cohesion: 0.53
Nodes (4): Export presets (Windows/Linux/Web), fail(), scan_log(), export.sh script

### Community 41 - "Guide: RNG Concepts"
Cohesion: 0.40
Nodes (6): 32-bit FNV-1a hashing, Keyed RNG values, Per-object streams, RNG stream (rng_stream.gd), RngManager, Seed string

### Community 42 - "Issue Template Config"
Cohesion: 0.33
Nodes (5): blank_issues_enabled, contact_links, about, name, url

### Community 43 - "Script Checker Tool"
Cohesion: 0.83
Nodes (3): _collect(), _initialize(), _is_abstract()

## Knowledge Gaps
- **29 isolated node(s):** `Template setup workflow (template-setup.yml)`, `Log levels and per-category filtering`, `Settings DEFAULTS constant`, `persist group`, `Autosave` (+24 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 304 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AudioManager` connect `Audio Manager Players` to `Settings Manager and Persistence`, `GameState Menus and Pause`, `RNG Manager and Streams`, `Audio Cue Playback API`, `Log Autoload`, `Audio Resources and Sounds`, `Audio Playback Tests`, `Audio System Concepts`?**
  _High betweenness centrality (0.154) - this node is a cross-community bridge._
- **What connects `Template setup workflow (template-setup.yml)`, `Log levels and per-category filtering`, `Settings DEFAULTS constant` to the rest of the system?**
  _29 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Settings Manager and Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.05220883534136546 - nodes in this community are weakly interconnected._
- **Why does `MainRoot` connect `Scene Manager Core` to `GameState Menus and Pause`, `Debug Console Overlay`, `Boot Flow`, `Debug 3D Launcher`, `GameState Integration Tests`, `Save Manager`, `TemplateTest Base Class`, `Log Autoload`, `Settings Menu Tests`, `Loading Screen Progress`, `Debug Scene Library`, `Scene Registry Keys`, `SignalBus Sandbox`?**
  _High betweenness centrality (0.091) - this node is a cross-community bridge._
- **Should `GameState Menus and Pause` be split into smaller, more focused modules?**
  _Cohesion score 0.05687645687645688 - nodes in this community are weakly interconnected._
- **Why does `RNGManager` connect `RNG Manager and Streams` to `GameState Menus and Pause`, `Debug Console Overlay`?**
  _High betweenness centrality (0.072) - this node is a cross-community bridge._
- **Should `Debug Console Overlay` be split into smaller, more focused modules?**
  _Cohesion score 0.07127882599580712 - nodes in this community are weakly interconnected._