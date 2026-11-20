extends Node
## Start-up flow of the full game. Attached to Main.tscn (the project's main scene).
##
## This runs ONLY when the whole project is started (F5 / exported game).
## Running a single scene (F6, or "run current scene" in VS Code) never loads
## Main.tscn, so that scene runs on its own without being sent to the menu.
##
## Change the start flow by editing the exported values on Main.tscn.

## Scene to show after the (optional) splash.
@export var start_scene: SceneRegistry.SceneKey = SceneRegistry.SceneKey.MainMenu

## Show an intermediate screen (logo, studio name...) before `start_scene`.
@export var show_splash := true

## Which registered scene to use as the splash.
@export var splash_scene: SceneRegistry.SceneKey = SceneRegistry.SceneKey.SplashScreen

## How long the splash stays up, in seconds (it can be skipped with any input).
@export_range(0.0, 10.0, 0.1) var splash_time := 2.0


func _ready() -> void:
	# Leave the tree first: this node has done its job, and SceneManager must
	# not mistake it for a standalone scene it should take over.
	get_parent().remove_child.call_deferred(self)
	_start.call_deferred()


func _start() -> void:
	if show_splash:
		SceneManager.change_scene_with_screen(start_scene, splash_scene, splash_time)
	else:
		SceneManager.change_scene(start_scene)
	queue_free()
