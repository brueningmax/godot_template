extends Node
class_name MainRoot

const DEFAULT_SPLASH_TIME: float = 2

var current_scene: Node = null
var fade_rect: ColorRect
var _changing := false
var _next_payload: Dictionary = {}

@onready var holder := Node.new()
@onready var overlay := CanvasLayer.new()

signal scene_changed(new_scene: Node)

func _ready():
	holder.name = "SceneHolder"
	add_child(holder)
	overlay.name = "Overlay"
	overlay.layer = 100
	add_child(overlay)

	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.size = get_viewport().size
	overlay.add_child(fade_rect)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	change_scene(SceneRegistry.SceneKey.MainMenu)

func change_scene(scene_key: SceneRegistry.SceneKey) -> void:
	if _changing: return
	_changing = true

	var packed: PackedScene = SceneRegistry.SCENES.get(scene_key)
	if packed == null:
		push_error("Invalid SceneKey")
		_changing = false
		return
	var new_scene = packed.instantiate()
	
	holder.add_child(new_scene)
	if current_scene:
		current_scene.queue_free()
	current_scene = new_scene
	
	if "apply_payload" in current_scene:
		current_scene.call_deferred("apply_payload", _next_payload)
	
	emit_signal("scene_changed", current_scene)
	_changing = false

func change_scene_with_splash(next_key: SceneRegistry.SceneKey, splash_time: float = DEFAULT_SPLASH_TIME, payload: Dictionary = {}, splash_key: SceneRegistry.SceneKey = SceneRegistry.SceneKey.SplashScreen) -> void:
	if _changing: return
	_changing = true
	_next_payload = payload

	if current_scene:
		current_scene.hide()

	await _fade_out(0.25)
	if current_scene:
		current_scene.queue_free()
	current_scene = null

	var splash_packed := SceneRegistry.SCENES.get(splash_key) as PackedScene
	var splash: Node = null
	if splash_packed:
		splash = splash_packed.instantiate()
		overlay.add_child(splash)
		await _fade_in(0.25)

	await get_tree().create_timer(splash_time).timeout

	await _fade_out(0.25)

	var new_scene = SceneRegistry.SCENES.get(next_key).instantiate()
	holder.add_child(new_scene)
	current_scene = new_scene
	if "apply_payload" in current_scene:
		current_scene.call_deferred("apply_payload", _next_payload)

	if splash:
		splash.queue_free()
		
	await _fade_in(0.25)
	emit_signal("scene_changed", current_scene)
	_changing = false

# --- Fade helpers ---
func _fade_out(dur := 0.25) -> void:
	fade_rect.visible = true
	var t := create_tween()
	t.tween_property(fade_rect, "modulate:a", 1.0, dur)
	await t.finished

func _fade_in(dur := 0.25) -> void:
	var t := create_tween()
	t.tween_property(fade_rect, "modulate:a", 0.0, dur)
	await t.finished
	fade_rect.visible = false


func goto_menu() -> void:
	await change_scene_with_splash(SceneRegistry.SceneKey.MainMenu)
