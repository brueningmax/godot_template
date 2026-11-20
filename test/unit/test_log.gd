extends GutTest
## Log: levels, categories, command-line overrides, buffer, engine capture.

var _orig_min_level: int
var _orig_levels: Dictionary


func before_each() -> void:
	_orig_min_level = Log.min_level
	_orig_levels = Log._category_levels.duplicate()
	Log._category_levels.clear()
	Log.min_level = Log.Level.DEBUG
	Log.clear_recent()


func after_each() -> void:
	Log.min_level = _orig_min_level
	Log._category_levels = _orig_levels
	Log.clear_recent()


func test_messages_are_recorded_with_level_and_category() -> void:
	Log.info(&"Test", "hello")
	var entries := Log.recent()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].level, Log.Level.INFO)
	assert_eq(entries[0].category, &"Test")
	assert_eq(entries[0].message, "hello")


func test_format() -> void:
	Log.warn(&"Audio", "unknown id 'x'")
	var regex := RegEx.create_from_string(
		r"^\[\d\d:\d\d:\d\d\.\d{3}\] \[WARN \] \[Audio\] unknown id 'x'$"
	)
	assert_not_null(regex.search(Log.recent()[0].text), Log.recent()[0].text)


func test_min_level_filters_debug_and_info() -> void:
	Log.min_level = Log.Level.WARN
	Log.debug(&"Test", "hidden")
	Log.info(&"Test", "hidden too")
	assert_eq(Log.recent().size(), 0)


func test_category_level_overrides_min_level() -> void:
	Log.min_level = Log.Level.WARN
	Log.set_level(&"Audio", Log.Level.DEBUG)
	Log.debug(&"Audio", "shown")
	Log.debug(&"Scene", "hidden")
	assert_eq(Log.recent().map(func(e): return e.message), ["shown"])
	Log.clear_level(&"Audio")
	assert_eq(Log.get_level(&"Audio"), Log.Level.WARN)


func test_warn_and_error_are_never_filtered() -> void:
	Log.min_level = Log.Level.ERROR
	Log.set_level(&"Test", Log.Level.ERROR)
	Log.warn(&"Test", "still shown")
	assert_eq(Log.recent().size(), 1)
	assert_true(Log.is_enabled(Log.Level.WARN, &"Test"))
	assert_false(Log.is_enabled(Log.Level.INFO, &"Test"))


func test_error_goes_through_push_error() -> void:
	Log.error(&"Test", "something broke")
	assert_push_error("[Test] something broke")


func test_own_errors_are_recorded_once() -> void:
	Log.error(&"Test", "only once")
	assert_push_error("only once")
	var matching := Log.recent().filter(func(e): return e.message.contains("only once"))
	assert_eq(matching.size(), 1, "not also captured as an Engine entry")


func test_engine_errors_are_captured() -> void:
	push_error("raw engine-style error")
	assert_push_error("raw engine-style error")
	var engine := Log.recent().filter(func(e): return e.category == Log.ENGINE_CATEGORY)
	assert_eq(engine.size(), 1)
	if engine.size() == 1:
		assert_eq(engine[0].level, Log.Level.ERROR)
		assert_string_contains(engine[0].message, "raw engine-style error")


func test_buffer_keeps_last_entries_oldest_first() -> void:
	for i in Log.BUFFER_SIZE + 10:
		Log.debug(&"Test", "m%d" % i)
	var entries := Log.recent()
	assert_eq(entries.size(), Log.BUFFER_SIZE)
	assert_eq(entries[0].message, "m10")
	assert_eq(entries[-1].message, "m%d" % (Log.BUFFER_SIZE + 9))
	assert_eq(Log.recent(3).map(func(e): return e.message), ["m207", "m208", "m209"])


func test_message_logged_signal() -> void:
	watch_signals(Log)
	Log.info(&"Test", "signalled")
	assert_signal_emitted(Log, "message_logged")
	var entry: Dictionary = get_signal_parameters(Log, "message_logged")[0]
	assert_eq(entry.message, "signalled")


func test_cmdline_args() -> void:
	var rejected := Log.apply_cmdline_args(
		PackedStringArray(
			[
				"--log-level=warn",
				"--log=Audio:debug,Scene:error",
				"--log=Bad",
				"--log-level=loud",
				"--other"
			]
		)
	)
	assert_eq(Log.min_level, Log.Level.WARN)
	assert_eq(Log.get_level(&"Audio"), Log.Level.DEBUG)
	assert_eq(Log.get_level(&"Scene"), Log.Level.ERROR)
	assert_eq(Array(rejected), ["Bad", "--log-level=loud"], "in argument order")


func test_level_names_are_case_insensitive() -> void:
	Log.apply_cmdline_args(PackedStringArray(["--log-level=DEBUG"]))
	assert_eq(Log.min_level, Log.Level.DEBUG)
