extends GutTest
## SceneRegistry: every key has a scene that loads.


func test_every_key_is_registered() -> void:
	for key in SceneRegistry.SceneKey.values():
		assert_has(SceneRegistry.SCENES, key, "SceneKey.%s" % SceneRegistry.SceneKey.keys()[key])


func test_every_scene_instantiates() -> void:
	for key in SceneRegistry.SCENES:
		var packed: PackedScene = SceneRegistry.SCENES[key]
		assert_not_null(packed, "scene for key %d" % key)
		if packed:
			var node: Node = autofree(packed.instantiate())
			assert_not_null(node, "instance for key %d" % key)
