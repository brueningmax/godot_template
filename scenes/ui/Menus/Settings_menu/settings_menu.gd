extends MenuBase
class_name SettingsMenu
## Settings menu built from the ROWS list below.
##
## Behaviour: changes apply immediately (preview, not saved). Apply saves and
## closes; Back / Esc restores the values from when the menu was opened.
##
## To add a setting to the menu, add one entry to ROWS. The setting itself
## (default value and how it's applied) lives in SettingsManager.

signal back_pressed
signal apply_pressed

enum RowType { SLIDER, TOGGLE }

const ROWS := [
	{section = "audio", key = "master_volume", label = "Master volume", type = RowType.SLIDER},
	{section = "audio", key = "music_volume", label = "Music volume", type = RowType.SLIDER},
	{section = "audio", key = "sfx_volume", label = "Effects volume", type = RowType.SLIDER},
	{section = "display", key = "fullscreen", label = "Fullscreen", type = RowType.TOGGLE},
	{section = "display", key = "vsync", label = "VSync", type = RowType.TOGGLE},
]

## "section/key" -> the Range or BaseButton showing that setting.
var _controls: Dictionary = {}
var _snapshot: Dictionary = {}

@onready var rows: VBoxContainer = %Rows
@onready var btn_back: Button = %BtnBack
@onready var btn_apply: Button = %BtnApply


func _ready() -> void:
	for row in ROWS:
		_build_row(row)
	if not ROWS.is_empty():
		default_focus = _controls[_id(ROWS[0])].get_path()
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
			slider.min_value = 0.0
			slider.max_value = 1.0
			slider.step = 0.05
			slider.custom_minimum_size.x = 220
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var readout := Label.new()
			readout.custom_minimum_size.x = 48
			readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			slider.value_changed.connect(
				func(v: float):
					readout.text = "%d%%" % roundi(v * 100.0)
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

	rows.add_child(box)
	_controls[_id(row)] = control


## Shows the current values without triggering the controls' signals.
func _refresh() -> void:
	for row in ROWS:
		var control: Control = _controls[_id(row)]
		var value: Variant = SettingsManager.get_setting(row.section, row.key)
		match row.type:
			RowType.SLIDER:
				var slider := control as HSlider
				slider.set_value_no_signal(float(value))
				# Readout is the next sibling of the slider.
				var readout := slider.get_parent().get_child(slider.get_index() + 1) as Label
				readout.text = "%d%%" % roundi(float(value) * 100.0)
			RowType.TOGGLE:
				(control as BaseButton).set_pressed_no_signal(bool(value))


func _id(row: Dictionary) -> String:
	return "%s/%s" % [row.section, row.key]
