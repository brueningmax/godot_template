extends Node2D
## Minimal example game. Replace it with your own: register your scene under
## SceneRegistry.SceneKey.GAME_SCENE, or point main.tscn's start_scene at it.
##
## It shows the template's systems in use:
## - Input actions from project.godot (left/right/up/down, jump, pause)
## - RngManager: a named stream, so a typed seed reproduces the same rolls
## - Audio: footsteps by registry ID
## - GameState: declares itself gameplay, so Esc opens the pause menu
##   (also when run on its own with F6)
## - GameFeel: a roll shakes the camera (CameraShaker) and pops the player

const SPEED := 300.0
const STEP_INTERVAL := 0.35

var _step_timer := 0.0
var _last_roll := "-"

@onready var player: Sprite2D = $Player
@onready var info: Label = %Info


func _ready() -> void:
	info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # already translated
	GameState.enter_gameplay(Input.MOUSE_MODE_VISIBLE)
	player.position = get_viewport_rect().size / 2.0
	_add_camera()
	_update_info()


func _process(delta: float) -> void:
	var dir := Input.get_vector("left", "right", "up", "down")
	if dir == Vector2.ZERO:
		_step_timer = 0.0
		return

	var bounds := get_viewport_rect()
	player.position = (player.position + dir * SPEED * delta).clamp(bounds.position, bounds.end)

	_step_timer -= delta
	if _step_timer <= 0.0:
		Audio.play(&"move.step")
		_step_timer = STEP_INTERVAL


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		_roll()


func _roll() -> void:
	# Same seed -> same sequence of rolls, because the "dice" stream is
	# derived from the run seed and nothing else draws from it.
	var roll := RngManager.get_stream("dice").rand_int(1, 6)
	_last_roll = str(roll)
	Audio.play(&"ui.click")
	GameFeel.shake(0.15 + roll * 0.07)  # a six shakes harder than a one
	GameFeel.flash(player)
	GameFeel.punch(player, 0.3)
	_update_info()


# A camera centred on the screen, so the view looks the same as without one,
# with a CameraShaker child so GameFeel.shake() has something to move.
func _add_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = get_viewport_rect().size / 2.0
	camera.add_child(CameraShaker.new())
	add_child(camera)
	camera.make_current()


func _notification(what: int) -> void:
	# Text built with tr() doesn't update by itself when the language changes.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_info()


func _update_info() -> void:
	info.text = (
		tr("Hello, world!\nSeed: %s\nLast roll: %s\n\nMove: WASD   Roll: Space   Pause: Esc")
		% [RngManager.get_seed(), _last_roll]
	)
