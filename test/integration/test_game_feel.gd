extends TemplateTest
## GameFeel: hit-stop, shake (with CameraShaker and the setting), flash, punch.

var _orig_shake: float


func before_each() -> void:
	_orig_shake = float(SettingsManager.get_setting("interface", "screen_shake", 1.0))


func after_each() -> void:
	SettingsManager.set_setting("interface", "screen_shake", _orig_shake, false)
	if GameFeel.is_hit_stopped():
		GameFeel._end_hit_stop()
	Engine.time_scale = 1.0
	await super.after_each()


func _camera() -> CameraShaker:
	var camera := Camera2D.new()
	add_child_autofree(camera)
	var shaker := CameraShaker.new()
	camera.add_child(shaker)
	return shaker


func test_hit_stop_freezes_and_restores() -> void:
	GameFeel.hit_stop(0.1)
	assert_eq(Engine.time_scale, 0.0)
	assert_true(GameFeel.is_hit_stopped())
	await wait_until(func(): return not GameFeel.is_hit_stopped(), 1.0)
	assert_eq(Engine.time_scale, 1.0)


func test_hit_stop_keeps_custom_time_scale() -> void:
	Engine.time_scale = 0.5  # e.g. set with the console's timescale command
	GameFeel.hit_stop(0.05, 0.1)
	assert_almost_eq(Engine.time_scale, 0.1, 0.001)
	await wait_until(func(): return not GameFeel.is_hit_stopped(), 1.0)
	assert_almost_eq(Engine.time_scale, 0.5, 0.001)


# GUT's wait_seconds() follows Engine.time_scale, which hit-stop sets to 0.
func _wait_real(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	await wait_until(func(): return Time.get_ticks_msec() >= until, seconds + 1.0)


func test_overlapping_hit_stops_extend() -> void:
	GameFeel.hit_stop(0.05)
	await _wait_real(0.03)
	GameFeel.hit_stop(0.1)
	await _wait_real(0.05)
	assert_true(GameFeel.is_hit_stopped(), "extended by the second hit")
	await wait_until(func(): return not GameFeel.is_hit_stopped(), 1.0)
	assert_eq(Engine.time_scale, 1.0, "restored to the scale from before the first")


func test_no_hit_stop_while_paused() -> void:
	await goto(SceneRegistry.SceneKey.GAME_SCENE)
	GameState.pause(false)
	GameFeel.hit_stop(0.1)
	assert_false(GameFeel.is_hit_stopped())
	assert_eq(Engine.time_scale, 1.0)


func test_shake_moves_camera_and_settles() -> void:
	var shaker := _camera()
	GameFeel.shake(1.0)
	assert_almost_eq(shaker.trauma, 1.0, 0.001)
	await wait_seconds(0.1)
	assert_ne(shaker.current_offset(), Vector2.ZERO, "shaking")
	await wait_until(func(): return shaker.trauma == 0.0, 2.0)
	await wait_process_frames(2)
	assert_eq(shaker.current_offset(), Vector2.ZERO, "back to rest")


func test_shake_setting_scales_and_disables() -> void:
	var shaker := _camera()
	SettingsManager.set_setting("interface", "screen_shake", 0.5, false)
	GameFeel.shake(0.4)
	assert_almost_eq(shaker.trauma, 0.2, 0.01)
	shaker.trauma = 0.0
	SettingsManager.set_setting("interface", "screen_shake", 0.0, false)
	GameFeel.shake(1.0)
	assert_eq(shaker.trauma, 0.0, "0 turns shaking off")


func test_shake_continues_during_hit_stop() -> void:
	var shaker := _camera()
	GameFeel.shake(1.0)
	GameFeel.hit_stop(0.2)
	await _wait_real(0.1)
	assert_lt(shaker.trauma, 1.0, "decays in real time")


func test_flash_and_punch_return_to_normal() -> void:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	await GameFeel.flash(sprite, Color(3, 3, 3), 0.05).finished
	assert_eq(sprite.modulate, Color.WHITE)
	GameFeel.punch(sprite, 0.3, 0.05)
	assert_almost_eq(sprite.scale.x, 1.3, 0.001)
	await wait_seconds(0.1)
	assert_almost_eq(sprite.scale.x, 1.0, 0.001)


func test_hello_world_has_a_shaking_camera() -> void:
	var scene := await goto(SceneRegistry.SceneKey.GAME_SCENE)
	var camera := scene.get_node("Camera") as Camera2D
	assert_not_null(camera)
	assert_true(camera.get_child(0) is CameraShaker)
	scene._roll()
	assert_gt((camera.get_child(0) as CameraShaker).trauma, 0.0)


func test_debug_commands() -> void:
	_camera()
	assert_string_contains(Debug.execute("shake 0.3"), "on 1 camera")
	assert_string_contains(Debug.execute("hitstop 0.01"), "hit-stop")
