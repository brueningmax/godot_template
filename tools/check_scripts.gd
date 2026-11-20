extends SceneTree
## Compiles every GDScript file in the project and reports the ones that fail.
##
## Usage (from the project folder):
##   godot --headless --script res://tools/check_scripts.gd
##
## Exit code: 0 if every script compiles, otherwise the number of failures.
##
## Why not `godot --check-only --script <file>`? That mode doesn't create the
## autoloads, so every script that uses SignalBus, Audio, etc. reports a false
## "Identifier not found" error. This tool runs after the autoloads exist.

const SKIP_DIRS := ["res://.godot", "res://addons"]
const TIMEOUT_SEC := 60.0


func _initialize() -> void:
	# Never hang CI: if anything below stalls, fail loudly.
	create_timer(TIMEOUT_SEC).timeout.connect(
		func():
			printerr("check_scripts: timed out after %d s" % TIMEOUT_SEC)
			quit(255)
	)
	await process_frame  # autoloads are in the tree now

	var paths: Array[String] = []
	_collect("res://", paths)
	paths.sort()

	var failed: Array[String] = []
	for path in paths:
		var script: Script = load(path)
		if script == null or not (script.can_instantiate() or _is_abstract(path)):
			failed.append(path)

	print("check_scripts: %d scripts, %d failed" % [paths.size(), failed.size()])
	for path in failed:
		printerr("  FAILED: " + path)
	quit(failed.size())


func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path in SKIP_DIRS:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.get_extension() == "gd":
			out.append(dir_path.path_join(file))


## Abstract classes compile fine but can't be instantiated.
func _is_abstract(path: String) -> bool:
	return FileAccess.get_file_as_string(path).contains("@abstract")
