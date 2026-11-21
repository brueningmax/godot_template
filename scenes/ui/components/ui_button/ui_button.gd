class_name UIButton
extends Control

signal pressed
signal button_down
signal button_up

@export var hover_offset := -4.0
@export var anim_duration := 0.12

@export var text: String:
	set(value):
		$Button.text = value
	get:
		return $Button.text

var base_pos := Vector2.ZERO

@onready var btn: Button = $Button


func _ready() -> void:
	base_pos = btn.position

	btn.mouse_entered.connect(_on_hover)
	btn.mouse_exited.connect(_on_unhover)
	btn.focus_entered.connect(_on_focus)
	btn.focus_exited.connect(_on_unhover)
	btn.pressed.connect(_on_pressed)
	btn.button_down.connect(_on_button_down)
	btn.button_up.connect(_on_button_up)


# Focus by keyboard/controller sounds like hover; automatic focus (a menu
# opening, MenuBase.grab_default_focus()) only shows the lift.
func _on_focus() -> void:
	if btn.has_meta(&"silent_focus"):
		_lift()
	else:
		_on_hover()


func _on_hover() -> void:
	Audio.play(&"ui.hover")
	_lift()


func _lift() -> void:
	(
		create_tween()
		. tween_property(btn, "position:y", base_pos.y + hover_offset, anim_duration)
		. set_trans(Tween.TRANS_CUBIC)
	)


func _on_unhover() -> void:
	create_tween().tween_property(btn, "position:y", base_pos.y, anim_duration).set_trans(
		Tween.TRANS_CUBIC
	)


func _on_pressed() -> void:
	Audio.play(&"ui.click")
	var t = create_tween()
	t.tween_property(btn, "position:y", base_pos.y + 2, 0.06)
	t.tween_property(btn, "position:y", base_pos.y + hover_offset, 0.08)
	pressed.emit()


func _on_button_down() -> void:
	button_down.emit()


func _on_button_up() -> void:
	button_up.emit()
