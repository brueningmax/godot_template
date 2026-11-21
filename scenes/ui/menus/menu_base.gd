class_name MenuBase
extends Control

@export var default_focus: NodePath
var _tween: Tween


func open() -> void:
	# Stop a running close() fade, or its callback would hide us again.
	if _tween and _tween.is_running():
		_tween.kill()
	visible = true
	modulate.a = 0.0
	_tween = get_tree().create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if has_method("_on_open"):
		_on_open()
	call_deferred("grab_default_focus")


func close() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = get_tree().create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	_tween.tween_callback(func(): visible = false)
	if has_method("_on_close"):
		_on_close()


## Controller / keyboard users must never end up with nothing focused (e.g.
## after a mouse click on empty space, or a submenu closing): the first
## navigation press focuses default_focus again instead of doing nothing.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or default_focus == NodePath():
		return
	var nav := (
		event.is_action_pressed("ui_up")
		or event.is_action_pressed("ui_down")
		or event.is_action_pressed("ui_left")
		or event.is_action_pressed("ui_right")
		or event.is_action_pressed("ui_accept")
	)
	if not nav:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not focus.is_visible_in_tree():
		grab_default_focus()
		get_viewport().set_input_as_handled()


func grab_default_focus() -> void:
	if default_focus == NodePath():
		return
	var target := _first_focusable(get_node_or_null(default_focus))
	if target:
		target.grab_focus()


# default_focus may point at a wrapper (e.g. UIButton) that can't take focus
# itself; use the first focusable control inside it.
func _first_focusable(node: Node) -> Control:
	if node is Control and (node as Control).focus_mode != Control.FOCUS_NONE:
		return node
	if node:
		for child in node.get_children():
			var found := _first_focusable(child)
			if found:
				return found
	return null


func _on_open() -> void:
	pass


func _on_close() -> void:
	pass
