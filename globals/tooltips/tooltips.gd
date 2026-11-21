extends Node
## Autoload "Tooltips": shows a control's tooltip_text when it gets focus from
## the keyboard or a controller. Godot's own tooltips only appear on mouse
## hover, so without this, controller players never see them.
##
## Nothing to call: set tooltip_text on a control as usual. Mouse users keep
## Godot's hover tooltip; this one hides as soon as the mouse moves.

## Above menus (50), fades (100) and toasts (110), below the debug tools (120).
const LAYER := 115
## Seconds of focus before the tooltip appears.
const DELAY := 0.4
const MAX_WIDTH := 360.0

var enabled := true

var _layer: CanvasLayer
var _panel: PanelContainer
var _label: Label
var _target: Control = null
var _last_input_was_mouse := true
var _timer: SceneTreeTimer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.name = "TooltipLayer"
	_layer.layer = LAYER
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.name = "Tooltip"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.96)
	style.border_color = Color(0.78, 0.78, 0.78, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_panel.add_child(_label)
	_layer.add_child(_panel)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_last_input_was_mouse = true
		hide_tooltip()
	elif event is InputEventKey or event is InputEventJoypadButton:
		_last_input_was_mouse = false
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_last_input_was_mouse = false


## The tooltip currently shown, or null.
func shown_for() -> Control:
	return _target if _panel.visible and _panel.modulate.a > 0.0 else null


func hide_tooltip() -> void:
	_panel.visible = false
	_target = null
	_timer = null


func _on_focus_changed(control: Control) -> void:
	hide_tooltip()
	if not enabled or _last_input_was_mouse or control == null:
		return
	if control.tooltip_text.strip_edges() == "":
		return
	_target = control
	var timer := get_tree().create_timer(DELAY, true, false, true)
	_timer = timer
	timer.timeout.connect(func(): _show_if_current(control, timer))


func _show_if_current(control: Control, timer: SceneTreeTimer) -> void:
	if timer != _timer or not is_instance_valid(control) or not control.has_focus():
		return
	if not control.is_visible_in_tree():
		return
	_label.text = control.tooltip_text  # translated by the label, like any text
	_fit_label(_label.tr(control.tooltip_text))
	# A wrapped label knows its height only after a layout pass: lay out
	# invisibly for a frame, then size, place and show.
	_panel.modulate.a = 0.0
	_panel.visible = true
	await get_tree().process_frame
	if timer != _timer:
		return  # hidden or replaced meanwhile
	_panel.reset_size()
	_panel.position = _place(control.get_global_rect(), _panel.size)
	_panel.modulate.a = 1.0


# Sizes the label for `text`: one line if it fits in MAX_WIDTH, otherwise
# wrapped at MAX_WIDTH. A wrapping label's own minimum height depends on its
# current width, so the width is set before the panel is sized.
func _fit_label(text: String) -> void:
	var font := _label.get_theme_font(&"font")
	var font_size := _label.get_theme_font_size(&"font_size")
	var one_line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := ceilf(minf(one_line, MAX_WIDTH)) + 2.0
	_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART if one_line > MAX_WIDTH else TextServer.AUTOWRAP_OFF
	)
	_label.custom_minimum_size = Vector2(width, 0)
	_panel.reset_size()


# Below the control, or above it if there's no room; kept on screen.
func _place(rect: Rect2, size: Vector2) -> Vector2:
	var screen := get_viewport().get_visible_rect().size
	var pos := Vector2(rect.position.x, rect.end.y + 6)
	if pos.y + size.y > screen.y:
		pos.y = rect.position.y - size.y - 6
	pos.x = clampf(pos.x, 4, maxf(4, screen.x - size.x - 4))
	pos.y = clampf(pos.y, 4, maxf(4, screen.y - size.y - 4))
	return pos
