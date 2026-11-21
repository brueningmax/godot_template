class_name SceneRegistry
extends RefCounted
## Maps every SceneKey to the path of its scene file. Nothing is loaded here:
## SceneManager loads a scene (on a background thread) only when it's needed.
##
## Because this file holds plain strings, any script may use it, including
## autoloads and scenes that are themselves registered.

## Add new keys at the END: exported SceneKey values (e.g. start_scene on
## main.tscn) are stored as numbers, so inserting one shifts the others.
enum SceneKey { SPLASH_SCREEN, MAIN_MENU, DEBUG_VIEWER, GAME_SCENE, LOADING_SCREEN }

const PATHS: Dictionary[int, String] = {
	SceneKey.SPLASH_SCREEN: "res://scenes/ui/splash_screen/splash_screen.tscn",
	SceneKey.MAIN_MENU: "res://scenes/ui/menus/main_menu/main_menu.tscn",
	SceneKey.DEBUG_VIEWER: "res://scenes/debug/scene_library/scene_library.tscn",
	# Replace with your game's first scene.
	SceneKey.GAME_SCENE: "res://scenes/game/hello_world/hello_world.tscn",
	SceneKey.LOADING_SCREEN: "res://scenes/ui/loading_screen/loading_screen.tscn",
}


## The scene file for `key`, or "" if the key has no scene.
static func path_of(key: int) -> String:
	return PATHS.get(key, "")


## "MAIN_MENU" for a known key, the number as text for anything else.
static func key_name(key: int) -> String:
	var names := SceneKey.keys()
	return names[key] if key >= 0 and key < names.size() else str(key)
