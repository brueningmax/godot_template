extends Node
## Autoload "Toasts": short notifications in a screen corner ("Game saved",
## "Achievement unlocked"). They stack, fade out on their own, never take
## input and keep working while the game is paused.
##
##   Toasts.show("Game saved")
##   Toasts.show("Couldn't save", Toasts.Kind.ERROR, 4.0)
##
## Text is translated like any label: pass the English text (a msgid). For
## text with values, translate first: Toasts.show(tr("Saved %s") % slot).

enum Kind { INFO, SUCCESS, WARNING, ERROR }

## Above menus (50) and scene fades (100), below the debug tools (120).
const LAYER := 110
const DEFAULT_DURATION := 2.5
const FADE := 0.2
const KIND_COLORS := {
	Kind.INFO: Color(0.55, 0.7, 1.0),
	Kind.SUCCESS: Color(0.45, 0.85, 0.5),
	Kind.WARNING: Color(1.0, 0.8, 0.35),
	Kind.ERROR: Color(1.0, 0.45, 0.45),
}

## Most toasts on screen at once; the oldest goes when another arrives.
var max_visible := 4

var _layer: CanvasLayer
var _box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.name = "ToastLayer"
	_layer.layer = LAYER
	add_child(_layer)
	_box = VBoxContainer.new()
	_box.name = "Toasts"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.add_theme_constant_override("separation", 8)
	_layer.add_child(_box)
	# Bottom-right, growing upwards, 16 px from the edges.
	_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.offset_right = -16
	_box.offset_bottom = -40  # leave room for the debug seed label


## Shows a toast for `duration` seconds (real time, also while paused).
## Returns its node, e.g. to close it early with dismiss().
func show(text: String, kind: Kind = Kind.INFO, duration := DEFAULT_DURATION) -> Control:
	while _box.get_child_count() >= max_visible:
		var oldest := _box.get_child(0)
		_box.remove_child(oldest)
		oldest.queue_free()
	var toast := _make_toast(text, kind)
	_box.add_child(toast)
	toast.modulate.a = 0.0
	var tween := toast.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(toast, "modulate:a", 1.0, FADE)
	tween.tween_interval(maxf(duration, 0.0))
	tween.tween_callback(dismiss.bind(toast))
	Log.debug(&"Toasts", text)
	return toast


## Fades a toast out and removes it.
func dismiss(toast: Control) -> void:
	if not is_instance_valid(toast) or toast.has_meta(&"dismissed"):
		return
	toast.set_meta(&"dismissed", true)
	var tween := toast.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(toast, "modulate:a", 0.0, FADE)
	tween.tween_callback(toast.queue_free)


## Removes every toast at once.
func clear() -> void:
	for toast in _box.get_children():
		_box.remove_child(toast)
		toast.queue_free()


## The toasts currently shown, oldest first.
func visible_toasts() -> Array[Node]:
	return _box.get_children().filter(func(t: Node): return not t.has_meta(&"dismissed"))


func _make_toast(text: String, kind: Kind) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.15, 0.95)
	style.border_color = KIND_COLORS[kind]
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 240
	panel.add_child(label)
	panel.set_meta(&"kind", kind)
	return panel
