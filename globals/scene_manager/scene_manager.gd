class_name MainRoot
extends Node

signal scene_changed(new_scene: Node)
signal _screen_finished(token: int)

const DEFAULT_SCREEN_TIME: float = 2.0
const DEFAULT_FADE_DURATION: float = 0.25
const DEFAULT_LOADING_SCREEN_DELAY: float = 0.3

var current_scene: Node = null
## SceneRegistry.SceneKey of current_scene, or -1 (adopted standalone scene / none).
var current_key: int = -1
## Take over a scene that was started on its own (F6) on the first change.
## Test runners turn this off, so their own runner scene is never adopted.
var adopt_standalone := true
## Seconds a load may run before the loading screen appears. Loads that finish
## sooner show nothing. 0 shows it for every scene that isn't already in memory.
var loading_screen_delay: float = DEFAULT_LOADING_SCREEN_DELAY
## Registered scene used as the loading screen, or -1 for none.
var loading_screen_key: int = SceneRegistry.SceneKey.LOADING_SCREEN
var fade_rect: ColorRect
var _changing := false
# Paths with a threaded load started by us that hasn't been collected yet.
var _requested: Dictionary[String, bool] = {}
var _loading_screen: Node = null

# Incremented for every intermediate screen, so a stale timer or skip from an
# earlier screen can't end a later one.
var _screen_token := 0
var _screen_done_token := -1

@onready var holder := Node.new()
@onready var overlay := CanvasLayer.new()


func _ready() -> void:
	holder.name = "SceneHolder"
	add_child(holder)
	overlay.name = "Overlay"
	overlay.layer = 100
	add_child(overlay)

	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	fade_rect.visible = false
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fade_rect)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)


# Transition to a scene directly, with an optional fade. The scene loads on a
# background thread; the old scene stays until the new one is ready.
func change_scene(
	scene_key: SceneRegistry.SceneKey, payload: Dictionary = {}, use_fade: bool = false
) -> void:
	var path := SceneRegistry.path_of(scene_key)
	if path == "":
		Log.error(&"Scene", "No scene registered for key: %s" % SceneRegistry.key_name(scene_key))
		return
	await _change_to(path, scene_key, payload, use_fade)


# Re-creates the current scene from its file (e.g. "Restart" in the pause menu).
# Also works for a scene that was started on its own (F6) and adopted.
func reload_current(payload: Dictionary = {}, use_fade: bool = true) -> void:
	_adopt_standalone_scene()
	if current_scene == null or current_scene.scene_file_path == "":
		Log.error(&"Scene", "reload_current() has no scene file to reload")
		return
	await _change_to(current_scene.scene_file_path, current_key, payload, use_fade)


## Starts loading a scene in the background, e.g. the next level while the
## player is still in this one. A later change to it then starts instantly.
## Each preloaded scene stays in memory until it is changed to.
func preload_scene(scene_key: SceneRegistry.SceneKey) -> void:
	var path := SceneRegistry.path_of(scene_key)
	if path == "" or not ResourceLoader.exists(path):
		Log.error(&"Scene", "Can't preload key %s" % SceneRegistry.key_name(scene_key))
		return
	_request(path)


## True while a transition is running. New change requests are ignored then.
func is_changing() -> bool:
	return _changing


## True while the loading screen is shown.
func is_loading_screen_visible() -> bool:
	return _loading_screen != null


func _change_to(path: String, key: int, payload: Dictionary, use_fade: bool) -> void:
	if _changing:
		return
	if not ResourceLoader.exists(path):
		Log.error(&"Scene", "Scene file not found: %s" % path)
		return
	_changing = true

	SignalBus.scene_change_started.emit(key)
	_adopt_standalone_scene()
	_request(path)  # loads while the old scene fades out

	if use_fade:
		if current_scene:
			_set_visible(current_scene, false)
		await _fade_out(DEFAULT_FADE_DURATION)

	var packed := await _await_scene(path)
	if packed == null:
		# Keep the old scene; the error is already logged.
		if current_scene:
			_set_visible(current_scene, true)
		if use_fade:
			await _fade_in(DEFAULT_FADE_DURATION)
		_changing = false
		return

	if current_scene:
		_free_scene(current_scene)

	var new_scene := packed.instantiate()
	holder.add_child(new_scene)
	current_scene = new_scene
	current_key = key

	if use_fade:
		await _fade_in(DEFAULT_FADE_DURATION)

	_finish_change(payload)


