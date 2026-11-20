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
