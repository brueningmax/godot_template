class_name TemplateTest
extends GutTest
## Base class for tests that touch the template's global state (scenes,
## pause, overlay menus). Resets everything after each test so tests can't
## leak into each other.
##
## If you override before_all(), after_all() or after_each(), call the
## super version in it (`await super.after_each()`).

## Seconds to wait for a scene transition to finish before failing.
const TRANSITION_TIMEOUT := 5.0

var _gut_root: Node
var _gut_root_mode: Node.ProcessMode


func before_all() -> void:
	# In the GUT editor panel, GUT's runner is the tree's current scene; never
	# let SceneManager adopt (and free) it.
	SceneManager.adopt_standalone = false
	# GUT's own nodes must keep running while a test pauses the game,
	# otherwise every wait_*() after a pause never returns.
	_gut_root = self
	while _gut_root.get_parent() != get_tree().root:
		_gut_root = _gut_root.get_parent()
	_gut_root_mode = _gut_root.process_mode
	_gut_root.process_mode = Node.PROCESS_MODE_ALWAYS


func after_all() -> void:
	SceneManager.adopt_standalone = true
	_gut_root.process_mode = _gut_root_mode


func after_each() -> void:
	await wait_for_transition()
	GameState.enter_menu()  # unpauses, closes overlay menus, shows the cursor
	var scene := SceneManager.current_scene
	if is_instance_valid(scene):
		SceneManager._free_scene(scene)
	SceneManager.current_scene = null
	SceneManager.current_key = -1
	await wait_process_frames(1)


## Waits until SceneManager has finished any running transition.
func wait_for_transition() -> void:
	if SceneManager.is_changing():
		await wait_until(func(): return not SceneManager.is_changing(), TRANSITION_TIMEOUT)


## Changes scene and waits for the transition to finish.
func goto(key: int, payload := {}, use_fade := false) -> Node:
	SceneManager.change_scene(key, payload, use_fade)
	await wait_for_transition()
	return SceneManager.current_scene


## Sends an input action (as if pressed) and lets it be processed.
func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await wait_process_frames(3)


## The overlay menu with this node name on GameState's menu layer, or null.
func overlay_menu(menu_name: String) -> Control:
	return GameState.get_node_or_null("MenuLayer/" + menu_name) as Control
