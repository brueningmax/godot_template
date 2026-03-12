extends Control

@onready var log_label: Label = $VBox/ScrollMsg/LogLabel
@onready var btn_setting: Button = $VBox/Buttons/BtnTestChange
@onready var btn_pause: Button = $VBox/Buttons/BtnTestPause
@onready var btn_back: Button = $VBox/Buttons/BtnBack

var _is_paused := false

func _ready() -> void:
	# Connect to SignalBus
	if is_instance_valid(SignalBus):
		SignalBus.setting_changed.connect(_on_setting_changed)
		SignalBus.pause_toggled.connect(_on_pause_toggled)
		SignalBus.scene_change_started.connect(_on_scene_started)
		SignalBus.scene_change_finished.connect(_on_scene_finished)
		_log("Connected to SignalBus")
	else:
		_log("CRITICAL: SignalBus singleton not found!")
	
	btn_setting.pressed.connect(func():
		SettingsManager.set_setting("test", "dummy", randf())
	)
	
	btn_pause.pressed.connect(func():
		_is_paused = !_is_paused
		SignalBus.pause_toggled.emit(_is_paused)
	)
	
	btn_back.pressed.connect(func():
		if is_instance_valid(SceneManager):
			SceneManager.goto_menu()
	)

func _on_setting_changed(key: String, val: Variant) -> void:
	_log("SIGNAL RECV: setting_changed -> %s: %s" % [key, str(val)])

func _on_pause_toggled(p: bool) -> void:
	_log("SIGNAL RECV: pause_toggled -> %s" % str(p))

func _on_scene_started(key: int) -> void:
	_log("SIGNAL RECV: scene_change_started -> %d" % key)

func _on_scene_finished(node: Node) -> void:
	_log("SIGNAL RECV: scene_change_finished -> %s" % node.name)

func _log(msg: String) -> void:
	log_label.text += "\n" + msg
	print("[TestSignals] " + msg)
