extends Control
class_name MenuBase

@export var default_focus: NodePath
var _tween: Tween

func open() -> void:
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

func grab_default_focus() -> void:
	if default_focus != NodePath():
		var n := get_node_or_null(default_focus)
		if n and n is Control:
			(n as Control).grab_focus()

func _on_open() -> void:
	pass
	
func _on_close() -> void:
	pass
