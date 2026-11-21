extends TemplateTest
## SceneManager: transitions, bus signals, reload, adoption, screens.

const HELLO_WORLD := preload("res://scenes/game/hello_world/hello_world.tscn")
# Small scenes that nothing else loads, so they always come from disk.
const LOAD_TARGET := "res://test/fixtures/scenes/load_target.tscn"
const LOAD_TARGET_2 := "res://test/fixtures/scenes/load_target_2.tscn"


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


# --- Threaded loading (#22) ---


func after_each() -> void:
	SceneManager.loading_screen_delay = SceneManager.DEFAULT_LOADING_SCREEN_DELAY
	await super.after_each()


func test_load_enters_and_leaves_loading_state() -> void:
	var states := []
	var on_state := func(new_state, _old): states.append(new_state)
	SignalBus.game_state_changed.connect(on_state)
	assert_false(ResourceLoader.has_cached(LOAD_TARGET), "fixture not loaded yet")
	await SceneManager._change_to(LOAD_TARGET, -1, {}, false)
	SignalBus.game_state_changed.disconnect(on_state)
	assert_eq(str(SceneManager.current_scene.name), "LoadTarget")
	assert_eq(states, [GameState.State.LOADING, GameState.State.MENU])
	assert_eq(GameState.state, GameState.State.MENU)


func test_pause_is_ignored_while_loading() -> void:
	await goto(SceneRegistry.SceneKey.GAME_SCENE)  # PLAYING
	GameState.begin_loading()
	GameState.pause()
	assert_eq(GameState.state, GameState.State.LOADING)
	assert_false(get_tree().paused)
	GameState.end_loading()
	assert_eq(GameState.state, GameState.State.PLAYING)


func test_loading_screen_shows_progress_and_is_removed() -> void:
	SceneManager.loading_screen_delay = 0.0  # show for every load from disk
	var seen := [false]
	var watch := func(node: Node) -> void:
		if node is LoadingScreen:
			seen[0] = true
	SceneManager.overlay.child_entered_tree.connect(watch)
	await SceneManager._change_to(LOAD_TARGET_2, -1, {}, true)
	SceneManager.overlay.child_entered_tree.disconnect(watch)
	assert_true(seen[0], "loading screen was shown")
	assert_false(SceneManager.is_loading_screen_visible(), "and removed afterwards")
	assert_null(SceneManager.overlay.get_node_or_null("LoadingScreen"))
	assert_eq(str(SceneManager.current_scene.name), "LoadTarget2")


func test_loading_screen_progress() -> void:
	var packed := load(SceneRegistry.path_of(SceneRegistry.SceneKey.LOADING_SCREEN)) as PackedScene
	var screen: LoadingScreen = add_child_autofree(packed.instantiate())
	screen.set_progress(0.5)
	assert_almost_eq(screen.get_progress(), 0.5, 0.001)
	screen.set_progress(3.0)
	assert_almost_eq(screen.get_progress(), 1.0, 0.001, "clamped")


func test_missing_file_errors_and_keeps_scene() -> void:
	var menu := await goto(SceneRegistry.SceneKey.MAIN_MENU)
	await SceneManager._change_to("res://does/not/exist.tscn", -1, {}, false)
	assert_push_error("Scene file not found")
	assert_eq(SceneManager.current_scene, menu)
	assert_false(SceneManager.is_changing())


func test_preload_then_change() -> void:
	SceneManager.preload_scene(SceneRegistry.SceneKey.DEBUG_VIEWER)
	SceneManager.preload_scene(SceneRegistry.SceneKey.DEBUG_VIEWER)  # twice is fine
	var scene := await goto(SceneRegistry.SceneKey.DEBUG_VIEWER)
	assert_eq(SceneManager.current_key, SceneRegistry.SceneKey.DEBUG_VIEWER)
	assert_not_null(scene)
	assert_false(
		SceneManager._requested.has(SceneRegistry.path_of(SceneRegistry.SceneKey.DEBUG_VIEWER))
	)


func test_reload_keeps_current_key() -> void:
	await goto(SceneRegistry.SceneKey.GAME_SCENE)
	SceneManager.reload_current({}, false)
	await wait_for_transition()
	assert_eq(SceneManager.current_key, SceneRegistry.SceneKey.GAME_SCENE)
