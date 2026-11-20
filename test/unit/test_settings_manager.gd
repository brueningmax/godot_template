extends GutTest
## SettingsManager: persistence, defaults, preview and revert.
## Uses a temporary settings file; the player's real settings are untouched.

const TEST_PATH := "user://test_settings.cfg"

var _orig_path: String
var _orig_values: Dictionary


func before_each() -> void:
	_orig_path = SettingsManager.settings_path
	_orig_values = SettingsManager.snapshot()
	SettingsManager.settings_path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	SettingsManager.reset_to_defaults()


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	SettingsManager.settings_path = _orig_path
	SettingsManager.restore(_orig_values)


func test_set_setting_saves_and_load_reads_back() -> void:
	SettingsManager.set_setting("audio", "music_volume", 0.33)
	assert_almost_eq(_file_value("audio", "music_volume"), 0.33, 0.0001, "written to file")
	SettingsManager.set_setting("audio", "music_volume", 0.9, false)
	SettingsManager.load_settings()
	assert_almost_eq(SettingsManager.get_setting("audio", "music_volume"), 0.33, 0.0001)


func test_persist_false_does_not_write() -> void:
	SettingsManager.set_setting("audio", "music_volume", 0.2, false)
	assert_false(FileAccess.file_exists(TEST_PATH), "no file written")
	assert_almost_eq(SettingsManager.get_setting("audio", "music_volume"), 0.2, 0.0001)


func test_partial_file_merges_over_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", 0.1)
	cfg.save(TEST_PATH)
	SettingsManager.load_settings()
	assert_almost_eq(SettingsManager.get_setting("audio", "master_volume"), 0.1, 0.0001)
	assert_eq(
		SettingsManager.get_setting("audio", "music_volume"),
		SettingsManager.DEFAULTS.audio.music_volume,
		"missing key keeps its default"
	)
	assert_eq(
		SettingsManager.get_setting("display", "vsync"), SettingsManager.DEFAULTS.display.vsync
	)


func test_missing_file_is_created_with_defaults() -> void:
	SettingsManager.load_settings()
	assert_true(FileAccess.file_exists(TEST_PATH))
	assert_eq(_file_value("display", "vsync"), SettingsManager.DEFAULTS.display.vsync)


func test_get_setting_default_for_unknown_key() -> void:
	assert_eq(SettingsManager.get_setting("nope", "missing", 42), 42)


func test_snapshot_and_restore() -> void:
	var snap := SettingsManager.snapshot()
	SettingsManager.set_setting("audio", "sfx_volume", 0.05, false)
	SettingsManager.restore(snap)
	assert_eq(
		SettingsManager.get_setting("audio", "sfx_volume"),
		SettingsManager.DEFAULTS.audio.sfx_volume
	)
	assert_false(FileAccess.file_exists(TEST_PATH), "restore doesn't save")


func test_snapshot_is_a_deep_copy() -> void:
	var snap := SettingsManager.snapshot()
	snap.audio.master_volume = 0.0
	assert_ne(SettingsManager.get_setting("audio", "master_volume"), 0.0)


func test_volume_is_applied_to_bus() -> void:
	SettingsManager.set_setting("audio", "music_volume", 0.25, false)
	var bus := AudioServer.get_bus_index("Music")
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25), 0.001)
	SettingsManager.set_setting("audio", "music_volume", 0.0, false)
	assert_true(AudioServer.is_bus_mute(bus), "zero volume mutes the bus")


func test_setting_changed_signal() -> void:
	watch_signals(SignalBus)
	SettingsManager.set_setting("audio", "music_volume", 0.5, false)
	assert_signal_emitted_with_parameters(
		SignalBus, "setting_changed", ["audio", "music_volume", 0.5]
	)


func _file_value(section: String, key: String) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(TEST_PATH)
	return cfg.get_value(section, key)
