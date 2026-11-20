extends Node
class_name SceneRegistry

enum SceneKey { SplashScreen, MainMenu, DebugViewer, GameScene }

const SCENES = {
	SceneKey.SplashScreen: preload("res://scenes/ui/splash_screen/splash_screen.tscn"),
	SceneKey.MainMenu: preload("res://scenes/ui/Menus/Main_menu/main_menu.tscn"),
	SceneKey.DebugViewer: preload("res://scenes/debug/scene_library/scene_library.tscn"),
	# Replace with your game's first scene.
	SceneKey.GameScene: preload("res://scenes/game/hello_world/hello_world.tscn"),
}
