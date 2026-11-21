class_name DefinitionRegistry
extends Node
## Autoload "Definitions". At startup it loads every Definition resource under
## `definitions_dir` (recursively), indexes them by type and id, and validates
## them. Problems are logged with Log.error in debug builds (failing tests and
## CI) and Log.warn in release builds.
##
##   Definitions.get_definition(CardDefinition, &"strike")   # or &"CardDefinition"
##   Definitions.all(CardDefinition)
##   Definitions.with_tag(CardDefinition, &"starter")
##
## A definition is indexed under its own class_name and every parent class
## between it and Definition, so all(ItemDefinition) also returns weapons if
## WeaponDefinition extends ItemDefinition.

## Folder scanned at startup (with subfolders).
@export_dir var definitions_dir := "res://data"

# type -> {id -> Definition}
var _by_type: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	var problems := scan(definitions_dir)
	for problem in problems:
		if OS.is_debug_build():
			Log.error(&"Data", problem)
		else:
			Log.warn(&"Data", problem)
	Log.info(&"Data", "%d definitions loaded from %s" % [count(), definitions_dir])
	_register_commands.call_deferred()


# --- Lookups --------------------------------------------------------------------


## The definition of `type` (a class like CardDefinition, or its name) with
## `id`, or null (logged as a warning).
func get_definition(type: Variant, id: StringName) -> Definition:
	var def: Definition = _by_type.get(type_key(type), {}).get(id)
	if def == null:
		Log.warn(&"Data", "No %s with id '%s'" % [type_key(type), id])
	return def


func has(type: Variant, id: StringName) -> bool:
	return _by_type.get(type_key(type), {}).has(id)


## Every definition of `type`, sorted by id.
func all(type: Variant) -> Array[Definition]:
	var result: Array[Definition] = []
	var table: Dictionary = _by_type.get(type_key(type), {})
	for id in _sorted(table.keys()):
		result.append(table[id])
	return result


func ids(type: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_sorted(_by_type.get(type_key(type), {}).keys()))
	return result


func with_tag(type: Variant, tag: StringName) -> Array[Definition]:
	return all(type).filter(func(def: Definition): return def.has_tag(tag))


## Every indexed type name, sorted.
func types() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_sorted(_by_type.keys()))
	return result


## Number of definitions (each counted once, under its own class).
func count() -> int:
	var seen := {}
	for table in _by_type.values():
		for def in table.values():
			seen[def] = true
	return seen.size()


## The index name of a type: a class (script) -> its class_name; a name as is.
static func type_key(type: Variant) -> StringName:
	if type is Script:
		return (type as Script).get_global_name()
	return StringName(type)


# --- Loading --------------------------------------------------------------------


## Clears the registry, loads every definition under `dir` and validates them.
## Returns the problems found (also used by tests); _ready() logs them.
func scan(dir: String) -> PackedStringArray:
	_by_type.clear()
	var problems := PackedStringArray()
	for path in _find_resources(dir):
		var res := load(path)
		if not res is Definition:
			continue  # other resources may live next to definitions
		var def := res as Definition
		if def.id == &"":
			def.id = StringName(path.get_file().get_basename())
		for key in _type_chain(def):
			var table: Dictionary = _by_type.get_or_add(key, {})
			if table.has(def.id):
				if key == _type_chain(def)[0]:
					problems.append(
						(
							"Duplicate %s id '%s': %s and %s"
							% [key, def.id, table[def.id].resource_path, path]
						)
					)
				continue
			table[def.id] = def

	problems.append_array(validate_all())
	return problems


## Runs validate() on every loaded definition and returns the problems, each
## prefixed with the definition's type, id and file.
func validate_all() -> PackedStringArray:
	var problems := PackedStringArray()
	var checked := {}
	for type in types():
		for def in all(type):
			if checked.has(def):
				continue
			checked[def] = true
			for problem in def.validate(self):
				problems.append(
					"%s '%s' (%s): %s" % [_type_chain(def)[0], def.id, def.resource_path, problem]
				)
	return problems


# Resource paths under `dir`, recursively. ResourceLoader.list_directory()
# lists files as the editor shows them, also in exported builds, where .tres
# files are converted and renamed (x.tres.remap) and a plain DirAccess scan
# would miss them.
func _find_resources(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return result
	for entry in ResourceLoader.list_directory(dir):
		var path := dir.path_join(entry)
		if entry.ends_with("/"):
			result.append_array(_find_resources(path.trim_suffix("/")))
		elif entry.get_extension() in ["tres", "res"]:
			result.append(path)
	return result


# The class names a definition is indexed under: its own first, then parents
# up to (not including) Definition. Scripts without class_name are skipped.
func _type_chain(def: Definition) -> Array[StringName]:
	var chain: Array[StringName] = []
	var script: Script = def.get_script()
	while script != null:
		var name := script.get_global_name()
		if name == &"Definition":
			break
		if name != &"":
			chain.append(name)
		script = script.get_base_script()
	if chain.is_empty():
		chain.append(&"Definition")
	return chain


func _sorted(keys: Array) -> Array:
	var copy := keys.duplicate()
	copy.sort_custom(func(a, b): return str(a) < str(b))
	return copy


# --- Debug console ----------------------------------------------------------------


func _register_commands() -> void:
	Debug.register_command("defs", _cmd_defs, "List definition types, or a type's ids.", "[type]")
	Debug.register_command("def", _cmd_def, "Show one definition's fields.", "<type> <id>")


func _cmd_defs(args: PackedStringArray) -> String:
	if args.is_empty():
		var lines := PackedStringArray()
		for type in types():
			lines.append("%s (%d)" % [type, _by_type[type].size()])
		return "\n".join(lines) if not lines.is_empty() else "no definitions"
	if not _by_type.has(StringName(args[0])):
		return "Unknown type '%s'. Types: %s" % [args[0], ", ".join(types())]
	return ", ".join(ids(args[0]))


func _cmd_def(args: PackedStringArray) -> String:
	if args.size() < 2:
		return "usage: def <type> <id>"
	if not has(args[0], args[1]):
		return "No %s with id '%s'" % [args[0], args[1]]
	var def: Definition = _by_type[StringName(args[0])][StringName(args[1])]
	var lines := PackedStringArray([def.resource_path])
	for prop in def.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE:
			lines.append("  %s = %s" % [prop.name, def.get(prop.name)])
	return "\n".join(lines)
