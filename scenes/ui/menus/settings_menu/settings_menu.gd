class_name SettingsMenu
extends MenuBase
## Settings menu built from the ROWS list below.
##
## Behaviour: changes apply immediately (preview, not saved). Apply saves and
## closes; Back / Esc restores the values from when the menu was opened.
##
## To add a setting to the menu, add one entry to ROWS. The setting itself
## (default value and how it's applied) lives in SettingsManager.
##
## Row fields: section, key, label, type, tab (tab title), and per type.
## Labels, tab titles and option labels are English source text; controls
## translate them automatically (see localization/).
##   SLIDER  min, max, step (default 0..1, 0.05), format: "percent" (default),
##           "x" (1.25x) or "int"
##   TOGGLE  -
##   OPTION  options: [[value, "Label"], ...], or the name of a method of this
##           menu returning that list (for lists only known at runtime)
##   BINDING section "input", key = an action in InputBindings.REBINDABLE:
##           a keyboard and a controller RebindButton
## Any row: debug_only = true hides it in release builds; tooltip = "…"
## explains the setting (shown on mouse hover and on keyboard/controller focus).
##
## Controller: LB / RB (ui_tab_previous / ui_tab_next, also PageUp / PageDown)
## switch tabs; B goes back like Esc.

signal back_pressed
signal apply_pressed

enum RowType { SLIDER, TOGGLE, OPTION, BINDING }

const ROWS := [
	# Audio
	{
		tab = "Audio",
		section = "audio",
		key = "master_volume",
		label = "Master",
		type = RowType.SLIDER
	},
	{
		tab = "Audio",
		section = "audio",
		key = "music_volume",
		label = "Music",
		type = RowType.SLIDER
	},
	{
		tab = "Audio",
		section = "audio",
		key = "sfx_volume",
		label = "Effects",
		type = RowType.SLIDER
	},
	{
		tab = "Audio",
		section = "audio",
		key = "ambient_volume",
		label = "Ambience",
		type = RowType.SLIDER
	},
	{
		tab = "Audio",
		section = "audio",
		key = "ui_volume",
		label = "Interface",
		type = RowType.SLIDER
	},
	# Display
	{
		tab = "Display",
		section = "display",
		key = "window_mode",
		label = "Window mode",
		type = RowType.OPTION,
		tooltip = "Fullscreen switches apps instantly. Exclusive fullscreen can lower input lag.",
		options =
		[
			["windowed", "Windowed"],
			["fullscreen", "Fullscreen"],
			["exclusive", "Exclusive fullscreen"]
		],
	},
	{
		tab = "Display",
		section = "display",
		key = "resolution",
		label = "Window size",
		type = RowType.OPTION,
		options = "_resolution_options",
	},
	{
		tab = "Display",
		section = "display",
		key = "vsync",
		label = "VSync",
		type = RowType.TOGGLE,
		tooltip = "Matches the frame rate to your monitor to avoid tearing.",
	},
	{
		tab = "Display",
		section = "display",
		key = "max_fps",
		label = "FPS cap",
		type = RowType.OPTION,
		tooltip = "Highest frame rate the game runs at. Lower values save power.",
		options =
		[[0, "Unlimited"], [30, "30"], [60, "60"], [120, "120"], [144, "144"], [240, "240"]],
	},
	# Interface
	{
		tab = "Interface",
		section = "interface",
		key = "ui_scale",
		label = "UI scale",
		type = RowType.SLIDER,
		tooltip = "Size of menus and text.",
		min = 0.75,
		max = 2.0,
		step = 0.05,
		format = "x",
	},
	{
		tab = "Interface",
		section = "interface",
		key = "screen_shake",
		label = "Screen shake",
		type = RowType.SLIDER,
		tooltip = "How strongly the screen shakes on hits. 0% turns it off.",
	},
	{
		tab = "Interface",
		section = "interface",
		key = "language",
		label = "Language",
		type = RowType.OPTION,
		options = "_language_options",
	},
	# Controls
	{tab = "Controls", section = "input", key = "up", label = "Move up", type = RowType.BINDING},
	{
		tab = "Controls",
		section = "input",
		key = "down",
		label = "Move down",
		type = RowType.BINDING
	},
	{
		tab = "Controls",
		section = "input",
		key = "left",
		label = "Move left",
		type = RowType.BINDING
	},
	{
		tab = "Controls",
		section = "input",
		key = "right",
		label = "Move right",
		type = RowType.BINDING
	},
	{tab = "Controls", section = "input", key = "jump", label = "Jump", type = RowType.BINDING},
	{tab = "Controls", section = "input", key = "pause", label = "Pause", type = RowType.BINDING},
	{
		tab = "Controls",
		section = "input",
		key = "debug_overlay",
		label = "Debug overlay",
		type = RowType.BINDING,
		debug_only = true,
	},
	{
		tab = "Controls",
		section = "input",
		key = "debug_console",
		label = "Debug console",
		type = RowType.BINDING,
		debug_only = true,
	},
]

