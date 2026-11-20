extends TemplateTest
## Boot flow from Main.tscn (what F5 runs).

const MAIN := preload("res://globals/sceneManager/Main.tscn")


func test_boot_with_splash() -> void:
	var main := MAIN.instantiate()
	main.splash_time = 0.2
	get_tree().root.add_child(main)
	await wait_process_frames(3)
	assert_false(is_instance_valid(main) and main.is_inside_tree(), "boot node left the tree")
	await wait_for_transition()
	assert_eq(str(SceneManager.current_scene.name), "MainMenu")


func test_boot_without_splash() -> void:
	var main := MAIN.instantiate()
	main.show_splash = false
	get_tree().root.add_child(main)
	await wait_for_transition()
	await wait_process_frames(2)
	assert_eq(str(SceneManager.current_scene.name), "MainMenu")
	assert_null(SceneManager.overlay.get_node_or_null("SplashScreen"))


func test_start_scene_is_configurable() -> void:
	var main := MAIN.instantiate()
	main.show_splash = false
	main.start_scene = SceneRegistry.SceneKey.GAME_SCENE
	get_tree().root.add_child(main)
	await wait_for_transition()
	await wait_process_frames(2)
	assert_eq(str(SceneManager.current_scene.name), "HelloWorld")