# Transition to a scene with an intermediate screen (splash, "chapter 2"...).
# The next scene loads in the background while the screen is shown.
func change_scene_with_screen(
	next_key: SceneRegistry.SceneKey,
	screen_key: SceneRegistry.SceneKey,
	screen_time: float = DEFAULT_SCREEN_TIME,
	payload: Dictionary = {}
) -> void:
	if _changing:
		return
	var next_path := SceneRegistry.path_of(next_key)
	if next_path == "" or not ResourceLoader.exists(next_path):
		Log.error(&"Scene", "No scene registered for key: %s" % SceneRegistry.key_name(next_key))
		return
	_changing = true

	SignalBus.scene_change_started.emit(next_key)
	_adopt_standalone_scene()
	_request(next_path)

	if current_scene:
		_set_visible(current_scene, false)
	await _fade_out(DEFAULT_FADE_DURATION)

	if current_scene:
		_free_scene(current_scene)
	current_scene = null

	var screen_node := _instantiate_now(screen_key)
	if screen_node:
		overlay.add_child(screen_node)
		overlay.move_child(fade_rect, -1)  # keep the fade drawn above the screen
	# Listen for a skip from the moment the screen exists (also during its fade-in).
	var token := _begin_screen(screen_node)
	if screen_node:
		await _fade_in(DEFAULT_FADE_DURATION)
	else:
		Log.warn(
			&"Scene",
			(
				"No scene registered for screen key: %s — skipping screen."
				% SceneRegistry.key_name(screen_key)
			)
		)

	await _wait_for_screen(token, screen_time)
	# Usually done by now; if not, the loading screen appears above the screen.
	var next_packed := await _await_scene(next_path)
	await _fade_out(DEFAULT_FADE_DURATION)

	if screen_node:
		screen_node.queue_free()
	if next_packed == null:
		current_key = -1
		await _fade_in(DEFAULT_FADE_DURATION)
		_changing = false
		return

	var new_scene := next_packed.instantiate()
	holder.add_child(new_scene)
	current_scene = new_scene
	current_key = next_key

	await _fade_in(DEFAULT_FADE_DURATION)
	_finish_change(payload)


# Convenience: return to the main menu with a splash screen.
func goto_menu() -> void:
	await change_scene_with_screen(
		SceneRegistry.SceneKey.MAIN_MENU, SceneRegistry.SceneKey.SPLASH_SCREEN
	)


func _finish_change(payload: Dictionary) -> void:
	_apply_payload(current_scene, payload)
	Log.info(
		&"Scene", "changed to %s (%s)" % [current_scene.name, SceneRegistry.key_name(current_key)]
	)
	scene_changed.emit(current_scene)
	SignalBus.scene_change_finished.emit(current_scene)
	_changing = false


# --- Loading ---


# Starts a threaded load of `path`, unless it's already in memory or loading.
func _request(path: String) -> void:
	if _requested.has(path) or ResourceLoader.has_cached(path):
		return
	var err := ResourceLoader.load_threaded_request(path, "PackedScene")
	if err == OK:
		_requested[path] = true
	else:
		Log.error(&"Scene", "Can't start loading %s: %s" % [path, error_string(err)])


