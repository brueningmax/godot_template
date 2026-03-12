extends Control

@onready var master_slider: HSlider = $Panel/VBox/MasterVol/Slider
@onready var fullscreen_check: CheckBox = $Panel/VBox/Fullscreen/Check
@onready var btn_play_sound: Button = $Panel/VBox/BtnPlaySound
@onready var log_label: Label = $Panel/VBox/Log

func _ready() -> void:
	# Initialize UI from SettingsManager
	master_slider.value = SettingsManager.get_setting("audio", "master_volume", 0.8)
	fullscreen_check.button_pressed = SettingsManager.get_setting("display", "fullscreen", true)
	
	# Connect signals
	master_slider.value_changed.connect(_on_master_vol_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	btn_play_sound.pressed.connect(_on_play_sound_pressed)
	
	# Listen to SignalBus
	if is_instance_valid(SignalBus):
		SignalBus.setting_changed.connect(_on_external_setting_change)

func _on_master_vol_changed(val: float) -> void:
	SettingsManager.set_setting("audio", "master_volume", val)
	_log("Master Volume -> %.2f" % val)

func _on_fullscreen_toggled(val: bool) -> void:
	SettingsManager.set_setting("display", "fullscreen", val)
	_log("Fullscreen -> %s" % str(val))

func _on_play_sound_pressed() -> void:
	if is_instance_valid(Audio):
		Audio.play(&"ui.click")
		_log("Played: ui.click")
	else:
		_log("Error: Audio manager not found")

func _on_external_setting_change(key: String, val: Variant) -> void:
	_log("External: %s -> %s" % [key, str(val)])

func _log(msg: String) -> void:
	log_label.text = "Log: " + msg
	print("[TestSettings] " + msg)
