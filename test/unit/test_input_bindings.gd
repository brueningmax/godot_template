extends GutTest
## InputBindings + SettingsManager "input" section: serialization, rebinding,
## swapping, reset and revert. Uses a temporary settings file.

const TEST_PATH := "user://test_input_settings.cfg"

var _orig_path: String
var _orig_values: Dictionary


func before_each() -> void:
	_orig_path = SettingsManager.settings_path
	_orig_values = SettingsManager.snapshot()
	SettingsManager.settings_path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	SettingsManager.reset_controls(false)


func after_each() -> void:
	SettingsManager.reset_controls(false)
	DirAccess.remove_absolute(TEST_PATH)
	SettingsManager.settings_path = _orig_path
	SettingsManager.restore(_orig_values)


func test_serialize_round_trip() -> void:
	for text in ["key:87", "keycode:65", "mouse:2", "joy_button:0", "joy_axis:1:-", "joy_axis:0:+"]:
		var event := InputBindings.deserialize(text)
		assert_not_null(event, text)
		assert_eq(InputBindings.serialize(event), text)
	assert_null(InputBindings.deserialize("nonsense"))
	assert_null(InputBindings.deserialize("key:x"))


func test_devices_and_names() -> void:
	assert_eq(InputBindings.device_of(_key(KEY_W)), InputBindings.Device.KEYBOARD)
	assert_eq(InputBindings.device_of(_button(JOY_BUTTON_A)), InputBindings.Device.GAMEPAD)
	assert_eq(InputBindings.display_name(_button(JOY_BUTTON_A)), "A")
	assert_eq(
		InputBindings.display_name(InputBindings.deserialize("joy_axis:1:-")), "Left stick up"
	)
	assert_eq(InputBindings.display_name(null), "—")


func test_every_rebindable_action_has_keyboard_and_gamepad_defaults() -> void:
	for action in InputBindings.REBINDABLE:
		assert_true(InputMap.has_action(action), action)
		var devices := []
		for event in InputBindings.default_events(action):
			devices.append(InputBindings.device_of(event))
		assert_has(devices, InputBindings.Device.KEYBOARD, "%s keyboard" % action)
		assert_has(devices, InputBindings.Device.GAMEPAD, "%s gamepad" % action)


func test_menus_work_with_a_controller() -> void:
	assert_true(InputMap.event_is_action(_button(JOY_BUTTON_A), "ui_accept"), "A accepts")
	assert_true(InputMap.event_is_action(_button(JOY_BUTTON_B), "ui_cancel"), "B goes back")
	assert_true(InputMap.event_is_action(_button(JOY_BUTTON_DPAD_DOWN), "ui_down"))
	assert_true(InputMap.event_is_action(_button(JOY_BUTTON_START), "pause"))
	assert_true(InputMap.event_is_action(_button(JOY_BUTTON_RIGHT_SHOULDER), "ui_tab_next"))


func test_bind_replaces_only_that_device() -> void:
	InputBindings.bind("jump", _key(KEY_J), false)
	assert_eq(InputBindings.serialize(InputBindings.event_for("jump", 0)), "key:%d" % KEY_J)
	assert_not_null(InputBindings.event_for("jump", InputBindings.Device.GAMEPAD), "pad kept")
	assert_true(InputMap.event_is_action(_key(KEY_J), "jump"))
	assert_false(InputMap.event_is_action(_key(KEY_SPACE), "jump"), "old key gone")
	assert_false(FileAccess.file_exists(TEST_PATH), "preview only")


func test_bind_swaps_with_conflicting_action() -> void:
	# "up" is W by default; give W to jump -> up gets jump's old Space.
	InputBindings.bind("jump", _key(KEY_W), false)
	assert_true(InputMap.event_is_action(_key(KEY_W), "jump"))
	assert_false(InputMap.event_is_action(_key(KEY_W), "up"))
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), "up"), "swapped")


func test_saved_bindings_load_at_start() -> void:
	InputBindings.bind("left", _key(KEY_J))  # persist
	SettingsManager.reset_controls(false)
	assert_false(InputMap.event_is_action(_key(KEY_J), "left"))
	SettingsManager.load_settings()
	SettingsManager.apply_all()
	assert_true(InputMap.event_is_action(_key(KEY_J), "left"))


func test_reset_controls_restores_project_events() -> void:
	InputBindings.bind("left", _key(KEY_J), false)
	SettingsManager.reset_controls(false)
	assert_true(InputMap.event_is_action(_key(KEY_A), "left"))
	assert_false(InputMap.event_is_action(_key(KEY_J), "left"))
	assert_false(SettingsManager.snapshot().input.has("left"))


func test_restore_removes_bindings_added_after_snapshot() -> void:
	var snap := SettingsManager.snapshot()
	InputBindings.bind("left", _key(KEY_J), false)
	SettingsManager.restore(snap)
	assert_true(InputMap.event_is_action(_key(KEY_A), "left"))
	assert_false(SettingsManager.snapshot().input.has("left"))


func test_normalize() -> void:
	var weak := InputEventJoypadMotion.new()
	weak.axis = JOY_AXIS_LEFT_X
	weak.axis_value = 0.3
	assert_null(InputBindings.normalize(weak), "small stick movement ignored")
	var strong := InputEventJoypadMotion.new()
	strong.device = 2
	strong.axis = JOY_AXIS_LEFT_X
	strong.axis_value = -0.9
	var n := InputBindings.normalize(strong) as InputEventJoypadMotion
	assert_eq(n.device, -1, "any controller")
	assert_eq(n.axis_value, -1.0)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _button(index: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	return e
