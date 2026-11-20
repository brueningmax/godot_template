extends Node
## Debug overlay (F1), console (the key left of 1, "~" on US keyboards) and
## an always-visible seed label. Autoload "Debug" (globals/debug/debug.tscn).
##
## Games add cheat commands:
##   Debug.register_command("gold", func(args): gold += int(args[0]), "Add gold", "<amount>")
##
## Off in release builds unless enabled_in_release is set or the game is
## started with "-- --debug-tools". When off, no UI exists and
## register_command() does nothing, so game code needs no checks.
##
## The console pauses gameplay while open (games usually poll input, which GUI
## focus doesn't block), through GameState.pause(false).

## Emitted when the console opens or closes.
signal console_toggled(is_open: bool)

const LAYER := 120  # above GameState menus (50) and SceneManager fades (100)
const REFRESH_SEC := 0.25
const MAX_LOG_LINES := 500
const LEVEL_COLORS := ["#9aa0a6", "#e8eaed", "#fdd663", "#f28b82"]  # debug, info, warn, error

## Enable the tools in debug builds (editor runs, debug exports).
@export var enabled_in_debug := true
## Enable the tools in release builds too (e.g. for testers).
@export var enabled_in_release := false
## Always show the run seed in the bottom-right corner (click to copy).
@export var show_seed := true

## True when the tools are active in this run.
var enabled := false

var _commands: Dictionary = {}  # name -> {callable, help, usage}
var _history: PackedStringArray = []
var _history_index := -1
var _paused_by_console := false
var _refresh_left := 0.0
var _error_count := 0
var _warning_count := 0

var _layer: CanvasLayer
var _overlay_panel: PanelContainer
var _overlay_label: Label
var _seed_button: Button
var _console: PanelContainer
var _log_view: RichTextLabel
var _input_line: LineEdit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var requested := "--debug-tools" in OS.get_cmdline_user_args()
	enabled = (enabled_in_debug if OS.is_debug_build() else enabled_in_release) or requested
	set_process(enabled)
	set_process_input(enabled)
	if not enabled:
		return
	_build_ui()
	_register_builtins()
	for entry in Log.recent():
		_on_log_message(entry)
	Log.message_logged.connect(_on_log_message)
	_update_overlay()


# --- Public API ---------------------------------------------------------------


## Adds a console command. `callable` receives the arguments as a
## PackedStringArray and may return a String, which the console prints.
func register_command(command: String, callable: Callable, help := "", usage := "") -> void:
	if not enabled:
		return
	_commands[command.to_lower()] = {callable = callable, help = help, usage = usage}


func unregister_command(command: String) -> void:
	_commands.erase(command.to_lower())


func has_command(command: String) -> bool:
	return _commands.has(command.to_lower())


## Runs a console line (as if typed) and returns what it printed.
func execute(line: String) -> String:
	if not enabled:
		return ""
	var parts := parse_args(line)
	if parts.is_empty():
		return ""
	_print_line("> " + line, LEVEL_COLORS[0])
	var command := parts[0].to_lower()
	var output := ""
	if not _commands.has(command):
		output = "Unknown command '%s'. Type 'help' for a list." % command
	else:
		var callable: Callable = _commands[command].callable
		if not callable.is_valid():
			output = "Command '%s' is no longer valid (its object was freed)." % command
		else:
			var result: Variant = callable.call(parts.slice(1))
			output = str(result) if result != null else ""
	if output != "":
		_print_line(output, LEVEL_COLORS[1])
	return output


