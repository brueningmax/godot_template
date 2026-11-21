class_name InputBindings
extends RefCounted
## Player key and controller bindings, stored by SettingsManager in its
## "input" section as {action: ["key:65", "joy_button:0", ...]}.
##
## Only actions in REBINDABLE can be changed by players. An action with no
## entry in the settings uses the events from Project Settings → Input Map.
##
## Each action has one binding per device kind (keyboard, gamepad). Binding an
## event that another rebindable action already uses swaps the two.

enum Device { KEYBOARD, GAMEPAD }

## Actions players may rebind, in menu order. Add your game's actions here and
## a row for each in the settings menu.
const REBINDABLE: Array[String] = [
	"up", "down", "left", "right", "jump", "pause", "debug_overlay", "debug_console"
]

## A stick has to move this far (0..1) to count as a binding.
const AXIS_THRESHOLD := 0.6

const _JOY_BUTTON_NAMES := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const _JOY_AXIS_NAMES := {
	JOY_AXIS_LEFT_X: ["Left stick left", "Left stick right"],
	JOY_AXIS_LEFT_Y: ["Left stick up", "Left stick down"],
	JOY_AXIS_RIGHT_X: ["Right stick left", "Right stick right"],
	JOY_AXIS_RIGHT_Y: ["Right stick up", "Right stick down"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"],
	JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}

# --- Events <-> text ---------------------------------------------------------


## "key:65" (physical key), "keycode:65", "mouse:2", "joy_button:0",
## "joy_axis:0:-" / "joy_axis:0:+". "" for events that can't be bound.
static func serialize(event: InputEvent) -> String:
	if event is InputEventKey:
		if event.physical_keycode != KEY_NONE:
			return "key:%d" % event.physical_keycode
		return "keycode:%d" % event.keycode
	if event is InputEventMouseButton:
		return "mouse:%d" % event.button_index
	if event is InputEventJoypadButton:
		return "joy_button:%d" % event.button_index
	if event is InputEventJoypadMotion:
		return "joy_axis:%d:%s" % [event.axis, "-" if event.axis_value < 0.0 else "+"]
	return ""


## The event for a serialize() string, or null if it isn't one.
static func deserialize(text: String) -> InputEvent:
	var parts := text.split(":")
	if parts.size() < 2 or not parts[1].is_valid_int():
		return null
	var number := parts[1].to_int()
	match parts[0]:
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = number as Key
			return key
		"keycode":
			var key := InputEventKey.new()
			key.keycode = number as Key
			return key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = number as MouseButton
			return mouse
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.device = -1
			button.button_index = number as JoyButton
			return button
		"joy_axis":
			if parts.size() != 3:
				return null
			var motion := InputEventJoypadMotion.new()
			motion.device = -1
			motion.axis = number as JoyAxis
			motion.axis_value = -1.0 if parts[2] == "-" else 1.0
			return motion
	return null


static func serialize_all(events: Array) -> Array[String]:
	var result: Array[String] = []
	for event in events:
		var text := serialize(event)
		if text != "":
			result.append(text)
	return result


## KEYBOARD (keys, mouse buttons), GAMEPAD, or -1.
static func device_of(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton:
		return Device.KEYBOARD
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return Device.GAMEPAD
	return -1


## A short name for showing a binding, e.g. "W", "A", "Left stick up".
static func display_name(event: InputEvent) -> String:
	if event == null:
		return "—"
	if event is InputEventKey:
		var keycode: Key = event.keycode
		if event.physical_keycode != KEY_NONE:
			# The key's label on this keyboard layout (W on QWERTY, Z on AZERTY).
			# Headless (tests, CI) has no layout and errors, so use the position.
			keycode = event.physical_keycode
			if DisplayServer.get_name() != "headless":
				keycode = DisplayServer.keyboard_get_label_from_physical(event.physical_keycode)
		return OS.get_keycode_string(keycode)
	if event is InputEventMouseButton:
		return "Mouse %d" % event.button_index
	if event is InputEventJoypadButton:
		return _JOY_BUTTON_NAMES.get(event.button_index, "Button %d" % event.button_index)
	if event is InputEventJoypadMotion:
		var names: Array = _JOY_AXIS_NAMES.get(
			event.axis, ["Axis %d-" % event.axis, "Axis %d+" % event.axis]
		)
		return names[0] if event.axis_value < 0.0 else names[1]
	return event.as_text()


# --- Reading and applying ----------------------------------------------------


## The action's events from Project Settings (what "reset" goes back to).
static func default_events(action: String) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	var setting: Variant = ProjectSettings.get_setting("input/" + action)
	if setting is Dictionary:
		for event in setting.get("events", []):
			result.append(event)
	return result


## The first event of `device` bound to `action` right now, or null.
static func event_for(action: String, device: int) -> InputEvent:
	for event in InputMap.action_get_events(action):
		if device_of(event) == device:
			return event
	return null


## Replaces the action's events in the InputMap. `value` is a list of
## serialize() strings; null restores the Project Settings events.
static func apply(action: String, value: Variant) -> void:
	if not InputMap.has_action(action):
		Log.warn(&"Input", "Saved binding for unknown action '%s' ignored" % action)
		return
	InputMap.action_erase_events(action)
	if value == null:
		for event in default_events(action):
			InputMap.action_add_event(action, event)
		return
	for text in value:
		var event := deserialize(str(text))
		if event:
			InputMap.action_add_event(action, event)


# --- Rebinding ---------------------------------------------------------------


## Binds `event` to `action` for the event's device, replacing the action's
## previous binding for that device. If another rebindable action used
## `event`, it gets `action`'s previous binding instead (a swap). Goes through
## SettingsManager.set_setting(), so `persist = false` previews it.
static func bind(action: String, event: InputEvent, persist := true) -> void:
	var device := device_of(event)
	var text := serialize(event)
	if device == -1 or text == "":
		return
	var old: InputEvent = event_for(action, device)
	var old_text := serialize(old) if old else ""
	if old_text == text:
		return

	for other in REBINDABLE:
		if other == action:
			continue
		var other_texts := serialize_all(InputMap.action_get_events(other))
		if other_texts.has(text):
			other_texts.erase(text)
			if old_text != "":
				other_texts.append(old_text)
			SettingsManager.set_setting("input", other, other_texts, persist)

	var texts := serialize_all(InputMap.action_get_events(action))
	if old_text != "":
		texts.erase(old_text)
	texts.append(text)
	SettingsManager.set_setting("input", action, texts, persist)


## Makes a captured event bindable: device -1 (any controller), sticks snapped
## to -1/+1, keys by physical position. Null if it can't be bound.
static func normalize(event: InputEvent) -> InputEvent:
	if event is InputEventJoypadMotion and absf(event.axis_value) < AXIS_THRESHOLD:
		return null
	if device_of(event) == -1:
		return null
	return deserialize(serialize(event))