# Waits for `path` to finish loading and returns it (null on failure, logged).
# GameState is LOADING meanwhile, and the loading screen appears after
# loading_screen_delay seconds.
func _await_scene(path: String) -> PackedScene:
	if not _requested.has(path):
		return load(path) as PackedScene  # already in memory

	GameState.begin_loading()
	var start := Time.get_ticks_msec()
	if loading_screen_delay <= 0.0:
		_show_loading_screen()
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(path, progress)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if _loading_screen == null and Time.get_ticks_msec() - start >= loading_screen_delay * 1000:
			_show_loading_screen()
		_set_loading_progress(progress[0] if not progress.is_empty() else 0.0)
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path, progress)

	var packed: PackedScene = null
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
	_requested.erase(path)
	if packed == null:
		Log.error(&"Scene", "Failed to load %s" % path)
	else:
		Log.debug(&"Scene", "loaded %s in %d ms" % [path, Time.get_ticks_msec() - start])
	_set_loading_progress(1.0)
	_hide_loading_screen()
	GameState.end_loading()
	return packed


func _show_loading_screen() -> void:
	if _loading_screen != null:
		return
	_loading_screen = _instantiate_now(loading_screen_key)
	if _loading_screen:
		overlay.add_child(_loading_screen)  # on top of screens and the fade


func _hide_loading_screen() -> void:
	if _loading_screen != null:
		_free_scene(_loading_screen)
		_loading_screen = null


func _set_loading_progress(value: float) -> void:
	if _loading_screen != null and _loading_screen.has_method("set_progress"):
		_loading_screen.call("set_progress", value)


# Loads a small registered scene (screens) on the spot. Null for no scene.
func _instantiate_now(key: int) -> Node:
	var path := SceneRegistry.path_of(key)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	return packed.instantiate() if packed else null


# --- Helpers ---


# A scene started on its own (F6 / "run current scene") is the tree's
# current_scene, outside our SceneHolder. Take ownership of it so the first
# change_scene() replaces it instead of leaving it on screen underneath.
func _adopt_standalone_scene() -> void:
	if current_scene != null or not adopt_standalone:
		return
	var standalone := get_tree().current_scene
	if standalone != null and standalone != self:
		current_scene = standalone
		current_key = -1


# Takes the old scene out of the tree right away (so the new one can use the
# same node name and paths) and frees it at the end of the frame.
func _free_scene(scene: Node) -> void:
	if scene.get_parent():
		scene.get_parent().remove_child(scene)
	scene.queue_free()


# Plain Node scenes have no visibility; only hide what can be hidden.
func _set_visible(node: Node, value: bool) -> void:
	if node is CanvasItem or node is Node3D:
		node.visible = value


# Starts a new intermediate screen and, if it has a `skipped` signal, listens
# for it right away. Returns a token for _wait_for_screen().
func _begin_screen(screen_node: Node) -> int:
	_screen_token += 1
	var token := _screen_token
	if screen_node != null and screen_node.has_signal("skipped"):
		screen_node.connect("skipped", _finish_screen.bind(token), CONNECT_ONE_SHOT)
	return token


# Waits until `screen_time` has passed or the screen was skipped, whichever
# comes first. A skip that happened before this call (during the fade-in)
# counts. Screens without a `skipped` signal just wait.
func _wait_for_screen(token: int, screen_time: float) -> void:
	get_tree().create_timer(screen_time, true).timeout.connect(_finish_screen.bind(token))
	while _screen_done_token != token:
		await _screen_finished


func _finish_screen(token: int) -> void:
	# Ignore stale timers/skips from an earlier screen.
	if token == _screen_token and _screen_done_token != token:
		_screen_done_token = token
		_screen_finished.emit(token)


func _apply_payload(scene: Node, payload: Dictionary) -> void:
	if not payload.is_empty() and scene.has_method("apply_payload"):
		scene.call_deferred("apply_payload", payload)


func _fade_out(dur: float) -> void:
	fade_rect.visible = true
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(fade_rect, "modulate:a", 1.0, dur)
	await t.finished


func _fade_in(dur: float) -> void:
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(fade_rect, "modulate:a", 0.0, dur)
	await t.finished
	fade_rect.visible = false
