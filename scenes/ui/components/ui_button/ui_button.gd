extends Control
class_name UIButton

signal pressed
signal button_down
signal button_up

@export var hover_offset := -4.0
@export var anim_duration := 0.12

@export var hover_sound: AudioStream
@export var click_sound: AudioStream


@export var text: String:
	set(value):
		$Button.text = value
	get:
		return $Button.text

@onready var btn: Button = $Button
@onready var hover_player: AudioStreamPlayer = $HoverPlayer
@onready var click_player: AudioStreamPlayer = $ClickPlayer

var base_pos := Vector2.ZERO

func _ready() -> void:
	base_pos = btn.position

	btn.mouse_entered.connect(_on_hover)
	btn.mouse_exited.connect(_on_unhover)
	btn.focus_entered.connect(_on_hover)
	btn.focus_exited.connect(_on_unhover)
	btn.pressed.connect(_on_pressed)
	btn.button_down.connect(_on_button_down)
	btn.button_up.connect(_on_button_up)


func _on_hover() -> void:
	Audio.play(&"ui.hover")
	create_tween().tween_property(
		btn, "position:y",
		base_pos.y + hover_offset,
		anim_duration
	).set_trans(Tween.TRANS_CUBIC)


func _on_unhover() -> void:
	create_tween().tween_property(
		btn, "position:y",
		base_pos.y,
		anim_duration
	).set_trans(Tween.TRANS_CUBIC)


func _on_pressed() -> void:
	Audio.play(&"ui.click")
	var t = create_tween()
	t.tween_property(btn, "position:y", base_pos.y + 2, 0.06)
	t.tween_property(btn, "position:y", base_pos.y + hover_offset, 0.08)
	emit_signal("pressed")

func _on_button_down() -> void:
	await click_player.finished
	emit_signal("button_down")

func _on_button_up() -> void:
	await click_player.finished
	emit_signal("button_up")

func _play_hover() -> void:
	if hover_sound:
		hover_player.stream = hover_sound
		hover_player.play()


func _play_click() -> void:
	if click_sound:
		click_player.stream = click_sound
		click_player.play()
