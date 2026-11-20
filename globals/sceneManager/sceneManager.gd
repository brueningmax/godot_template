class_name MainRoot
extends Node

signal scene_changed(new_scene: Node)
signal _screen_finished(token: int)

const DEFAULT_SCREEN_TIME: float = 2.0
const DEFAULT_FADE_DURATION: float = 0.25

var current_scene: Node = null
## SceneRegistry.SceneKey of current_scene, or -1 (adopted standalone scene / none).
var current_key: int = -1
## Take over a scene that was started on its own (F6) on the first change.
## Test runners turn this off, so their own runner scene is never adopted.
var adopt_standalone := true
var fade_rect: ColorRect
var _changing := false

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


# Transition to a scene directly, with an optional fade.
func change_scene(
	scene_key: SceneRegistry.SceneKey, payload: Dictionary = {}, use_fade: bool = false
) -> void:
	var packed: PackedScene = SceneRegistry.SCENES.get(scene_key)
	if packed == null:
		push_error("SceneManager: No scene registered for key: %s" % _key_name(scene_key))
		return
	await _change_to(packed, scene_key, payload, use_fade)


# Re-creates the current scene from its file (e.g. "Restart" in the pause menu).
# Also works for a scene that was started on its own (F6) and adopted.
func reload_current(payload: Dictionary = {}, use_fade: bool = true) -> void:
	_adopt_standalone_scene()
	if current_scene == null or current_scene.scene_file_path == "":
		push_error("SceneManager: reload_current() has no scene file to reload")
		return
	var packed: PackedScene = load(current_scene.scene_file_path)
	await _change_to(packed, current_key, payload, use_fade)


## True while a transition is running. New change requests are ignored then.
func is_changing() -> bool:
	return _changing


func _change_to(packed: PackedScene, key: int, payload: Dictionary, use_fade: bool) -> void:
	if _changing:
		return
	_changing = true

	SignalBus.scene_change_started.emit(key)
	_adopt_standalone_scene()

	if use_fade:
		if current_scene:
			_set_visible(current_scene, false)
		await _fade_out(DEFAULT_FADE_DURATION)

	if current_scene:
		_free_scene(current_scene)

	var new_scene := packed.instantiate()
	holder.add_child(new_scene)
	current_scene = new_scene
	current_key = key

	if use_fade:
		await _fade_in(DEFAULT_FADE_DURATION)

	_apply_payload(current_scene, payload)
	scene_changed.emit(current_scene)
	SignalBus.scene_change_finished.emit(current_scene)
	_changing = false


# Transition to a scene with an intermediate screen (splash, loading, etc.).
func change_scene_with_screen(
	next_key: SceneRegistry.SceneKey,
	screen_key: SceneRegistry.SceneKey,
	screen_time: float = DEFAULT_SCREEN_TIME,
	payload: Dictionary = {}
) -> void:
	if _changing:
		return
	_changing = true

	var next_packed: PackedScene = SceneRegistry.SCENES.get(next_key)
	if next_packed == null:
		push_error("SceneManager: No scene registered for key: %s" % _key_name(next_key))
		_changing = false
		return

	SignalBus.scene_change_started.emit(next_key)
	_adopt_standalone_scene()

	if current_scene:
		_set_visible(current_scene, false)
	await _fade_out(DEFAULT_FADE_DURATION)

	if current_scene:
		_free_scene(current_scene)
	current_scene = null

	var screen_packed: PackedScene = SceneRegistry.SCENES.get(screen_key)
	var screen_node: Node = null
	if screen_packed:
		screen_node = screen_packed.instantiate()
		overlay.add_child(screen_node)
		overlay.move_child(fade_rect, -1)  # keep the fade drawn above the screen
	# Listen for a skip from the moment the screen exists (also during its fade-in).
	var token := _begin_screen(screen_node)
	if screen_node:
		await _fade_in(DEFAULT_FADE_DURATION)
	else:
		push_warning(
			(
				"SceneManager: No scene registered for screen key: %s — skipping screen."
				% _key_name(screen_key)
			)
		)

	await _wait_for_screen(token, screen_time)
	await _fade_out(DEFAULT_FADE_DURATION)

	var new_scene := next_packed.instantiate()
	holder.add_child(new_scene)
	current_scene = new_scene
	current_key = next_key

	if screen_node:
		screen_node.queue_free()

	await _fade_in(DEFAULT_FADE_DURATION)
	_apply_payload(current_scene, payload)
	scene_changed.emit(current_scene)
	SignalBus.scene_change_finished.emit(current_scene)
	_changing = false


# Convenience: return to the main menu with a splash screen.
func goto_menu() -> void:
	await change_scene_with_screen(
		SceneRegistry.SceneKey.MAIN_MENU, SceneRegistry.SceneKey.SPLASH_SCREEN
	)


# --- Helpers ---


# "MAIN_MENU" for a known key, the number for anything else (never errors,
# since it's used to build error messages).
func _key_name(key: int) -> String:
	var names := SceneRegistry.SceneKey.keys()
	return names[key] if key >= 0 and key < names.size() else str(key)


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
