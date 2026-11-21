extends Node
## Game-state saves in slots under user://saves/, separate from the player's
## preferences (SettingsManager).
##
## Two ways to use it:
##   SaveManager.save_game("slot_1", {"gold": 10, "level": 3})   # explicit
##   var data := SaveManager.load_game("slot_1")
## or let nodes in the "persist" group save themselves:
##   SaveManager.save_persist("slot_1")    # calls save_state() on each node
##   SaveManager.load_persist("slot_1")    # calls load_state(state) on each node
##
## Every file has a version. Older files are upgraded step by step by the
## functions registered in _register_migrations() (v1 -> v2 -> ...).

## Bump when the save format changes, and add a migration from the old version.
const SAVE_VERSION := 1
## Group whose nodes save_persist() / load_persist() handle.
const PERSIST_GROUP := &"persist"
const AUTOSAVE_SLOT := "autosave"
const EXTENSION := ".save"

## Where saves go. Tests point this at a temporary folder.
var saves_dir := "user://saves"
## Version written into new saves; files are migrated up to it on load.
var current_version: int = SAVE_VERSION
## Seconds of play (GameState PLAYING) in this run, restored from a save's
## metadata on load. Stored in every save.
var playtime: float = 0.0
## Seconds between autosaves while playing; 0 turns the timer off.
var autosave_interval: float = 0.0

# from_version -> Callable(data: Dictionary) -> Dictionary (data at from_version + 1)
var _migrations: Dictionary[int, Callable] = {}
var _autosave_elapsed := 0.0


func _ready() -> void:
	_register_migrations()


func _process(delta: float) -> void:
	if GameState.state != GameState.State.PLAYING:
		return
	playtime += delta
	if autosave_interval > 0.0:
		_autosave_elapsed += delta
		if _autosave_elapsed >= autosave_interval:
			_autosave_elapsed = 0.0
			autosave()


# --- Migrations -----------------------------------------------------------------


## Register your game's migrations here, one per version step. Each gets the
## saved data at `from_version` and returns it upgraded by one version:
##
##   register_migration(1, func(data: Dictionary) -> Dictionary:
##       data["gold"] = data.get("coins", 0)   # v2 renamed coins to gold
##       data.erase("coins")
##       return data)
func _register_migrations() -> void:
	pass


## Adds the step that upgrades data saved at `from_version` to `from_version + 1`.
func register_migration(from_version: int, migration: Callable) -> void:
	_migrations[from_version] = migration


## Upgrades `data` from `from_version` to current_version. Returns null if a
## step is missing or the file is from a newer version (logged).
func migrate(data: Dictionary, from_version: int) -> Variant:
	if from_version > current_version:
		Log.error(
			&"Save",
			"Save is version %d, newer than this game (%d)" % [from_version, current_version]
		)
		return null
	var version := from_version
	while version < current_version:
		if not _migrations.has(version):
			Log.error(&"Save", "No migration from save version %d" % version)
			return null
		var result: Variant = _migrations[version].call(data)
		if not result is Dictionary:
			Log.error(&"Save", "Migration from version %d didn't return a Dictionary" % version)
			return null
		data = result
		Log.info(&"Save", "migrated save from version %d to %d" % [version, version + 1])
		version += 1
	return data


# --- Slots ----------------------------------------------------------------------


## Writes `data` to `slot` atomically. `meta` is extra, small information for a
## slot list (e.g. {"chapter": 2}); slot, version, saved_at and playtime are added.
func save_game(slot: String, data: Dictionary, meta: Dictionary = {}) -> Error:
	if not _is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var full_meta := meta.duplicate(true)
	full_meta["saved_at"] = int(Time.get_unix_time_from_system())
	full_meta["playtime"] = playtime
	var envelope := {
		"version": current_version,
		"meta": JSON.from_native(full_meta),
		"data": JSON.from_native(data),
	}
	var err := _write_atomic(_path(slot), JSON.stringify(envelope, "\t"))
	if err == OK:
		Log.info(&"Save", "saved slot '%s'" % slot)
		SignalBus.game_saved.emit(slot)
	return err


## The data saved in `slot`, migrated to current_version. Empty if the slot
## doesn't exist or can't be read (logged). Restores `playtime`.
func load_game(slot: String) -> Dictionary:
	var envelope := _read(slot)
	if envelope.is_empty():
		return {}
	var data: Variant = migrate(envelope.data, envelope.version)
	if data == null:
		return {}
	playtime = float(envelope.meta.get("playtime", 0.0))
	_autosave_elapsed = 0.0
	Log.info(&"Save", "loaded slot '%s'" % slot)
	SignalBus.game_loaded.emit(slot)
	return data


