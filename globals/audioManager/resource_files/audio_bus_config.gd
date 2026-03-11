@tool
extends Resource
class_name AudioBusConfig

@export_category("Bus Selection")

## Name of the audio bus this configuration applies to.
## The dropdown is populated from the current Audio Bus Layout (AudioServer).
## This must match an existing bus name exactly.
var bus_name: StringName = &"SFX"


@export_category("Voice Limiting")

## Maximum number of simultaneous AudioStreamPlayers allowed on this bus.
## When the limit is reached, the AudioManager will reuse (steal) the oldest voice.
##
## Typical values:
## - UI: 4–6
## - SFX: 8–16
## - Ambient: 2–4
## - Music: 1–2
@export_range(0, 64, 1)
var max_voices: int = 8


@export_category("Editor Integration")

## Builds a dynamic dropdown for `bus_name` based on the current AudioServer buses.
## This runs in the editor because the script is marked with @tool.
func _get_property_list() -> Array:
	var bus_names: PackedStringArray = []
	for i in range(AudioServer.bus_count):
		bus_names.append(AudioServer.get_bus_name(i))

	# Fallback if no buses are detected (should not normally happen)
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
