extends TemplateTest
## Settings menu: preview, revert, apply, from main menu and pause menu.

const TEST_PATH := "user://test_settings.cfg"

var _orig_path: String
var _orig_values: Dictionary


func before_each() -> void:
	_orig_path = SettingsManager.settings_path
	_orig_values = SettingsManager.snapshot()
	SettingsManager.settings_path = TEST_PATH
	SettingsManager.set_setting("audio", "music_volume", 0.7)  # saved start value
	var menu := await goto(SceneRegistry.SceneKey.MAIN_MENU)
	menu._on_options_pressed()
	await wait_process_frames(2)


func after_each() -> void:
	await super.after_each()
	SettingsManager.reset_controls(false)
	DirAccess.remove_absolute(TEST_PATH)
	SettingsManager.settings_path = _orig_path
	SettingsManager.restore(_orig_values)


func test_options_opens_settings_over_main_menu() -> void:
	assert_true(_menu().visible)
	assert_eq(GameState.state, GameState.State.MENU)
	assert_almost_eq(_slider("music_volume").value, 0.7, 0.001, "shows current value")
	assert_eq(_menu().get_viewport().gui_get_focus_owner(), _slider("master_volume"))


func test_slider_previews_without_saving() -> void:
	_slider("music_volume").value = 0.25
	assert_almost_eq(_music_db(), linear_to_db(0.25), 0.001, "bus changed now")
	assert_almost_eq(_file_value(), 0.7, 0.001, "file unchanged")


func test_esc_reverts() -> void:
	_slider("music_volume").value = 0.25
	await press("ui_cancel")
	await wait_seconds(0.3)
	assert_almost_eq(SettingsManager.get_setting("audio", "music_volume"), 0.7, 0.001)
	assert_almost_eq(_music_db(), linear_to_db(0.7), 0.001)
	assert_false(_menu().visible)
	assert_almost_eq(_file_value(), 0.7, 0.001)


func test_apply_saves() -> void:
	_slider("music_volume").value = 0.3
	_menu().btn_apply.pressed.emit()
	await wait_seconds(0.3)
	assert_almost_eq(_file_value(), 0.3, 0.001)
	assert_false(_menu().visible)


func test_back_from_pause_menu_reverts_and_stays_paused() -> void:
	await press("ui_cancel")
	SceneManager.current_scene._on_play_pressed()
	await wait_for_transition()
	await press("pause")
	overlay_menu("PauseMenu").settings_pressed.emit()
	await wait_process_frames(2)
	_slider("music_volume").value = 0.9
	_menu().btn_back.pressed.emit()
	await wait_seconds(0.3)
	assert_almost_eq(SettingsManager.get_setting("audio", "music_volume"), 0.7, 0.001)
	assert_true(get_tree().paused)
	assert_true(overlay_menu("PauseMenu").visible)


func _menu() -> SettingsMenu:
	return overlay_menu("SettingsMenu") as SettingsMenu


func _slider(key: String) -> HSlider:
	return _menu()._controls["audio/" + key]


func _music_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))


func _file_value() -> float:
	var cfg := ConfigFile.new()
	cfg.load(TEST_PATH)
	return cfg.get_value("audio", "music_volume", -1.0)


# --- Tabs and option rows (#17) ---


func test_rows_are_grouped_in_tabs() -> void:
	var titles := []
	for i in _menu().tabs.get_tab_count():
		titles.append(_menu().tabs.get_tab_title(i))
	assert_eq(titles, ["Audio", "Display", "Interface", "Controls"])
	for row in SettingsMenu.ROWS:
		assert_has(_menu()._controls, "%s/%s" % [row.section, row.key])


func test_option_row_previews_and_reverts() -> void:
	var option: OptionButton = _menu()._controls["display/max_fps"]
	assert_eq(option.get_item_text(option.selected), "Unlimited")
	option.select(2)
	option.item_selected.emit(2)
	assert_eq(SettingsManager.get_setting("display", "max_fps"), 60)
	assert_eq(Engine.max_fps, 60)
	await press("ui_cancel")
	await wait_seconds(0.3)
	assert_eq(SettingsManager.get_setting("display", "max_fps"), 0)
	assert_eq(Engine.max_fps, 0)


