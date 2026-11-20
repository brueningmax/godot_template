extends Control
## Template splash screen: shows the project icon and name.
## Swap the texture or label for your own logo / studio name.
##
## Emits `skipped` on any key, mouse or controller button press. SceneManager
## listens for that signal on intermediate screens and moves on early.

signal skipped

@onready var title: Label = %Title


func _ready() -> void:
	title.text = ProjectSettings.get_setting("application/config/name", "")


func _input(event: InputEvent) -> void:
	var is_button := event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton
	if is_button and event.is_pressed() and not event.is_echo():
		skipped.emit()
		get_viewport().set_input_as_handled()
