extends TemplateTest
## Debug overlay and console.

const DEBUG_SCENE := preload("res://globals/debug/debug.tscn")


func after_each() -> void:
	Debug.close_console()
	if Debug.is_overlay_visible():
		Debug.toggle_overlay()
	Debug.unregister_command("echo")
	Debug.unregister_command("gone")
	Engine.time_scale = 1.0
	Log.clear_level(&"Audio")
	await super.after_each()


func test_enabled_in_debug_builds() -> void:
	assert_true(Debug.enabled)
	assert_not_null(Debug.get_node_or_null("DebugLayer"))


func test_overlay_toggles_with_f1_action() -> void:
	await press("debug_overlay")
	assert_true(Debug.is_overlay_visible())
	var text: String = Debug._overlay_label.text
	for field in ["FPS", "draw calls", "scene", "state", "seed", "log"]:
		assert_string_contains(text, field)
	await press("debug_overlay")
	assert_false(Debug.is_overlay_visible())


func test_seed_label_shows_current_seed() -> void:
	RngManager.set_seed("abc")
	Debug._update_overlay()
	assert_eq(Debug._seed_button.text, "seed abc")


func test_console_pauses_gameplay_and_esc_closes_it() -> void:
	await goto(SceneRegistry.SceneKey.GAME_SCENE)
	assert_eq(GameState.state, GameState.State.PLAYING)
	await press("debug_console")
	assert_true(Debug.is_console_open())
	assert_true(get_tree().paused, "gameplay frozen while typing")
	assert_null(overlay_menu("PauseMenu"), "no pause menu for the console")
	await press("pause")  # Esc
	assert_false(Debug.is_console_open())
	assert_false(get_tree().paused, "resumed")
	assert_eq(GameState.state, GameState.State.PLAYING, "Esc didn't reach GameState")


func test_console_keeps_players_pause() -> void:
	await goto(SceneRegistry.SceneKey.GAME_SCENE)
	await press("pause")
	assert_true(overlay_menu("PauseMenu").visible)
	Debug.open_console()
	Debug.close_console()
	assert_true(get_tree().paused, "still paused")
	assert_eq(GameState.state, GameState.State.PAUSED)


func test_parse_args() -> void:
	assert_eq(Array(Debug.parse_args('give  "magic sword" 2')), ["give", "magic sword", "2"])
	assert_eq(Array(Debug.parse_args('say ""')), ["say", ""])
	assert_eq(Array(Debug.parse_args("   ")), [])


func test_unknown_command() -> void:
	assert_string_contains(Debug.execute("nope"), "Unknown command 'nope'")


func test_custom_command_gets_args_and_prints_result() -> void:
	Debug.register_command("echo", func(args): return "|".join(args), "Echo", "<words>")
	assert_true(Debug.has_command("ECHO"), "names are case-insensitive")
	assert_eq(Debug.execute('echo a "b c"'), "a|b c")
	assert_string_contains(Debug._log_view.get_parsed_text(), "a|b c")


func test_command_of_freed_object_is_reported() -> void:
	var owner_node := Node.new()
	Debug.register_command("gone", owner_node.get_name)
	owner_node.free()
	assert_string_contains(Debug.execute("gone"), "no longer valid")


func test_help_lists_builtins() -> void:
	var text := Debug.execute("help")
	for command in ["help", "seed", "scene", "reload", "timescale", "log", "quit"]:
		assert_string_contains(text, command)
	assert_string_contains(Debug.execute("help scene"), "<SCENE_KEY>")


func test_seed_command() -> void:
	Debug.execute("seed my run")
	assert_eq(RngManager.get_seed(), "my run")
	assert_string_contains(Debug.execute("seed"), "my run")


func test_scene_command_and_completion() -> void:
	Debug._input_line.text = "scene ma"
	Debug._complete()
	assert_eq(Debug._input_line.text, "scene MAIN_MENU ")
	Debug.execute("scene main_menu")
	await wait_for_transition()
	assert_eq(str(SceneManager.current_scene.name), "MainMenu")
	assert_string_contains(Debug.execute("scene nowhere"), "Unknown scene key")


func test_timescale_command() -> void:
	Debug.execute("timescale 0.5")
	assert_eq(Engine.time_scale, 0.5)
	assert_string_contains(Debug.execute("timescale fast"), "usage")


func test_log_command() -> void:
	Debug.execute("log Audio warn")
	assert_eq(Log.get_level(&"Audio"), Log.Level.WARN)
	assert_string_contains(Debug.execute("log Audio loud"), "usage")


func test_log_view_shows_new_messages() -> void:
	Log.info(&"Test", "visible in console")
	assert_string_contains(Debug._log_view.get_parsed_text(), "visible in console")


func test_history() -> void:
	Debug._on_submitted("help")
	Debug._on_submitted("seed")
	Debug._browse_history(-1)
	assert_eq(Debug._input_line.text, "seed")
	Debug._browse_history(-1)
	assert_eq(Debug._input_line.text, "help")
	Debug._browse_history(1)
	Debug._browse_history(1)
	assert_eq(Debug._input_line.text, "", "past the newest entry: empty line")


func test_disabled_instance_has_no_ui_and_ignores_commands() -> void:
	var off: Node = DEBUG_SCENE.instantiate()
	off.enabled_in_debug = false
	add_child_autofree(off)
	assert_false(off.enabled)
	assert_null(off.get_node_or_null("DebugLayer"))
	off.register_command("x", func(_a): return "y")
	assert_false(off.has_command("x"))
	assert_eq(off.execute("x"), "")
	assert_false(off.is_console_open())


func test_layout_anchors() -> void:
	# Regression: anchors without offsets left the console a 60 px sliver.
	# (Headless windows are 64x64 px, so check anchors/offsets, not pixel sizes.)
	var console: Control = Debug._console
	assert_eq(
		[console.anchor_left, console.anchor_right], [0.0, 1.0], "console anchored full width"
	)
	assert_eq([console.offset_left, console.offset_right], [0.0, 0.0], "no width-limiting offsets")
	assert_eq(console.anchor_top, 0.0)
	assert_almost_eq(console.anchor_bottom, 0.45, 0.001, "top 45 %")
	assert_eq(console.offset_bottom, 0.0)
	var overlay: Control = Debug._overlay_panel
	assert_eq([overlay.anchor_left, overlay.anchor_right], [1.0, 1.0], "overlay anchored right")
	assert_lt(overlay.offset_right, 0.0, "overlay inset from the right edge")
	assert_eq(overlay.grow_horizontal, Control.GROW_DIRECTION_BEGIN, "grows leftwards")
	var layer := Debug.get_node("DebugLayer")
	assert_eq(layer.get_child(-1), Debug._seed_button, "seed drawn last")
	assert_gt(overlay.get_index(), console.get_index(), "overlay drawn above console")