func test_unknown_value_is_still_shown() -> void:
	SettingsManager.set_setting("display", "resolution", Vector2i(1000, 500), false)
	_menu()._on_open()
	var option: OptionButton = _menu()._controls["display/resolution"]
	assert_eq(option.get_item_text(option.selected), str(Vector2i(1000, 500)))


func test_ui_scale_slider_uses_its_range() -> void:
	var slider: HSlider = _menu()._controls["interface/ui_scale"]
	assert_almost_eq(slider.min_value, 0.75, 0.001)
	assert_almost_eq(slider.max_value, 2.0, 0.001)
	slider.value = 1.25
	assert_almost_eq(get_tree().root.content_scale_factor, 1.25, 0.001)
	var readout := slider.get_parent().get_child(slider.get_index() + 1) as Label
	assert_eq(readout.text, "1.25x")


# --- Controls and controller navigation (#16) ---


func test_rebind_from_menu_previews_and_esc_reverts() -> void:
	var button := _rebind("jump", InputBindings.Device.KEYBOARD)
	button.start_listening()
	await wait_process_frames(2)
	await _send_key(KEY_J)
	assert_false(button.is_listening())
	assert_eq(button.text, "J")
	assert_true(InputMap.event_is_action(_key(KEY_J), "jump"))
	await press("ui_cancel")  # Back: revert
	await wait_seconds(0.3)
	assert_false(InputMap.event_is_action(_key(KEY_J), "jump"))
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), "jump"))


func test_escape_cancels_listening_without_closing_menu() -> void:
	var button := _rebind("jump", InputBindings.Device.KEYBOARD)
	button.start_listening()
	await wait_process_frames(2)
	await _send_key(KEY_ESCAPE)
	assert_false(button.is_listening())
	assert_true(_menu().visible, "menu still open")
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), "jump"))


func test_gamepad_rebind() -> void:
	var button := _rebind("jump", InputBindings.Device.GAMEPAD)
	button.start_listening()
	await wait_process_frames(2)
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_X
	event.pressed = true
	Input.parse_input_event(event)
	await wait_process_frames(2)
	assert_eq(button.text, "X")
	SettingsManager.reset_controls(false)


func test_reset_controls_button() -> void:
	InputBindings.bind("jump", _key(KEY_J), false)
	var reset: Button = _menu().tabs.find_child("ResetControls", true, false)
	reset.pressed.emit()
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), "jump"))
	assert_eq(_rebind("jump", InputBindings.Device.KEYBOARD).text, "Space")


func test_shoulder_buttons_switch_tabs_and_move_focus() -> void:
	assert_eq(_menu().tabs.current_tab, 0)
	await press("ui_tab_next")
	assert_eq(_menu().tabs.current_tab, 1)
	var focus := _menu().get_viewport().gui_get_focus_owner()
	assert_true(_menu().tabs.get_current_tab_control().is_ancestor_of(focus), "focus in new tab")
	await press("ui_tab_previous")
	await press("ui_tab_previous")
	assert_eq(_menu().tabs.current_tab, _menu().tabs.get_tab_count() - 1, "wraps around")


func test_focus_returns_to_main_menu_after_back() -> void:
	await press("ui_cancel")
	await wait_seconds(0.3)
	var focus := get_viewport().gui_get_focus_owner()
	assert_not_null(focus)
	if focus:
		assert_true(SceneManager.current_scene.btn_play.is_ancestor_of(focus), "Play focused")


func test_lost_focus_is_recovered_by_navigation() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()
	await press("ui_down")
	assert_not_null(get_viewport().gui_get_focus_owner())


func _rebind(action: String, device: int) -> RebindButton:
	for button in _menu().tabs.find_children("*", "RebindButton", true, false):
		if button.action == action and button.device == device:
			return button
	return null


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _send_key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await wait_process_frames(2)
