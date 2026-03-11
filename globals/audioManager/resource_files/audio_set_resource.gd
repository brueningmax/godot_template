@tool
extends Resource
class_name AudioSet

@export_category("Identification")

## ID of this sound event within its registry.
## Example: "step", "jump.land", "ui.click".
## The registry usually prefixes a namespace like "move.step".
@export var id: StringName


@export_category("Content")

## Variations of this sound. One cue is picked each time the set is played.
@export var cues: Array[AudioCue] = []


@export_category("Routing")

## Target audio bus for all cues in this set (e.g. "SFX", "UI", "Ambient", "Music").
## This list is populated from the current Audio Bus Layout (AudioServer).
var bus_name: StringName = &"SFX"


# Internal: remembers last chosen index to reduce immediate repeats.
var _last_idx := -1


## Builds a dynamic dropdown for `bus_name` based on current AudioServer buses.
## This runs in the editor because the script is marked with @tool.
func _get_property_list() -> Array:
	var bus_names: PackedStringArray = []
	for i in range(AudioServer.bus_count):
		bus_names.append(AudioServer.get_bus_name(i))

	var hint := ",".join(bus_names)
	if hint.is_empty():
		hint = "Master"

	return [
		{
			"name": "bus_name",
			"type": TYPE_STRING_NAME,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": hint,
			"usage": PROPERTY_USAGE_DEFAULT
		}
	]

func _get(property: StringName):
	if property == &"bus_name":
		return bus_name
	return null

func _set(property: StringName, value) -> bool:
	if property == &"bus_name":
		bus_name = value
		emit_changed()
		return true
	return false


@export_category("Playback")

## Picks one cue from the set.
## Current behavior: random choice with "no immediate repeat" when possible.
func pick() -> AudioCue:
	if cues.is_empty():
		return null
	if cues.size() == 1:
		_last_idx = 0
		return cues[0]

	var idx := randi() % cues.size()
	if idx == _last_idx:
		idx = (idx + 1) % cues.size()

	_last_idx = idx
	return cues[idx]