func has_save(slot: String) -> bool:
	return _is_valid_slot(slot) and FileAccess.file_exists(_path(slot))


func delete_save(slot: String) -> Error:
	if not has_save(slot):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(_path(slot))


## Metadata of one slot: slot, version, saved_at (unix seconds), playtime and
## whatever was passed as `meta`. Empty if the slot can't be read.
func get_save_info(slot: String) -> Dictionary:
	var envelope := _read(slot)
	if envelope.is_empty():
		return {}
	var info: Dictionary = envelope.meta
	info["slot"] = slot
	info["version"] = envelope.version
	return info


## get_save_info() of every slot, newest first.
func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(saves_dir)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(EXTENSION):
			var info := get_save_info(file.trim_suffix(EXTENSION))
			if not info.is_empty():
				result.append(info)
	result.sort_custom(func(a, b): return a.get("saved_at", 0) > b.get("saved_at", 0))
	return result


# --- "persist" group ------------------------------------------------------------


## The state of every node in the "persist" group, keyed by persist_key().
## Each node must have save_state() -> Dictionary.
func collect_persist_state() -> Dictionary:
	var state := {}
	for node in get_tree().get_nodes_in_group(PERSIST_GROUP):
		if not node.has_method("save_state"):
			Log.warn(&"Save", "%s is in group 'persist' but has no save_state()" % node.name)
			continue
		state[persist_key(node)] = node.call("save_state")
	return state


## Calls load_state(state) on each node in the "persist" group that has an
## entry in `state`. Returns how many nodes were restored.
func apply_persist_state(state: Dictionary) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(PERSIST_GROUP):
		var key := persist_key(node)
		if state.has(key) and node.has_method("load_state"):
			node.call("load_state", state[key])
			count += 1
	return count


func save_persist(slot: String, meta: Dictionary = {}) -> Error:
	return save_game(slot, {"persist": collect_persist_state()}, meta)


## Loads `slot` and hands each persist node its state. False if nothing loaded.
func load_persist(slot: String) -> bool:
	var data := load_game(slot)
	if data.is_empty():
		return false
	apply_persist_state(data.get("persist", {}))
	return true


## Saves the persist group to the autosave slot. Call it at checkpoints, or
## set autosave_interval.
func autosave() -> Error:
	return save_persist(AUTOSAVE_SLOT, {"autosave": true})


## A node's key in persist state: its `persist_id` property if it has one
## (use that for nodes whose path may change), else its path in the tree.
func persist_key(node: Node) -> String:
	var id: Variant = node.get("persist_id")
	if id != null and str(id) != "":
		return str(id)
	return str(node.get_path())


# --- Files ----------------------------------------------------------------------


func _path(slot: String) -> String:
	return saves_dir.path_join(slot + EXTENSION)


func _is_valid_slot(slot: String) -> bool:
	var regex := RegEx.create_from_string("^[A-Za-z0-9_-]+$")
	if regex.search(slot) == null:
		Log.error(&"Save", "Invalid slot name '%s' (use letters, digits, _ and -)" % slot)
		return false
	return true


# Reads and checks a slot's envelope: {version: int, meta: Dictionary, data: Dictionary}.
func _read(slot: String) -> Dictionary:
	if not _is_valid_slot(slot):
		return {}
	var path := _path(slot)
	if not FileAccess.file_exists(path):
		Log.warn(&"Save", "No save in slot '%s'" % slot)
		return {}
	var json := JSON.new()
	var parsed: Variant = null
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		parsed = json.data
	if not parsed is Dictionary or not parsed.has("version") or not parsed.has("data"):
		Log.error(&"Save", "Save file is damaged: %s" % path)
		return {}
	var data: Variant = JSON.to_native(parsed.data)
	var meta: Variant = JSON.to_native(parsed.get("meta", {}))
	if not data is Dictionary:
		Log.error(&"Save", "Save file is damaged: %s" % path)
		return {}
	return {
		"version": int(parsed.version),
		"meta": meta if meta is Dictionary else {},
		"data": data,
	}


# Writes to a temporary file first and renames it over the target, so a crash
# mid-write leaves the previous save intact.
func _write_atomic(path: String, text: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		Log.error(&"Save", "Can't create %s: %s" % [path.get_base_dir(), error_string(err)])
		return err
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		err = FileAccess.get_open_error()
		Log.error(&"Save", "Can't write %s: %s" % [tmp, error_string(err)])
		return err
	file.store_string(text)
	file.close()
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		Log.error(&"Save", "Can't replace %s: %s" % [path, error_string(err)])
		DirAccess.remove_absolute(tmp)
	return err
