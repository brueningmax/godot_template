class_name MainMenu
extends Control

var mainRoot = MainRoot
@onready var seed_input: LineEdit = $"MarginContainer/VBoxContainer/HBoxContainer/Seed Input"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_play_pressed() -> void:
	# if the text is "", the RngManager will create a random seed
	RngManager.set_seed(seed_input.text)
	SceneManager.change_scene(SceneRegistry.SceneKey.GameScene)

func _on_debug_pressed() -> void:
	# if the text is "", the RngManager will create a random seed
	SceneManager.change_scene(SceneRegistry.SceneKey.DebugViewer)
	
func _on_movement_lab_pressed() -> void:
	SceneManager.goto_movement_lab(0.1)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_options_pressed() -> void:
	pass # Replace with function body
