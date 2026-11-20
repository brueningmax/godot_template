class_name MainMenu
extends Control

@onready var seed_input: LineEdit = $"MarginContainer/VBoxContainer/HBoxContainer/Seed Input"

func _ready() -> void:
	GameState.enter_menu()

func _on_play_pressed() -> void:
	# if the text is "", the RngManager will create a random seed
	RngManager.set_seed(seed_input.text)
	SceneManager.change_scene(SceneRegistry.SceneKey.GameScene)

func _on_debug_pressed() -> void:
	SceneManager.change_scene(SceneRegistry.SceneKey.DebugViewer)
	
func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_options_pressed() -> void:
	GameState.open_settings()
