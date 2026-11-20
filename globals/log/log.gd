extends Node
## Leveled, categorized logging. The first autoload, so everything can log.
##
##   Log.debug(&"Audio", "pool created for %s" % bus)
##   Log.info(&"Scene", "changed to %s" % scene.name)
##   Log.warn(&"Audio", "unknown id '%s'" % id)       # also push_warning()
##   Log.error(&"Scene", "no scene for key %d" % key)  # also push_error()
##
## Output: [12:03:04.123] [WARN ] [Audio] unknown id 'ui.x'
##
## Messages go through print() / push_warning() / push_error(), so they show in
## the editor's Output and Debugger panels (with backtraces), reach Godot's
## rotating log file (user://logs/godot.log), fail GUT tests (errors) and are
## caught by tools/check.sh (errors).
##
## Levels: DEBUG and INFO can be filtered (globally or per category); WARN and
## ERROR are always logged. Command-line overrides, after "--":
##   --log-level=debug
##   --log=Audio:debug,Scene:warn
##
## The last BUFFER_SIZE entries, including engine errors and warnings (category
## "Engine"), are kept for in-game consoles: recent() and message_logged.

## Emitted for every logged entry (also for captured engine messages), on the
## main thread. See recent() for the entry format.
signal message_logged(entry: Dictionary)

enum Level { DEBUG, INFO, WARN, ERROR }

const LEVEL_LABELS := ["DEBUG", "INFO ", "WARN ", "ERROR"]
const BUFFER_SIZE := 200
const ENGINE_CATEGORY := &"Engine"

## Lowest level that is logged for categories without their own level.
var min_level: Level = Level.DEBUG if OS.is_debug_build() else Level.INFO

var _category_levels: Dictionary = {}  # StringName -> Level
var _buffer: Array[Dictionary] = []
var _mutex := Mutex.new()
var _engine_logger: _EngineLogger
# Thread that is currently printing through Log, so the engine logger can skip
# Log's own output instead of recording it twice. -1 when none.
var _forwarding_thread := -1
# Thread currently recording an engine message: guards against a listener
# that errors on every message (error -> record -> emit -> error ...).
var _engine_record_thread := -1


func _init() -> void:
	apply_cmdline_args(OS.get_cmdline_user_args())
	_engine_logger = _EngineLogger.new(self)
	OS.add_logger(_engine_logger)


func _exit_tree() -> void:
	OS.remove_logger(_engine_logger)


# --- Logging ------------------------------------------------------------------


func debug(category: StringName, message: String) -> void:
	_log(Level.DEBUG, category, message)


func info(category: StringName, message: String) -> void:
	_log(Level.INFO, category, message)


func warn(category: StringName, message: String) -> void:
	_log(Level.WARN, category, message)


func error(category: StringName, message: String) -> void:
	_log(Level.ERROR, category, message)


# --- Configuration ------------------------------------------------------------


## Sets the lowest logged level for one category (WARN and ERROR always log).
func set_level(category: StringName, level: Level) -> void:
	_category_levels[category] = level


## Makes a category follow min_level again.
func clear_level(category: StringName) -> void:
	_category_levels.erase(category)


func get_level(category: StringName) -> Level:
	return _category_levels.get(category, min_level)


## True if a message of this level and category would be logged. Use it to skip
## building expensive debug messages.
func is_enabled(level: Level, category: StringName) -> bool:
	return level >= Level.WARN or level >= get_level(category)


## Applies "--log-level=<level>" and "--log=<Category>:<level>,..." arguments.
## Returns the arguments it couldn't understand (also logged as warnings).
func apply_cmdline_args(args: PackedStringArray) -> PackedStringArray:
	var rejected := PackedStringArray()
	for arg in args:
		if arg.begins_with("--log-level="):
			var level := _parse_level(arg.trim_prefix("--log-level="))
			if level < 0:
				rejected.append(arg)
			else:
				min_level = level as Level
		elif arg.begins_with("--log="):
			for pair in arg.trim_prefix("--log=").split(",", false):
				var parts := pair.split(":")
				var level := _parse_level(parts[1]) if parts.size() == 2 else -1
				if parts.size() != 2 or parts[0].strip_edges() == "" or level < 0:
					rejected.append(pair)
				else:
					set_level(StringName(parts[0].strip_edges()), level as Level)
	for bad in rejected:
		push_warning(
			"Log: ignoring unknown log option '%s' (levels: debug, info, warn, error)" % bad
		)
	return rejected


# --- Recent entries -----------------------------------------------------------


## The most recent entries, oldest first. Each entry is a Dictionary:
##   level: Level, category: StringName, message: String,
##   time: String ("12:03:04.123"), text: String (the formatted line)
func recent(count: int = BUFFER_SIZE) -> Array[Dictionary]:
	_mutex.lock()
	var start := maxi(0, _buffer.size() - count)
	var out: Array[Dictionary] = _buffer.slice(start)
	_mutex.unlock()
	return out


func clear_recent() -> void:
	_mutex.lock()
	_buffer.clear()
	_mutex.unlock()


# --- Internals ----------------------------------------------------------------


func _log(level: Level, category: StringName, message: String) -> void:
	if not is_enabled(level, category):
		return
	var entry := _make_entry(level, category, message)
	_record(entry)

	_forwarding_thread = OS.get_thread_caller_id()
	match level:
		Level.WARN:
			push_warning(entry.text)
		Level.ERROR:
			push_error(entry.text)
		_:
			print(entry.text)
	_forwarding_thread = -1


func _make_entry(level: Level, category: StringName, message: String) -> Dictionary:
	var time := _timestamp()
	return {
		level = level,
		category = category,
		message = message,
		time = time,
		text = "[%s] [%s] [%s] %s" % [time, LEVEL_LABELS[level], category, message],
	}


func _record(entry: Dictionary) -> void:
	_mutex.lock()
	_buffer.append(entry)
	if _buffer.size() > BUFFER_SIZE:
		_buffer.remove_at(0)
	_mutex.unlock()
	# Logging can happen on any thread; listeners (UI) expect the main thread.
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		message_logged.emit(entry)
	else:
		message_logged.emit.call_deferred(entry)


# Called by _EngineLogger for engine and script errors/warnings that didn't
# come through Log itself (e.g. "Cannot open file", runtime script errors).
func _record_engine(is_warning: bool, message: String) -> void:
	var thread := OS.get_thread_caller_id()
	if _forwarding_thread == thread or _engine_record_thread == thread:
		return
	_engine_record_thread = thread
	_record(_make_entry(Level.WARN if is_warning else Level.ERROR, ENGINE_CATEGORY, message))
	_engine_record_thread = -1


func _timestamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	var msec := int(fmod(Time.get_unix_time_from_system(), 1.0) * 1000.0)
	return "%02d:%02d:%02d.%03d" % [now.hour, now.minute, now.second, msec]


func _parse_level(text: String) -> int:
	var index := ["debug", "info", "warn", "error"].find(text.strip_edges().to_lower())
	return index  # -1 if unknown


## Captures engine errors and warnings into Log's buffer (it never prints:
## Godot has already printed them).
class _EngineLogger:
	extends Logger

	var _owner_log: Node

	func _init(owner_log: Node) -> void:
		_owner_log = owner_log

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array
	) -> void:
		var what := rationale if rationale != "" else code
		var where := "%s:%d" % [file.get_file(), line] if file != "" else function
		_owner_log._record_engine(error_type == ERROR_TYPE_WARNING, "%s (%s)" % [what, where])

	func _log_message(_message: String, _error: bool) -> void:
		pass  # plain prints aren't captured; Log records its own messages
