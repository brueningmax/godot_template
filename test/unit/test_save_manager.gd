extends GutTest
## SaveManager: round trips, slots, atomic writes, migrations, persist group.
## Uses a temporary folder; the player's real saves are untouched.

const TEST_DIR := "user://test_saves"
const V1_FIXTURE := "res://test/fixtures/saves/v1_slot.save"


class Persisted:
	extends Node
	var persist_id := ""
	var hp := 10

	func save_state() -> Dictionary:
		return {"hp": hp}

	func load_state(state: Dictionary) -> void:
		hp = state.hp


var _orig_dir: String
var _orig_version: int
var _orig_playtime: float


func before_each() -> void:
	_orig_dir = SaveManager.saves_dir
	_orig_version = SaveManager.current_version
	_orig_playtime = SaveManager.playtime
	SaveManager.saves_dir = TEST_DIR
	_clear_dir()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func after_each() -> void:
	_clear_dir()
	SaveManager.saves_dir = _orig_dir
	SaveManager.current_version = _orig_version
	SaveManager.playtime = _orig_playtime
	SaveManager._migrations.clear()
	SaveManager._register_migrations()


func test_round_trip_keeps_types() -> void:
	var data := {"gold": 10, "ratio": 0.5, "pos": Vector2(1, 2), "tags": [&"a", "b"], "n": {"x": 1}}
	assert_eq(SaveManager.save_game("slot_1", data), OK)
	var back := SaveManager.load_game("slot_1")
	assert_eq(back, data)
	assert_typeof(back.gold, TYPE_INT, "ints stay ints")
	assert_typeof(back.pos, TYPE_VECTOR2)


func test_list_has_metadata_newest_first() -> void:
	SaveManager.playtime = 42.0
	SaveManager.save_game("a", {}, {"chapter": 1})
	_write_file("b", 1, {"saved_at": 100}, {})  # older
	var saves := SaveManager.list_saves()
	assert_eq(saves.size(), 2)
	assert_eq(saves[0].slot, "a")
	assert_eq(saves[0].chapter, 1)
	assert_almost_eq(float(saves[0].playtime), 42.0, 0.001)
	assert_eq(saves[0].version, SaveManager.SAVE_VERSION)
	assert_gt(int(saves[0].saved_at), 100)
	assert_eq(saves[1].slot, "b")


func test_load_restores_playtime() -> void:
	SaveManager.playtime = 99.0
	SaveManager.save_game("p", {})
	SaveManager.playtime = 0.0
	SaveManager.load_game("p")
	assert_almost_eq(SaveManager.playtime, 99.0, 0.001)


func test_delete_and_has() -> void:
	SaveManager.save_game("d", {"x": 1})
	assert_true(SaveManager.has_save("d"))
	assert_eq(SaveManager.delete_save("d"), OK)
	assert_false(SaveManager.has_save("d"))
	assert_eq(SaveManager.delete_save("d"), ERR_FILE_NOT_FOUND)


func test_write_is_atomic() -> void:
	SaveManager.save_game("s", {"v": 1})
	SaveManager.save_game("s", {"v": 2})
	assert_false(FileAccess.file_exists(TEST_DIR.path_join("s.save.tmp")), "temp file renamed")
	# A leftover temp file from a crash is ignored; the last complete save loads.
	var f := FileAccess.open(TEST_DIR.path_join("s.save.tmp"), FileAccess.WRITE)
	f.store_string("{ half written")
	f.close()
	assert_eq(SaveManager.load_game("s"), {"v": 2})
	assert_eq(SaveManager.list_saves().size(), 1)


func test_damaged_file_errors() -> void:
	var f := FileAccess.open(TEST_DIR.path_join("bad.save"), FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	assert_eq(SaveManager.load_game("bad"), {})
	assert_push_error("Save file is damaged")


func test_invalid_slot_name() -> void:
	assert_eq(SaveManager.save_game("../evil", {}), ERR_INVALID_PARAMETER)
	assert_push_error("Invalid slot name")


func test_migrates_v1_fixture_step_by_step() -> void:
	DirAccess.copy_absolute(V1_FIXTURE, TEST_DIR.path_join("old.save"))
	SaveManager.current_version = 3
	SaveManager.register_migration(
		1,
		func(data: Dictionary) -> Dictionary:
			data["gold"] = data.coins
			data.erase("coins")
			return data
	)
	SaveManager.register_migration(
		2,
		func(data: Dictionary) -> Dictionary:
			data["gold"] *= 10
			return data
	)
	var data := SaveManager.load_game("old")
	assert_eq(data, {"gold": 70, "pos": Vector2(3, 4)})
	assert_eq(SaveManager.get_save_info("old").chapter, 1)


func test_missing_migration_errors() -> void:
	DirAccess.copy_absolute(V1_FIXTURE, TEST_DIR.path_join("old.save"))
	SaveManager.current_version = 2
	assert_eq(SaveManager.load_game("old"), {})
	assert_push_error("No migration from save version 1")


func test_newer_save_is_refused() -> void:
	_write_file("future", SaveManager.current_version + 1, {}, {"x": 1})
	assert_eq(SaveManager.load_game("future"), {})
	assert_push_error("newer than this game")


func test_persist_group_round_trip() -> void:
	var a: Persisted = add_child_autofree(Persisted.new())
	a.persist_id = "player"
	a.add_to_group(SaveManager.PERSIST_GROUP)
	var b: Persisted = add_child_autofree(Persisted.new())
	b.add_to_group(SaveManager.PERSIST_GROUP)
	a.hp = 3
	b.hp = 4
	assert_eq(SaveManager.save_persist("p"), OK)
	a.hp = 0
	b.hp = 0
	assert_true(SaveManager.load_persist("p"))
	assert_eq(a.hp, 3)
	assert_eq(b.hp, 4)
	assert_eq(SaveManager.persist_key(a), "player")
	assert_eq(SaveManager.persist_key(b), str(b.get_path()), "path when no persist_id")


func test_autosave_writes_autosave_slot() -> void:
	assert_eq(SaveManager.autosave(), OK)
	assert_true(SaveManager.has_save(SaveManager.AUTOSAVE_SLOT))
	assert_true(SaveManager.get_save_info(SaveManager.AUTOSAVE_SLOT).autosave)


func test_signals() -> void:
	watch_signals(SignalBus)
	SaveManager.save_game("sig", {})
	SaveManager.load_game("sig")
	assert_signal_emitted_with_parameters(SignalBus, "game_saved", ["sig"])
	assert_signal_emitted_with_parameters(SignalBus, "game_loaded", ["sig"])


# --- Helpers ---


func _write_file(slot: String, version: int, meta: Dictionary, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var env := {"version": version, "meta": JSON.from_native(meta), "data": JSON.from_native(data)}
	var f := FileAccess.open(TEST_DIR.path_join(slot + ".save"), FileAccess.WRITE)
	f.store_string(JSON.stringify(env))
	f.close()


func _clear_dir() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(TEST_DIR)