## Splits a command line on spaces; "double quotes" group words.
static func parse_args(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var quoted := false
	var has_token := false
	for c in line:
		if c == '"':
			quoted = not quoted
			has_token = true
		elif c == " " and not quoted:
			if has_token:
				out.append(current)
			current = ""
			has_token = false
		else:
			current += c
			has_token = true
	if has_token:
		out.append(current)
	return out


func open_console() -> void:
	if not enabled or is_console_open():
		return
	_console.visible = true
	if GameState.state == GameState.State.PLAYING:
		GameState.pause(false)
		_paused_by_console = true
	_input_line.grab_focus()
	console_toggled.emit(true)


func close_console() -> void:
	if not enabled or not is_console_open():
		return
	_console.visible = false
	_input_line.release_focus()
	# Only undo a pause we caused (not the player's own pause menu).
	if _paused_by_console and GameState.state == GameState.State.PAUSED:
		GameState.resume()
	_paused_by_console = false
	console_toggled.emit(false)


func toggle_console() -> void:
	if is_console_open():
		close_console()
	else:
		open_console()


func is_console_open() -> bool:
	return enabled and _console.visible


func toggle_overlay() -> void:
	if enabled:
		_overlay_panel.visible = not _overlay_panel.visible
		_update_overlay()


func is_overlay_visible() -> bool:
	return enabled and _overlay_panel.visible


# --- Input --------------------------------------------------------------------


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_console"):
		toggle_console()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_overlay"):
		toggle_overlay()
		get_viewport().set_input_as_handled()
	elif is_console_open():
		# Handle Esc here, before GameState sees it as "pause"/"back".
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			close_console()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and _input_line.has_focus():
			match event.keycode:
				KEY_UP:
					_browse_history(-1)
					get_viewport().set_input_as_handled()
				KEY_DOWN:
					_browse_history(1)
					get_viewport().set_input_as_handled()
				KEY_TAB:
					_complete()
					get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SEC
		_update_overlay()


# --- Built-in commands ----------------------------------------------------------


func _register_builtins() -> void:
	register_command("help", _cmd_help, "List commands, or show one command's usage.", "[command]")
	register_command("clear", _cmd_clear, "Clear the console.")
	register_command("seed", _cmd_seed, "Show and copy the seed, or set a new one.", "[value]")
	register_command("scene", _cmd_scene, "Change scene.", "<SCENE_KEY>")
	register_command("reload", _cmd_reload, "Reload the current scene.")
	register_command("timescale", _cmd_timescale, "Set Engine.time_scale.", "<x>")
	register_command("log", _cmd_log, "Set a log category's level.", "<Category> <level>")
	register_command("pause", func(_a): GameState.pause(), "Pause the game (pause menu).")
	register_command("resume", func(_a): GameState.resume(), "Resume the game.")
	register_command("quit", func(_a): get_tree().quit(), "Quit the game.")


func _cmd_help(args: PackedStringArray) -> String:
	if args.size() > 0:
		var command := args[0].to_lower()
		if not _commands.has(command):
			return "Unknown command '%s'." % command
		var c: Dictionary = _commands[command]
		return "%s %s\n  %s" % [command, c.usage, c.help]
	var names := _commands.keys()
	names.sort()
	var lines := PackedStringArray()
	for command in names:
		lines.append("%-10s %s" % [command, _commands[command].help])
	return "\n".join(lines)


func _cmd_clear(_args: PackedStringArray) -> String:
	_log_view.clear()
	return ""


func _cmd_seed(args: PackedStringArray) -> String:
	if args.is_empty():
		DisplayServer.clipboard_set(RngManager.get_seed())
		return "seed %s (copied to clipboard)" % RngManager.get_seed()
	RngManager.set_seed(" ".join(args))
	return "seed set to %s; streams fetched from now on use it" % RngManager.get_seed()


func _cmd_scene(args: PackedStringArray) -> String:
	var names := SceneRegistry.SceneKey.keys()
	if args.is_empty():
		return "usage: scene <%s>" % "|".join(names)
	var index := names.find(args[0].to_upper())
	if index < 0:
		return "Unknown scene key '%s'. Keys: %s" % [args[0], ", ".join(names)]
	close_console()
	SceneManager.change_scene(index, {}, true)
	return "changing to %s" % names[index]


func _cmd_reload(_args: PackedStringArray) -> String:
	close_console()
	SceneManager.reload_current()
	return "reloading"


func _cmd_timescale(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_float():
		return "usage: timescale <x>   (current: %s)" % Engine.time_scale
	Engine.time_scale = maxf(0.0, args[0].to_float())
	return "time scale %s" % Engine.time_scale


func _cmd_log(args: PackedStringArray) -> String:
	var levels := Log.Level.keys()
	if args.size() != 2 or levels.find(args[1].to_upper()) < 0:
		return "usage: log <Category> <%s>" % "|".join(levels).to_lower()
	Log.set_level(StringName(args[0]), levels.find(args[1].to_upper()))
	return "%s logs from %s up" % [args[0], args[1].to_lower()]


# --- Console internals ----------------------------------------------------------


func _on_submitted(text: String) -> void:
	_input_line.clear()
	if text.strip_edges() == "":
		return
	if _history.is_empty() or _history[-1] != text:
		_history.append(text)
	_history_index = -1
	execute(text)


func _browse_history(step: int) -> void:
	if _history.is_empty():
		return
	if _history_index == -1:
		_history_index = _history.size()
	_history_index = clampi(_history_index + step, 0, _history.size())
	_input_line.text = _history[_history_index] if _history_index < _history.size() else ""
	_input_line.caret_column = _input_line.text.length()


# Completes the command name, or a scene key after "scene ".
func _complete() -> void:
	var text := _input_line.text
	var candidates: Array = []
	var prefix := ""
	if text.to_lower().begins_with("scene "):
		prefix = "scene "
		candidates = SceneRegistry.SceneKey.keys()
	else:
		candidates = _commands.keys()
	var typed := text.substr(prefix.length()).to_lower()
	var matches := candidates.filter(func(c): return c.to_lower().begins_with(typed))
	if matches.size() == 1:
		_input_line.text = prefix + matches[0] + " "
		_input_line.caret_column = _input_line.text.length()
	elif matches.size() > 1:
		_print_line("  ".join(matches), LEVEL_COLORS[0])


func _on_log_message(entry: Dictionary) -> void:
	if entry.level == Log.Level.ERROR:
		_error_count += 1
	elif entry.level == Log.Level.WARN:
		_warning_count += 1
	_print_line(entry.text, LEVEL_COLORS[entry.level])


func _print_line(text: String, color: String) -> void:
	if _log_view == null:
		return
	_log_view.append_text("[color=%s]%s[/color]\n" % [color, text.replace("[", "[lb]")])
	while _log_view.get_paragraph_count() > MAX_LOG_LINES:
		_log_view.remove_paragraph(0)


# --- Overlay ------------------------------------------------------------------


func _update_overlay() -> void:
	if not enabled:
		return
	_seed_button.visible = show_seed
	_seed_button.text = "seed %s" % RngManager.get_seed()
	if not _overlay_panel.visible:
		return
	var fps := Engine.get_frames_per_second()
	var scene: Node = SceneManager.current_scene
	if scene == null:
		scene = get_tree().current_scene
	var keys := SceneRegistry.SceneKey.keys()
	var key: int = SceneManager.current_key
	var key_text: String = keys[key] if key >= 0 and key < keys.size() else "no key"
	var scene_text := "%s (%s)" % [scene.name, key_text] if scene else "-"
	_overlay_label.text = (
		"\n"
		. join(
			[
				"FPS %d  (%.1f ms)" % [fps, 1000.0 / maxf(fps, 1.0)],
				(
					"draw calls %d   objects %d"
					% [
						RenderingServer.get_rendering_info(
							RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
						),
						RenderingServer.get_rendering_info(
							RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
						),
					]
				),
				"scene %s" % scene_text,
				(
					"state %s   time scale %s"
					% [GameState.State.keys()[GameState.state], Engine.time_scale]
				),
				"seed %s" % RngManager.get_seed(),
				"log %d errors, %d warnings" % [_error_count, _warning_count],
			]
		)
	)


# --- UI construction ------------------------------------------------------------


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "DebugLayer"
	_layer.layer = LAYER
	add_child(_layer)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace"])

	# Overlay (top-right)
	_overlay_panel = PanelContainer.new()
	_overlay_panel.name = "Overlay"
	_overlay_panel.visible = false
	_overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_panel.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.6)))
	_overlay_label = Label.new()
	_overlay_label.add_theme_font_override("font", font)
	_overlay_label.add_theme_font_size_override("font_size", 13)
	_overlay_panel.add_child(_overlay_label)
	_layer.add_child(_overlay_panel)
	# Top-right, so it doesn't sit under the console (top) or the seed (bottom-right).
	_overlay_panel.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8
	)
	_overlay_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Seed (bottom-right), click to copy
	_seed_button = Button.new()
	_seed_button.name = "Seed"
	_seed_button.flat = true
	_seed_button.focus_mode = Control.FOCUS_NONE
	_seed_button.tooltip_text = "Click to copy the seed"
	_seed_button.add_theme_font_override("font", font)
	_seed_button.add_theme_font_size_override("font_size", 11)
	_seed_button.modulate = Color(1, 1, 1, 0.55)
	_seed_button.pressed.connect(func(): DisplayServer.clipboard_set(RngManager.get_seed()))
	_layer.add_child(_seed_button)
	_seed_button.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 4
	)
	_seed_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_seed_button.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Console (top, 45 % of the screen)
	_console = PanelContainer.new()
	_console.name = "Console"
	_console.visible = false
	_console.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.08, 0.92)))
	_layer.add_child(_console)
	# Offsets too, not just anchors: anchors alone keep the (zero) size the
	# control has right now, which pins it to a sliver at the left edge.
	_console.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_console.anchor_bottom = 0.45
	_console.offset_bottom = 0.0
	var box := VBoxContainer.new()
	_console.add_child(box)
	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = true
	_log_view.selection_enabled = true
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.add_theme_font_override("normal_font", font)
	_log_view.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_log_view)
	_input_line = LineEdit.new()
	_input_line.placeholder_text = "command (help, Tab completes, Esc closes)"
	_input_line.add_theme_font_override("font", font)
	_input_line.text_submitted.connect(_on_submitted)
	box.add_child(_input_line)

	# Overlay and seed draw above the console.
	_layer.move_child(_overlay_panel, -1)
	_layer.move_child(_seed_button, -1)


func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_content_margin_all(6)
	return style
