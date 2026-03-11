extends MenuBase
class_name SettingsMenu

signal back_pressed
signal apply_pressed

@onready var btn_back: Button = $Panel/MarginContainer/VBoxContainer/HBoxContainer/BtnBack
@onready var btn_apply: Button = $Panel/MarginContainer/VBoxContainer/HBoxContainer/BtnApply


func _ready() -> void:
	default_focus = btn_apply.get_path()
	btn_back.pressed.connect(func(): back_pressed.emit())
	btn_apply.pressed.connect(func(): apply_pressed.emit())


func _unhandled_input(e: InputEvent) -> void:
	if not visible: return
	if e.is_action_pressed("pause"):
		back_pressed.emit()
		accept_event()
