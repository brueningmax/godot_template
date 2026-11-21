class_name CameraShaker
extends Node
## Trauma-based screen shake for its parent Camera2D or Camera3D. Add it as a
## child of a camera; GameFeel.shake() then reaches it, or call add_trauma().
##
## Trauma (0..1) adds up from hits and decays over time; the shake strength is
## trauma², so small hits barely move the camera and big ones clearly do. The
## motion comes from smooth noise, not random jumps.
##
## It shakes the camera's offset (2D: offset and rotation, 3D: h/v_offset and
## a small roll), so it works with cameras that follow a target. It freezes
## while the game is paused and keeps shaking during GameFeel.hit_stop().

const GROUP := &"camera_shakers"

## Largest offset at full trauma, in pixels (2D) or meters (3D).
@export var max_offset := Vector2(16, 12)
## Largest roll at full trauma, in degrees.
@export var max_roll_degrees := 2.0
## Trauma lost per second.
@export var decay := 1.6
## How fast the shake moves (noise speed).
@export var frequency := 18.0

var trauma := 0.0

var _camera: Node = null
var _noise := FastNoiseLite.new()
var _time := 0.0
var _base_rotation := 0.0
var _last_usec := 0


func _ready() -> void:
	add_to_group(GROUP)
	_camera = get_parent()
	if not (_camera is Camera2D or _camera is Camera3D):
		Log.warn(&"GameFeel", "CameraShaker must be a child of a Camera2D or Camera3D")
		_camera = null
	_noise.seed = randi()
	_noise.frequency = 1.0
	_last_usec = Time.get_ticks_usec()


## Adds trauma (clamped to 1). GameFeel.shake() scales it by the player's
## screen shake setting first; calling this directly doesn't.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(_delta: float) -> void:
	# Real time, so the shake continues during hit-stop (time_scale ~0).
	var now := Time.get_ticks_usec()
	var real_delta := minf((now - _last_usec) / 1_000_000.0, 0.1)
	_last_usec = now
	if _camera == null:
		return
	if trauma <= 0.0:
		_apply(Vector2.ZERO, 0.0)
		return
	trauma = maxf(trauma - decay * real_delta, 0.0)
	_time += real_delta * frequency
	var strength := trauma * trauma
	var offset := Vector2(
		max_offset.x * strength * _noise.get_noise_2d(_time, 0.0),
		max_offset.y * strength * _noise.get_noise_2d(0.0, _time)
	)
	var roll := deg_to_rad(max_roll_degrees) * strength * _noise.get_noise_2d(_time, _time)
	_apply(offset, roll)


## The offset applied right now (for tests and debugging).
func current_offset() -> Vector2:
	if _camera is Camera2D:
		return (_camera as Camera2D).offset
	if _camera is Camera3D:
		return Vector2((_camera as Camera3D).h_offset, (_camera as Camera3D).v_offset)
	return Vector2.ZERO


func _apply(offset: Vector2, roll: float) -> void:
	if _camera is Camera2D:
		var cam := _camera as Camera2D
		cam.offset = offset
		cam.rotation = _base_rotation + roll
	elif _camera is Camera3D:
		var cam3 := _camera as Camera3D
		cam3.h_offset = offset.x
		cam3.v_offset = offset.y
