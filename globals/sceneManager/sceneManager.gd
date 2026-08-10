extends Node
class_name MainRoot

const DEFAULT_SCREEN_TIME: float = 2.0
const DEFAULT_FADE_DURATION: float = 0.25

var current_scene: Node = null
var fade_rect: ColorRect
var _changing := false

@onready var holder := Node.new()
@onready var overlay := CanvasLayer.new()

signal scene_changed(new_scene: Node)

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

	if use_fade:
		if current_scene:
			current_scene.hide()
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

	if current_scene:
		current_scene.hide()
	await _fade_out(DEFAULT_FADE_DURATION)

	if current_scene:
		current_scene.queue_free()
	current_scene = null

	var screen_packed: PackedScene = SceneRegistry.SCENES.get(screen_key)
	var screen_node: Node = null
	if screen_packed:
		screen_node = screen_packed.instantiate()
		overlay.add_child(screen_node)
		await _fade_in(DEFAULT_FADE_DURATION)
	else:
		push_warning("SceneManager: No scene registered for screen key: %s — skipping screen." % SceneRegistry.SceneKey.keys()[screen_key])

	await get_tree().create_timer(screen_time).timeout
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
