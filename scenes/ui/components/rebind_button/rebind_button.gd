class_name RebindButton
extends Button
## Shows an action's binding for one device kind and rebinds it: press the
## button, then the new key or controller button / stick direction.
## Escape or a left click cancels listening, so neither can be bound
## (Escape stays the menu/back key).
##
## Uses InputBindings.bind(), which swaps with any action already using the
## new input. Changes are previews (not saved) unless `persist` is true.

## Emitted after a new binding was set.
signal rebound(action: String, event: InputEvent)

@export var action := ""
@export var device: InputBindings.Device = InputBindings.Device.KEYBOARD
## Save immediately instead of previewing (the settings menu saves on Apply).
@export var persist := false

var _listening := false
# Events from before this frame belong to the press that started listening.
var _listen_from_frame := 0


func _ready() -> void:
	toggle_mode = false
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # key names
	custom_minimum_size.x = 140
	pressed.connect(start_listening)
	refresh()


## Shows the current binding (call after bindings changed elsewhere).
func refresh() -> void:
	if not _listening:
		text = InputBindings.display_name(InputBindings.event_for(action, device))


func is_listening() -> bool:
	return _listening


func start_listening() -> void:
	_listening = true
	_listen_from_frame = Engine.get_process_frames() + 1
	text = tr("Press a key…") if device == InputBindings.Device.KEYBOARD else tr("Press a button…")


func cancel_listening() -> void:
	_listening = false
	refresh()


func _input(event: InputEvent) -> void:
	if not _listening or Engine.get_process_frames() < _listen_from_frame:
		return
	if not event.is_pressed() or event.is_echo():
		return
	var is_escape: bool = event is InputEventKey and event.physical_keycode == KEY_ESCAPE
	var is_click: bool = (
		event is InputEventMouseButton
		and (
			event.button_index
			in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		)
	)
	if is_escape or is_click:
		cancel_listening()
		get_viewport().set_input_as_handled()
		return
	if InputBindings.device_of(event) != device:
		return
	var bindable := InputBindings.normalize(event)
	if bindable == null:
		return  # e.g. a stick barely moved
	get_viewport().set_input_as_handled()
	_listening = false
	InputBindings.bind(action, bindable, persist)
	refresh()
	rebound.emit(action, bindable)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _listening:
		cancel_listening()
