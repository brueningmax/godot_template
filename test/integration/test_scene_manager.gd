extends TemplateTest
## SceneManager: transitions, bus signals, reload, adoption, screens.

const HELLO_WORLD := preload("res://scenes/game/hello_world/hello_world.tscn")


func test_change_scene_shows_scene_and_sets_key() -> void:
	var scene := await goto(SceneRegistry.SceneKey.MAIN_MENU)
	assert_eq(str(scene.name), "MainMenu")
	assert_eq(SceneManager.current_key, SceneRegistry.SceneKey.MAIN_MENU)
	assert_eq(scene.get_parent().name, &"SceneHolder")


func test_bus_signals_in_order() -> void:
	var got := []
	var on_start := func(k): got.append(["started", k])
	var on_finish := func(n): got.append(["finished", str(n.name)])
	SignalBus.scene_change_started.connect(on_start)
	SignalBus.scene_change_finished.connect(on_finish)
	await goto(SceneRegistry.SceneKey.MAIN_MENU)
	await goto(SceneRegistry.SceneKey.GAME_SCENE, {}, true)
	SignalBus.scene_change_started.disconnect(on_start)
	SignalBus.scene_change_finished.disconnect(on_finish)
	assert_eq(
		got,
		[
			["started", SceneRegistry.SceneKey.MAIN_MENU],
			["finished", "MainMenu"],
			["started", SceneRegistry.SceneKey.GAME_SCENE],
			["finished", "HelloWorld"],
		]
	)


func test_change_during_transition_is_ignored() -> void:
	SceneManager.change_scene(SceneRegistry.SceneKey.MAIN_MENU, {}, true)
	assert_true(SceneManager.is_changing())
	SceneManager.change_scene(SceneRegistry.SceneKey.GAME_SCENE)
	await wait_for_transition()
	assert_eq(str(SceneManager.current_scene.name), "MainMenu")


func test_reload_current_keeps_node_name() -> void:
	var old := await goto(SceneRegistry.SceneKey.GAME_SCENE)
	SceneManager.reload_current()
	await wait_for_transition()
	assert_ne(SceneManager.current_scene, old, "new instance")
	assert_false(is_instance_valid(old), "old instance freed")
	assert_eq(str(SceneManager.current_scene.name), "HelloWorld", "no @HelloWorld@2")


func test_unknown_key_errors() -> void:
	SceneManager.change_scene(999)
	assert_push_error("No scene registered for key: 999")
	assert_false(SceneManager.is_changing())


func test_adopts_standalone_scene() -> void:
	SceneManager.adopt_standalone = true
	var standalone := HELLO_WORLD.instantiate()
	get_tree().root.add_child(standalone)
	get_tree().current_scene = standalone
	await goto(SceneRegistry.SceneKey.MAIN_MENU)
	SceneManager.adopt_standalone = false
	await wait_process_frames(1)  # queue_free() completes at frame end
	assert_false(is_instance_valid(standalone), "standalone scene replaced")
	assert_eq(str(SceneManager.current_scene.name), "MainMenu")


func test_screen_is_skippable() -> void:
	await goto(SceneRegistry.SceneKey.MAIN_MENU)
	var start := Time.get_ticks_msec()
	SceneManager.change_scene_with_screen(
		SceneRegistry.SceneKey.GAME_SCENE, SceneRegistry.SceneKey.SPLASH_SCREEN, 10.0
	)
	# The screen is added after the initial fade-out; skip during its fade-in.
	await wait_until(func(): return SceneManager.overlay.has_node("SplashScreen"), 2.0)
	var splash := SceneManager.overlay.get_node_or_null("SplashScreen")
	assert_not_null(splash, "splash shown")
	if splash == null:
		return
	splash.skipped.emit()
	await wait_for_transition()
	assert_eq(str(SceneManager.current_scene.name), "HelloWorld")
	assert_lt(Time.get_ticks_msec() - start, 3000, "skipped well before 10 s")
	assert_null(SceneManager.overlay.get_node_or_null("SplashScreen"), "splash removed")


func test_payload_is_applied_after_ready() -> void:
	var scene := await goto(SceneRegistry.SceneKey.MAIN_MENU, {"x": 1})
	# MainMenu has no apply_payload(); this just must not error.
	assert_not_null(scene)