## Window sizes offered in windowed mode (the current one is added if missing).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

## "section/key" -> the Range, BaseButton or OptionButton showing that setting.
var _controls: Dictionary = {}
## "section/key" -> option values, in the order of the OptionButton's items.
var _option_values: Dictionary = {}
var _tab_boxes: Dictionary = {}
var _snapshot: Dictionary = {}

@onready var tabs: TabContainer = %Tabs
@onready var btn_back: Button = %BtnBack
@onready var btn_apply: Button = %BtnApply


func _ready() -> void:
	for row in _rows():
		_build_row(row)
	if _tab_boxes.has("Controls"):
		_add_reset_controls_button(_tab_boxes["Controls"])
	if not _rows().is_empty():
		default_focus = _controls[_id(_rows()[0])].get_path()
	tabs.tab_changed.connect(_on_tab_changed)
	btn_back.pressed.connect(cancel)
	btn_apply.pressed.connect(apply)


## Saves the previewed values and closes.
func apply() -> void:
	SettingsManager.save_settings()
	_snapshot = SettingsManager.snapshot()
	apply_pressed.emit()


## Reverts to the values from when the menu was opened and closes.
## GameState calls this when Esc / ui_cancel is pressed while the menu is on top.
func cancel() -> void:
	SettingsManager.restore(_snapshot)
	back_pressed.emit()


func _on_open() -> void:
	_snapshot = SettingsManager.snapshot()
	_refresh()


# --- Rows -------------------------------------------------------------------


func _build_row(row: Dictionary) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)

	var label := Label.new()
	label.text = row.label
	label.custom_minimum_size.x = 160
	box.add_child(label)

	var control: Control
	match row.type:
		RowType.SLIDER:
			var slider := HSlider.new()
			slider.min_value = row.get("min", 0.0)
			slider.max_value = row.get("max", 1.0)
			slider.step = row.get("step", 0.05)
			slider.custom_minimum_size.x = 220
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var readout := Label.new()
			readout.custom_minimum_size.x = 56
			readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			readout.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # a number
			slider.value_changed.connect(
				func(v: float):
					readout.text = _format(row, v)
					SettingsManager.set_setting(row.section, row.key, v, false)
			)
			box.add_child(slider)
			box.add_child(readout)
			control = slider
		RowType.TOGGLE:
			var toggle := CheckButton.new()
			toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			toggle.toggled.connect(
				func(on: bool): SettingsManager.set_setting(row.section, row.key, on, false)
			)
			box.add_child(toggle)
			control = toggle
		RowType.BINDING:
			var keyboard := RebindButton.new()
			keyboard.action = row.key
			keyboard.device = InputBindings.Device.KEYBOARD
			keyboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var gamepad := RebindButton.new()
			gamepad.action = row.key
			gamepad.device = InputBindings.Device.GAMEPAD
			gamepad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# A swap changes another row too, so refresh them all.
			keyboard.rebound.connect(func(_a, _e): _refresh())
			gamepad.rebound.connect(func(_a, _e): _refresh())
			box.add_child(keyboard)
			box.add_child(gamepad)
			control = keyboard
		RowType.OPTION:
			var option := OptionButton.new()
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.item_selected.connect(
				func(index: int):
					var value: Variant = _option_values[_id(row)][index]
					SettingsManager.set_setting(row.section, row.key, value, false)
			)
			box.add_child(option)
			control = option

	var tooltip: String = row.get("tooltip", "")
	if tooltip != "":
		label.tooltip_text = tooltip
		label.mouse_filter = Control.MOUSE_FILTER_PASS  # labels ignore the mouse otherwise
		control.tooltip_text = tooltip

	_tab_box(row.get("tab", "General")).add_child(box)
	_controls[_id(row)] = control


