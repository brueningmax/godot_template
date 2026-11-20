extends Node
class_name MainRoot

const DEFAULT_SCREEN_TIME: float = 2.0
const DEFAULT_FADE_DURATION: float = 0.25

var current_scene: Node = null
var fade_rect: ColorRect
var _changing := false

# Incremented for every intermediate screen, so a stale timer or skip from an
# earlier screen can't end a later one.
var _screen_token := 0
var _screen_done_token := -1

@onready var holder := Node.new()
@onready var overlay := CanvasLayer.new()

signal scene_changed(new_scene: Node)
signal _screen_finished(token: int)

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
func change_scene(scene_key: SceneRegistry.SceneKey, payload: Dictionary = {}, use_fade: bool = false) -> void:
	if _changing: return
	_changing = true

	var packed: PackedScene = SceneRegistry.SCENES.get(scene_key)
	if packed == null:
		push_error("SceneManager: No scene registered for key: %s" % SceneRegistry.SceneKey.keys()[scene_key])
		_changing = false
		return

	_emit_signal_bus("scene_change_started", scene_key)
	_adopt_standalone_scene()

	if use_fade:
		if current_scene:
			_set_visible(current_scene, false)
		await _fade_out(DEFAULT_FADE_DURATION)

	if current_scene:
		current_scene.queue_free()

	var new_scene := packed.instantiate()
	holder.add_child(new_scene)
	current_scene = new_scene

	if use_fade:
		await _fade_in(DEFAULT_FADE_DURATION)

	_apply_payload(current_scene, payload)
	emit_signal("scene_changed", current_scene)
	_emit_signal_bus("scene_change_finished", current_scene)
	_changing = false


# Transition to a scene with an intermediate screen (splash, loading, etc.).
func change_scene_with_screen(next_key: SceneRegistry.SceneKey, screen_key: SceneRegistry.SceneKey, screen_time: float = DEFAULT_SCREEN_TIME, payload: Dictionary = {}) -> void:
	if _changing: return
	_changing = true

	var next_packed: PackedScene = SceneRegistry.SCENES.get(next_key)
	if next_packed == null:
		push_error("SceneManager: No scene registered for key: %s" % SceneRegistry.SceneKey.keys()[next_key])
		_changing = false
		return

	_emit_signal_bus("scene_change_started", next_key)
	_adopt_standalone_scene()

	if current_scene:
		_set_visible(current_scene, false)
	await _fade_out(DEFAULT_FADE_DURATION)

	if current_scene:
		current_scene.queue_free()
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
		push_warning("SceneManager: No scene registered for screen key: %s — skipping screen." % SceneRegistry.SceneKey.keys()[screen_key])

	await _wait_for_screen(token, screen_time)
	await _fade_out(DEFAULT_FADE_DURATION)

	var new_scene := next_packed.instantiate()
	holder.add_child(new_scene)
	current_scene = new_scene

	if screen_node:
		screen_node.queue_free()

	await _fade_in(DEFAULT_FADE_DURATION)
	_apply_payload(current_scene, payload)
	emit_signal("scene_changed", current_scene)
	_emit_signal_bus("scene_change_finished", current_scene)
	_changing = false


# Convenience: return to the main menu with a splash screen.
func goto_menu() -> void:
	await change_scene_with_screen(SceneRegistry.SceneKey.MainMenu, SceneRegistry.SceneKey.SplashScreen)


# --- Helpers ---

# A scene started on its own (F6 / "run current scene") is the tree's
# current_scene, outside our SceneHolder. Take ownership of it so the first
# change_scene() replaces it instead of leaving it on screen underneath.
func _adopt_standalone_scene() -> void:
	if current_scene != null:
		return
	var standalone := get_tree().current_scene
	if standalone != null and standalone != self:
		current_scene = standalone


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
	get_tree().create_timer(screen_time).timeout.connect(_finish_screen.bind(token))
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

func _emit_signal_bus(signal_name: String, arg) -> void:
	if "SignalBus" in get_tree().root:
		get_tree().root.get_node("SignalBus").emit_signal(signal_name, arg)

func _fade_out(dur: float) -> void:
	fade_rect.visible = true
	var t := create_tween()
	t.tween_property(fade_rect, "modulate:a", 1.0, dur)
	await t.finished

func _fade_in(dur: float) -> void:
	var t := create_tween()
	t.tween_property(fade_rect, "modulate:a", 0.0, dur)
	await t.finished
	fade_rect.visible = false
