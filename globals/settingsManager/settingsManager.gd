extends Node

## Handles global game settings, persistence (saving/loading), 
## and applying settings to the engine (AudioServer, DisplayServer).

const SETTINGS_PATH = "user://settings.cfg"

# Default values
var _settings = {
	"audio": {
		"master_volume": 0.8,
		"sfx_volume": 1.0,
		"music_volume": 0.7,
	},
	"display": {
		"fullscreen": true,
		"vsync": true,
	}
}

func _ready() -> void:
	load_settings()
	apply_all()

# --- Public API ---

func set_setting(section: String, key: String, value: Variant) -> void:
	if not _settings.has(section):
		_settings[section] = {}
	_settings[section][key] = value
	
	_apply_setting(section, key, value)
	save_settings()
	
	if is_instance_valid(SignalBus):
		SignalBus.setting_changed.emit(section + ":" + key, value)

func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	if _settings.has(section) and _settings[section].has(key):
		return _settings[section][key]
	return default

# --- Persistence ---

func save_settings() -> void:
	var config = ConfigFile.new()
	for section in _settings.keys():
		for key in _settings[section].keys():
			config.set_value(section, key, _settings[section][key])
	
	var err = config.save(SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: Failed to save settings to %s" % SETTINGS_PATH)

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	
	if err == OK:
		for section in config.get_sections():
			if not _settings.has(section):
				_settings[section] = {}
			for key in config.get_section_keys(section):
				_settings[section][key] = config.get_value(section, key)
	else:
		# If file doesn't exist or is corrupted, we just use defaults (already in _settings)
		save_settings()

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

func _apply_audio(key: String, value: float) -> void:
	var bus_name = "Master"
	match key:
		"master_volume": bus_name = "Master"
		"sfx_volume": bus_name = "SFX"
		"music_volume": bus_name = "Music"
	
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		# Convert 0-1 linear to decibels
		var db = linear_to_db(value)
		AudioServer.set_bus_volume_db(bus_index, db)
		AudioServer.set_bus_mute(bus_index, value <= 0.001)

func _apply_display(key: String, value: Variant) -> void:
	match key:
		"fullscreen":
			var mode = Window.MODE_EXCLUSIVE_FULLSCREEN if value else Window.MODE_WINDOWED
			DisplayServer.window_set_mode(mode)
		"vsync":
			var mode = DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
			DisplayServer.window_set_vsync_mode(mode)
