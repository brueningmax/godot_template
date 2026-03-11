extends CanvasLayer
class_name MenuRoot

enum MenuState { NONE, PAUSE, SETTINGS, RESULTS }

@onready var dimmer     := $Dimmer
@onready var pause_menu: PauseMenu = $MenuStack/PauseMenu
@onready var settings_menu: SettingsMenu = $MenuStack/SettingsMenu
@onready var results_menu: ResultsMenu = $MenuStack/ResultsMenu
@onready var current_session: GameSession = get_parent()

var _stack: Array[int] = [] 

func _ready():
	dimmer.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	for m in [pause_menu, results_menu, settings_menu]:
		m.visible = false
		m.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		
	   # Wire submenu signals (names are examples)
	if pause_menu.has_signal("resume_pressed"):
		pause_menu.resume_pressed.connect(_on_resume)
	if pause_menu.has_signal("settings_pressed"):
		pause_menu.settings_pressed.connect(open_settings)
	if pause_menu.has_signal("restart_pressed"):
		pause_menu.restart_pressed.connect(_on_restart)
	if pause_menu.has_signal("quit_pressed"):
		pause_menu.quit_pressed.connect(_on_quit)

	if settings_menu.has_signal("back_pressed"):
		settings_menu.back_pressed.connect(_on_back)
	if settings_menu.has_signal("apply_pressed"):
		settings_menu.apply_pressed.connect(_on_settings_apply)

	if results_menu.has_signal("restart_pressed"):
		results_menu.restart_pressed.connect(_on_restart)
	if results_menu.has_signal("quit_pressed"):
		results_menu.quit_pressed.connect(_on_quit)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		var current_menu = _current_menu()
		match current_menu:
			MenuState.NONE:
				open_pause()
			MenuState.PAUSE:
				_on_resume()   # same key resumes
			MenuState.SETTINGS:
				_on_back()     # go back to Pause
			MenuState.RESULTS:
				pass        

# --- Public API --------------------------------------------------------------

func open_pause() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _current_menu() == MenuState.RESULTS: return
	if _current_menu() == MenuState.PAUSE:   return
	_push(MenuState.PAUSE)

func open_settings() -> void:
	if _current_menu() == MenuState.SETTINGS: return
	_push(MenuState.SETTINGS)

func open_results(scores: ScoreClasses.ResultObject) -> void:
	_stack.clear()
	var summary = current_session.score.get_summary()
	results_menu.display(summary, scores)
	_push(MenuState.RESULTS)

func close_all() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_stack.clear()
	_apply_state()
	
# --- Actions ----------------------------------------------------------------

func _on_resume() -> void:
	#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	close_all()                      # NONE → unpaused

func _on_restart() -> void:
	current_session._restart()
	close_all()

func _on_quit() -> void:
	close_all()
	SceneManager.change_scene(SceneRegistry.SceneKey.MainMenu)

func _on_back() -> void:
	_pop()

func _on_settings_apply() -> void:
	_pop()                           # or keep you on settings, your call

# --- Stack helpers -----------------------------------------------------------

func _current_menu() -> int:
	return MenuState.NONE if _stack.is_empty() else _stack.back()

func _push(menu: int) -> void:
	if _stack.size() > 0 and _stack.back() == menu: return
	if menu != MenuState.NONE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_stack.push_back(menu)
	_apply_state()

func _pop() -> void:
	if _stack.is_empty(): return
	_stack.pop_back()
	_apply_state()

func _apply_state() -> void:
	var current_menu := _current_menu()

	# Pause rules: PAUSE/SETTINGS paused, RESULTS optional (here: paused = true for static backdrop)
	get_tree().paused = (current_menu == MenuState.PAUSE || current_menu == MenuState.SETTINGS || current_menu == MenuState.RESULTS)

	# Visibility
	pause_menu.visible    = (current_menu == MenuState.PAUSE)
	settings_menu.visible = (current_menu == MenuState.SETTINGS)
	results_menu.visible  = (current_menu == MenuState.RESULTS)
	dimmer.visible        = (current_menu != MenuState.NONE)

	# Call submenu lifecycle hooks if they exist
	for menu in [pause_menu, results_menu, settings_menu]:
		if menu.visible and menu.has_method("open"):
			menu.open()
		elif !menu.visible and menu.has_method("close"):
			menu.close()

	## Focus
	if pause_menu.visible and pause_menu.has_method("grab_default_focus"):
		pause_menu.grab_default_focus()
	if settings_menu.visible and settings_menu.has_method("grab_default_focus"):
		settings_menu.grab_default_focus()
	if results_menu.visible and results_menu.has_method("grab_default_focus"):
		results_menu.grab_default_focus()
