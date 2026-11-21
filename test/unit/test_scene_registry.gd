extends GutTest
## SceneRegistry: every key has a scene file that loads, and nothing is preloaded.


func test_every_key_is_registered() -> void:
	for key in SceneRegistry.SceneKey.values():
		assert_has(SceneRegistry.PATHS, key, "SceneKey.%s" % SceneRegistry.key_name(key))


func test_every_scene_instantiates() -> void:
	for key in SceneRegistry.PATHS:
		var path := SceneRegistry.path_of(key)
		assert_true(ResourceLoader.exists(path), "file for %s: %s" % [key, path])
		var packed := load(path) as PackedScene
		assert_not_null(packed, "scene for key %d" % key)
		if packed:
			var node: Node = autofree(packed.instantiate())
			assert_not_null(node, "instance for key %d" % key)


func test_registry_holds_paths_not_scenes() -> void:
	for key in SceneRegistry.PATHS:
		assert_typeof(SceneRegistry.PATHS[key], TYPE_STRING)


func test_unknown_key() -> void:
	assert_eq(SceneRegistry.path_of(999), "")
	assert_eq(SceneRegistry.key_name(999), "999")
	assert_eq(SceneRegistry.key_name(SceneRegistry.SceneKey.MAIN_MENU), "MAIN_MENU")
