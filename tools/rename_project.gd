extends SceneTree
## Sets the project's name (config/name in project.godot).
##
## Usage, from the project folder:
##   godot --headless --script res://tools/rename_project.gd -- "My Game"
##
## Run it before the game's first real run: the name also decides the user
## data folder (user://, which holds settings, saves and logs).
## Afterwards, delete the .godot/ folder so the editor cache is rebuilt.

const USAGE := 'usage: godot --headless --script res://tools/rename_project.gd -- "My Game"'


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	if args.size() != 1 or args[0].strip_edges() == "":
		printerr(USAGE)
		return 2
	var project_name := args[0].strip_edges()

	var path := ProjectSettings.globalize_path("res://project.godot")
	var text := FileAccess.get_file_as_string(path)
	var regex := RegEx.create_from_string('(?m)^config/name=".*"$')
	var found := regex.search(text)
	if found == null:
		printerr("rename_project: no config/name line in project.godot")
		return 1

	# Edit the one line as text so the rest of project.godot stays untouched.
	var new_line := 'config/name="%s"' % project_name.c_escape()
	if found.get_string() == new_line:
		print('rename_project: already named "%s", nothing to do' % project_name)
		return 0
	text = text.substr(0, found.get_start()) + new_line + text.substr(found.get_end())

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr(
			(
				"rename_project: can't write project.godot (%s)"
				% error_string(FileAccess.get_open_error())
			)
		)
		return 1
	file.store_string(text)
	file.close()

	print('rename_project: project renamed to "%s"' % project_name)
	print("  User data (settings, saves) will be stored in a folder named after the project.")
	print("  Now delete the .godot/ folder (editor cache) and reopen the project.")
	return 0
