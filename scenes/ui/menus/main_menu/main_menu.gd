class_name MainMenu
extends MenuBase

@onready var btn_play: UIButton = $MarginContainer/VBoxContainer/Play
@onready var seed_input: LineEdit = $"MarginContainer/VBoxContainer/HBoxContainer/Seed Input"


func _ready() -> void:
	GameState.enter_menu()
	default_focus = btn_play.get_path()
	grab_default_focus.call_deferred()


func _on_play_pressed() -> void:
	# if the text is "", the RngManager will create a random seed
	RngManager.set_seed(seed_input.text)
	SceneManager.change_scene(SceneRegistry.SceneKey.GAME_SCENE)


func _on_debug_pressed() -> void:
	SceneManager.change_scene(SceneRegistry.SceneKey.DEBUG_VIEWER)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_options_pressed() -> void:
	GameState.open_settings()
