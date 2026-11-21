extends Node
## Global game state: MENU, PLAYING, PAUSED or LOADING.
##
## This is the ONLY place that sets get_tree().paused and Input.mouse_mode,
## and the only handler of the "pause" action. Scenes declare what they are
## in _ready(), which also works when a scene is run on its own (F6):
##
##   func _ready() -> void:
##       GameState.enter_gameplay(Input.MOUSE_MODE_CAPTURED)   # gameplay scene
##       GameState.enter_menu()                                # menu scene
##
## While PLAYING, "pause" opens the pause menu. While a menu is open, "pause"
## or "ui_cancel" goes back one step (settings -> pause menu -> resume).
##
## Menus shown over the game are kept on a small stack (push_menu/pop_menu),
## on a CanvasLayer below SceneManager's fade overlay.
##
## LOADING is set by SceneManager while it waits for a scene to load; pause
## is ignored then. The state from before comes back when loading ends.

## Add new states at the END (values may be stored as numbers).
enum State { MENU, PLAYING, PAUSED, LOADING }

const PAUSE_MENU_SCENE := preload("res://scenes/ui/menus/pause_menu/pause_menu.tscn")
const SETTINGS_MENU_SCENE := preload("res://scenes/ui/menus/settings_menu/settings_menu.tscn")

## Below SceneManager's overlay (100), so scene fades cover open menus.
const MENU_LAYER := 50

var state: State = State.MENU

var _state_before_loading: State = State.MENU
var _gameplay_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _layer: CanvasLayer
var _dimmer: ColorRect
var _stack: Array[Control] = []
var _pause_menu: PauseMenu
var _settings_menu: SettingsMenu


func _ready() -> void:
	# Must keep receiving input while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.name = "MenuLayer"
	_layer.layer = MENU_LAYER
	add_child(_layer)

	_dimmer = ColorRect.new()
	_dimmer.name = "Dimmer"
	_dimmer.color = Color(0, 0, 0, 0.55)
	_dimmer.visible = false
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to the game
	_layer.add_child(_dimmer)
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Never let a paused tree or an open overlay leak into the next scene.
	SignalBus.scene_change_started.connect(_on_scene_change_started)


# --- Public API ---------------------------------------------------------------


