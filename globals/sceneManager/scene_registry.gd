extends Node
class_name SceneRegistry

enum SceneKey {
	SplashScreen,
	MainMenu,
	DebugViewer
}

const SCENES = {
	# SceneKey.SplashScreen: preload("res://scenes/main/Game/splashScreen/splash_screen.tscn"),
	SceneKey.MainMenu: preload("res://scenes/ui/Menus/Main_menu/main_menu.tscn"),
	SceneKey.DebugViewer: preload("res://scenes/debug/scene_library/scene_library.tscn")
	
	# SceneKey.GameSession: preload("res://scenes/main/Game_Session/game_session.tscn")
}
