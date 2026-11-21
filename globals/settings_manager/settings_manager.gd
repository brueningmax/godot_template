extends Node

## Handles global game settings, persistence (saving/loading),
## and applying settings to the engine (AudioServer, DisplayServer).

## Bump when a key is renamed or changes meaning, and convert old files in
## _migrate(). New keys need no bump: they're merged in from DEFAULTS.
const SCHEMA_VERSION := 2

## Window modes for display/window_mode.
const WINDOW_MODES := {
	"windowed": Window.MODE_WINDOWED,
	"fullscreen": Window.MODE_FULLSCREEN,  # borderless, fast to alt-tab
	"exclusive": Window.MODE_EXCLUSIVE_FULLSCREEN,
}

## audio/<key> -> bus in resources/audio/bus_layout.tres.
const VOLUME_BUSES := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
	"ui_volume": "UI",
	"ambient_volume": "Ambient",
}

## Default value of every setting. Values from the settings file are merged
## over these, so new keys added here reach existing players automatically.
## Debug builds (editor runs) start windowed instead: see defaults().
const DEFAULTS := {
	"audio":
	{
		"master_volume": 0.8,
		"music_volume": 0.7,
		"sfx_volume": 1.0,
		"ui_volume": 1.0,
		"ambient_volume": 1.0,
	},
	"display":
	{
		"window_mode": "fullscreen",
		"resolution": Vector2i(1280, 720),  # window size when windowed
		"vsync": true,
		"max_fps": 0,  # 0 = no cap
	},
	"interface":
	{
		"ui_scale": 1.0,
		"language": "",  # "" = the system language
	},
	# Rebound actions only, {action: ["key:87", "joy_button:0"]}; see
	# InputBindings. Actions not listed use Project Settings → Input Map.
	"input": {},
}

## Where settings are saved. Tests point this at a temporary file.
var settings_path := "user://settings.cfg"

var _settings: Dictionary = defaults()


func _ready() -> void:
	load_settings()
	apply_all()


# --- Public API ---


## Changes a setting, applies it to the engine and emits SignalBus.setting_changed.
## With `persist` (default) the settings file is written too. Pass false to
## preview a value (e.g. while dragging a slider) and call save_settings() later.
func set_setting(section: String, key: String, value: Variant, persist := true) -> void:
	if not _settings.has(section):
		_settings[section] = {}
	_settings[section][key] = value

	_apply_setting(section, key, value)
	if persist:
		save_settings()

	SignalBus.setting_changed.emit(section, key, value)


## DEFAULTS for this build: debug builds (editor runs, debug exports) start
## windowed, so a run from the editor doesn't take over the screen.
static func defaults() -> Dictionary:
	var values := DEFAULTS.duplicate(true)
	if OS.is_debug_build():
		values.display.window_mode = "windowed"
	return values


## Puts every setting back to defaults() and applies them (does not save).
func reset_to_defaults() -> void:
	restore(defaults())


## A deep copy of all current settings, e.g. to revert a settings menu.
func snapshot() -> Dictionary:
	return _settings.duplicate(true)


## Applies every value from a snapshot() (without saving) and emits
## setting_changed for each, so UIs listening to the bus update too. Keys
## added since the snapshot (e.g. a new key binding) are removed again.
func restore(values: Dictionary) -> void:
	for section in _settings.keys():
		for key in _settings[section].keys():
			if not (values.has(section) and values[section].has(key)):
				_unset(section, key)
	for section in values.keys():
		for key in values[section].keys():
			set_setting(section, key, values[section][key], false)


## Puts every key binding back to Project Settings → Input Map.
func reset_controls(persist := true) -> void:
	for action in _settings.get("input", {}).keys():
		_unset("input", action)
	if persist:
		save_settings()


# Removes a stored key: input actions go back to the project's events, other
# keys to their default (if they have one).
func _unset(section: String, key: String) -> void:
	_settings[section].erase(key)
	if section == "input":
		InputBindings.apply(key, null)
		SignalBus.setting_changed.emit(section, key, null)
		return
	var fallback: Variant = defaults().get(section, {}).get(key)
	if fallback != null:
		set_setting(section, key, fallback, false)


func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	if _settings.has(section) and _settings[section].has(key):
		return _settings[section][key]
	return default


# --- Persistence ---


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SCHEMA_VERSION)
	for section in _settings.keys():
		for key in _settings[section].keys():
			config.set_value(section, key, _settings[section][key])

	var err := config.save(settings_path)
	if err != OK:
		Log.error(&"Settings", "Failed to save settings to %s" % settings_path)


## Reads the settings file and merges it over defaults(). A missing or broken
## file is replaced by one with the defaults. Call apply_all() afterwards to
## apply what was read (done at startup).
func load_settings() -> void:
	_settings = defaults()
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK:
		save_settings()
		return

	var version: int = config.get_value("meta", "version", 1)
	for section in config.get_sections():
		if section == "meta":
			continue
		if not _settings.has(section):
			_settings[section] = {}
		for key in config.get_section_keys(section):
			_settings[section][key] = config.get_value(section, key)
	if version < SCHEMA_VERSION:
		_migrate(version)
		save_settings()


# Converts settings read from an older file, one version at a time.
func _migrate(from_version: int) -> void:
	if from_version < 2:
		# v1 had display/fullscreen (bool, exclusive fullscreen).
		var display: Dictionary = _settings.display
		if display.has("fullscreen"):
			display.window_mode = "exclusive" if display.fullscreen else "windowed"
			display.erase("fullscreen")
	Log.info(&"Settings", "settings file upgraded from version %d" % from_version)


# --- Internal: Applying Settings ---


func apply_all() -> void:
	for section in _settings.keys():
		for key in _settings[section].keys():
			_apply_setting(section, key, _settings[section][key])


func _apply_setting(section: String, key: String, value: Variant) -> void:
	match section:
		"audio":
			_apply_audio(key, value)
		"display":
			_apply_display(key, value)
		"interface":
			_apply_interface(key, value)
		"input":
			InputBindings.apply(key, value)


func _apply_audio(key: String, value: Variant) -> void:
	if not VOLUME_BUSES.has(key):
		return
	var bus_index := AudioServer.get_bus_index(VOLUME_BUSES[key])
	if bus_index != -1:
		# Settings are linear 0..1; buses use decibels.
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(float(value)))
		AudioServer.set_bus_mute(bus_index, float(value) <= 0.001)


func _apply_display(key: String, value: Variant) -> void:
	match key:
		"window_mode":
			var mode: int = WINDOW_MODES.get(value, Window.MODE_WINDOWED)
			DisplayServer.window_set_mode(mode)
			if mode == Window.MODE_WINDOWED:
				_apply_window_size(get_setting("display", "resolution", Vector2i(1280, 720)))
		"resolution":
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
				_apply_window_size(value)
		"vsync":
			var mode := DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
			DisplayServer.window_set_vsync_mode(mode)
		"max_fps":
			Engine.max_fps = maxi(int(value), 0)


func _apply_interface(key: String, value: Variant) -> void:
	match key:
		"ui_scale":
			get_tree().root.content_scale_factor = clampf(float(value), 0.5, 3.0)
		"language":
			var locale := str(value)
			TranslationServer.set_locale(locale if locale != "" else OS.get_locale())


# Resizes the window (clamped to the screen) and centres it.
func _apply_window_size(value: Variant) -> void:
	if not value is Vector2i or DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var size := Vector2i(mini(value.x, usable.size.x), mini(value.y, usable.size.y))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
