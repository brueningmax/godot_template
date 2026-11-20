class_name SceneRegistry
extends Node

## Add new keys at the END: exported SceneKey values (e.g. start_scene on
## main.tscn) are stored as numbers, so inserting one shifts the others.
enum SceneKey { SPLASH_SCREEN, MAIN_MENU, DEBUG_VIEWER, GAME_SCENE }

const SCENES = {
	SceneKey.SPLASH_SCREEN: preload("res://scenes/ui/splash_screen/splash_screen.tscn"),
	SceneKey.MAIN_MENU: preload("res://scenes/ui/menus/main_menu/main_menu.tscn"),
	SceneKey.DEBUG_VIEWER: preload("res://scenes/debug/scene_library/scene_library.tscn"),
	# Replace with your game's first scene.
	SceneKey.GAME_SCENE: preload("res://scenes/game/hello_world/hello_world.tscn"),
}