## Call from a menu scene's _ready(): visible cursor, not paused.
func enter_menu() -> void:
	_clear_menus()
	_set_paused(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_state(State.MENU)


## Call from a gameplay scene's _ready(). `mouse_mode` is restored on every resume.
func enter_gameplay(mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE) -> void:
	_gameplay_mouse_mode = mouse_mode
	_clear_menus()
	_set_paused(false)
	Input.mouse_mode = mouse_mode
	_set_state(State.PLAYING)


## Pauses gameplay. With show_menu = false nothing is opened, e.g. for the
## debug console, which needs the game frozen but not the pause menu.
func pause(show_menu := true) -> void:
	if state != State.PLAYING:
		return
	_set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if show_menu:
		push_menu(_get_pause_menu())
	_set_state(State.PAUSED)
	SignalBus.pause_toggled.emit(true)


func resume() -> void:
	if state != State.PAUSED:
		return
	_clear_menus()
	_set_paused(false)
	Input.mouse_mode = _gameplay_mouse_mode
	_set_state(State.PLAYING)
	SignalBus.pause_toggled.emit(false)


## Goes back one step (Esc / ui_cancel). If the top menu has a cancel()
## method (e.g. the settings menu reverting its changes), that runs and the
## menu closes itself through its signal; otherwise the top menu is closed,
## or the game resumes from the pause menu.
func back() -> void:
	if not _stack.is_empty() and _stack.back().has_method("cancel"):
		_stack.back().cancel()
		return
	_close_top()


func _close_top() -> void:
	if _stack.size() > 1:
		pop_menu()
	elif state == State.PAUSED:
		resume()
	elif not _stack.is_empty():
		pop_menu()


## Shows `menu` on top of the overlay stack (hiding the one below).
## The menu is added to the menu layer the first time; it stays there, hidden,
## when popped, so it can be reused.
func push_menu(menu: Control) -> void:
	if menu.get_parent() != _layer:
		if menu.get_parent():
			menu.get_parent().remove_child(menu)
		_layer.add_child(menu)
		menu.process_mode = Node.PROCESS_MODE_ALWAYS  # usable paused or not
		menu.visible = false
	if not _stack.is_empty():
		_close(_stack.back())
	_stack.push_back(menu)
	_dimmer.visible = true
	_open(menu)


func pop_menu() -> void:
	if _stack.is_empty():
		return
	_close(_stack.pop_back())
	if _stack.is_empty():
		_dimmer.visible = false
		_refocus_scene()
	else:
		_open(_stack.back())


## Called by SceneManager while it waits for a scene to load.
func begin_loading() -> void:
	if state == State.LOADING:
		return
	_state_before_loading = state
	_set_state(State.LOADING)


## Called by SceneManager when loading is done. Restores the earlier state,
## unless something already declared a new one.
func end_loading() -> void:
	if state == State.LOADING:
		_set_state(_state_before_loading)


## The settings menu, shared by the pause menu and (from #4) the main menu.
func open_settings() -> void:
	push_menu(_get_settings_menu())


# --- Input --------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	var pause_pressed := event.is_action_pressed("pause")
	var cancel_pressed := event.is_action_pressed("ui_cancel")
	if not (pause_pressed or cancel_pressed):
		return
	if SceneManager.is_changing():
		return

	if state == State.PLAYING:
		# Only the dedicated action pauses; ui_cancel (e.g. a gamepad's B) is
		# often a gameplay button.
		if pause_pressed:
			pause()
			get_viewport().set_input_as_handled()
	elif state == State.PAUSED or not _stack.is_empty():
		back()
		get_viewport().set_input_as_handled()


# --- Internals ----------------------------------------------------------------


func _get_pause_menu() -> PauseMenu:
	if _pause_menu == null:
		_pause_menu = PAUSE_MENU_SCENE.instantiate()
		_pause_menu.resume_pressed.connect(resume)
		_pause_menu.settings_pressed.connect(open_settings)
		_pause_menu.restart_pressed.connect(_restart)
		_pause_menu.quit_pressed.connect(_quit_to_menu)
	return _pause_menu


func _get_settings_menu() -> SettingsMenu:
	if _settings_menu == null:
		_settings_menu = SETTINGS_MENU_SCENE.instantiate()
		_settings_menu.back_pressed.connect(_close_top)
		_settings_menu.apply_pressed.connect(_close_top)
	return _settings_menu


func _restart() -> void:
	_clear_menus()
	_set_paused(false)
	SceneManager.reload_current()


func _quit_to_menu() -> void:
	_clear_menus()
	_set_paused(false)
	SceneManager.change_scene(SceneRegistry.SceneKey.MAIN_MENU, {}, true)


func _on_scene_change_started(_to_scene_key: int) -> void:
	_clear_menus()
	_set_paused(false)


func _clear_menus() -> void:
	while not _stack.is_empty():
		_close(_stack.pop_back())
	_dimmer.visible = false


# After the last overlay closes, give focus back to a menu scene underneath
# (e.g. the main menu after Options), so controllers keep working.
func _refocus_scene() -> void:
	var scene: Node = SceneManager.current_scene
	if scene is MenuBase and scene.is_visible_in_tree():
		(scene as MenuBase).grab_default_focus.call_deferred()


func _open(menu: Control) -> void:
	if menu.has_method("open"):
		menu.open()
	else:
		menu.visible = true


func _close(menu: Control) -> void:
	if menu.has_method("close"):
		menu.close()
	else:
		menu.visible = false


func _set_paused(value: bool) -> void:
	get_tree().paused = value


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	Log.debug(&"GameState", "%s -> %s" % [State.keys()[old], State.keys()[new_state]])
	SignalBus.game_state_changed.emit(new_state, old)
