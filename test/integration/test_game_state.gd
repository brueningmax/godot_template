extends TemplateTest
## GameState: pause, overlay menus, back navigation, restart, quit.


func before_each() -> void:
	var menu := await goto(SceneRegistry.SceneKey.MAIN_MENU)
	menu._on_play_pressed()
	await wait_for_transition()


func test_gameplay_scene_declares_playing() -> void:
	assert_eq(GameState.state, GameState.State.PLAYING)
	assert_false(get_tree().paused)


func test_menu_scene_declares_menu_and_ignores_pause() -> void:
	await goto(SceneRegistry.SceneKey.MAIN_MENU)
	assert_eq(GameState.state, GameState.State.MENU)
	await press("pause")
	assert_false(get_tree().paused)


func test_pause_and_resume() -> void:
	watch_signals(SignalBus)
	await press("pause")
	assert_eq(GameState.state, GameState.State.PAUSED)
	assert_true(get_tree().paused)
	assert_true(overlay_menu("PauseMenu").visible, "pause menu shown")
	assert_true(GameState.get_node("MenuLayer/Dimmer").visible, "dimmer shown")
	await press("pause")
	assert_eq(GameState.state, GameState.State.PLAYING)
	assert_false(get_tree().paused)
	assert_false(GameState.get_node("MenuLayer/Dimmer").visible)
	assert_signal_emit_count(SignalBus, "pause_toggled", 2)


func test_ui_cancel_does_not_pause() -> void:
	await press("ui_cancel")
	assert_eq(GameState.state, GameState.State.PLAYING)


func test_back_from_settings_returns_to_pause_menu() -> void:
	await press("pause")
	overlay_menu("PauseMenu").settings_pressed.emit()
	await wait_process_frames(2)
	assert_true(overlay_menu("SettingsMenu").visible)
	await wait_seconds(0.3)
	assert_false(overlay_menu("PauseMenu").visible, "pause menu hidden under settings")
	await press("ui_cancel")
	await wait_seconds(0.3)
	assert_true(overlay_menu("PauseMenu").visible)
	assert_false(overlay_menu("SettingsMenu").visible)
	assert_true(get_tree().paused, "still paused")


func test_rapid_toggle_keeps_menu_visible() -> void:
	await press("pause")
	await press("pause")
	await press("pause")
	await wait_seconds(0.4)
	assert_true(get_tree().paused)
	assert_true(overlay_menu("PauseMenu").visible)


func test_restart_reloads_scene() -> void:
	var old := SceneManager.current_scene
	await press("pause")
	overlay_menu("PauseMenu").restart_pressed.emit()
	await wait_for_transition()
	assert_ne(SceneManager.current_scene, old)
	assert_eq(GameState.state, GameState.State.PLAYING)
	assert_false(get_tree().paused)


func test_quit_returns_to_menu_unpaused() -> void:
	await press("pause")
	overlay_menu("PauseMenu").quit_pressed.emit()
	await wait_for_transition()
	assert_eq(str(SceneManager.current_scene.name), "MainMenu")
	assert_eq(GameState.state, GameState.State.MENU)
	assert_false(get_tree().paused)
	assert_false(overlay_menu("PauseMenu").visible)


func test_pause_ignored_during_transition() -> void:
	SceneManager.change_scene(SceneRegistry.SceneKey.MAIN_MENU, {}, true)
	await press("pause")
	assert_false(get_tree().paused)


func test_gameplay_mouse_mode_is_remembered() -> void:
	GameState.enter_gameplay(Input.MOUSE_MODE_CONFINED)
	await press("pause")
	await press("pause")
	assert_eq(GameState._gameplay_mouse_mode, Input.MOUSE_MODE_CONFINED)
