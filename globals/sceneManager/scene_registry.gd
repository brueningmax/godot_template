extends Node
class_name SceneRegistry

enum SceneKey {
	SplashScreen,
	MainMenu,
	DebugViewer,

	GameScene
}

const SCENES = {
	# Wire up your splash screen here:
	# SceneKey.SplashScreen: preload("res://scenes/ui/splash_screen/splash_screen.tscn"),
	SceneKey.MainMenu: preload("res://scenes/ui/Menus/Main_menu/main_menu.tscn"),
	SceneKey.DebugViewer: preload("res://scenes/debug/scene_library/scene_library.tscn"),

	SceneKey.GameScene: preload("res://scenes/debug/scene_library/scene_library.tscn"),
}
