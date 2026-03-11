extends MenuBase
class_name PauseMenu

signal resume_pressed
signal settings_pressed
signal restart_pressed
signal quit_pressed
@onready var btn_resume: UIButton = $MarginContainer/VBoxContainer/VBoxContainer/Resume
@onready var btn_settings: UIButton = $MarginContainer/VBoxContainer/VBoxContainer/Settings
@onready var btn_restart: UIButton = $MarginContainer/VBoxContainer/VBoxContainer/Restart
@onready var btn_quit: UIButton = $MarginContainer/VBoxContainer/VBoxContainer/Quit

func _ready() -> void:
	default_focus = btn_resume.get_path()
	btn_resume.pressed.connect(func(): resume_pressed.emit())
	btn_settings.pressed.connect(func(): settings_pressed.emit())
	btn_restart.pressed.connect(func(): restart_pressed.emit())
	btn_quit.pressed.connect(func(): quit_pressed.emit())

func _unhandled_input(e: InputEvent) -> void:
	if not visible: return
	if e.is_action_pressed("pause"):
		resume_pressed.emit()  # Esc = resume
		accept_event()