# The row container of a tab, created on first use (tabs appear in ROWS order).
func _tab_box(title: String) -> VBoxContainer:
	if not _tab_boxes.has(title):
		var box := VBoxContainer.new()
		box.name = title
		box.add_theme_constant_override("separation", 12)
		tabs.add_child(box)
		tabs.set_tab_title(box.get_index(), title)  # translated by the tab bar
		_tab_boxes[title] = box
	return _tab_boxes[title]


## Shows the current values without triggering the controls' signals.
func _refresh() -> void:
	for row in _rows():
		var control: Control = _controls[_id(row)]
		var value: Variant = SettingsManager.get_setting(row.section, row.key)
		match row.type:
			RowType.SLIDER:
				var slider := control as HSlider
				slider.set_value_no_signal(float(value))
				# Readout is the next sibling of the slider.
				var readout := slider.get_parent().get_child(slider.get_index() + 1) as Label
				readout.text = _format(row, float(value))
			RowType.TOGGLE:
				(control as BaseButton).set_pressed_no_signal(bool(value))
			RowType.OPTION:
				_fill_options(row, control as OptionButton, value)
			RowType.BINDING:
				for button in control.get_parent().get_children():
					if button is RebindButton:
						button.refresh()


# (Re)builds an OptionButton's items and selects `value`. A value that isn't
# in the list (e.g. a size edited into the file) is added, so it still shows.
func _fill_options(row: Dictionary, option: OptionButton, value: Variant) -> void:
	var options: Array = row.options if row.options is Array else call(row.options)
	var values: Array = []
	option.clear()
	for entry in options:
		values.append(entry[0])
		option.add_item(entry[1])
	if not values.has(value):
		values.append(value)
		option.add_item(str(value))
	_option_values[_id(row)] = values
	option.select(values.find(value))


func _add_reset_controls_button(box: VBoxContainer) -> void:
	var reset := Button.new()
	reset.name = "ResetControls"
	reset.text = "Reset controls"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset.pressed.connect(
		func():
			SettingsManager.reset_controls(false)
			_refresh()
	)
	box.add_child(reset)


# --- Tabs and focus ----------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var step := 0
	if event.is_action_pressed("ui_tab_previous"):
		step = -1
	elif event.is_action_pressed("ui_tab_next"):
		step = 1
	if step != 0:
		tabs.current_tab = wrapi(tabs.current_tab + step, 0, tabs.get_tab_count())
		get_viewport().set_input_as_handled()


# Keep keyboard / controller focus inside the visible tab.
func _on_tab_changed(_tab: int) -> void:
	if not is_visible_in_tree() or get_viewport().gui_get_focus_owner() is TabBar:
		return  # someone is browsing the tab bar itself
	var first := _first_focusable(tabs.get_current_tab_control())
	if first:
		first.grab_focus()


func _format(row: Dictionary, value: float) -> String:
	match row.get("format", "percent"):
		"x":
			return "%.2fx" % value
		"int":
			return str(roundi(value))
	return "%d%%" % roundi(value * 100.0)


func _resolution_options() -> Array:
	var options := []
	for size in RESOLUTIONS:
		options.append([size, "%d × %d" % [size.x, size.y]])
	return options


# "System" plus every language with a loaded translation, each named in its
# own language (the LANGUAGE_NAME entry of its .po file), so players find theirs.
func _language_options() -> Array:
	var options := [["", "System"]]
	for locale in TranslationServer.get_loaded_locales():
		if options.any(func(o): return o[0] == locale):
			continue
		var native := TranslationServer.get_translation_object(locale).get_message(&"LANGUAGE_NAME")
		options.append([locale, str(native) if native != &"" else locale])
	return options


# ROWS without debug_only rows in release builds.
func _rows() -> Array:
	return ROWS.filter(func(row): return OS.is_debug_build() or not row.get("debug_only", false))


func _id(row: Dictionary) -> String:
	return "%s/%s" % [row.section, row.key]
