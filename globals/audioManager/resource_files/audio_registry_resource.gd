extends Resource
class_name AudioRegistry

@export_category("Identification")

## Namespace prefix for all audio sets in this registry.
## Used to build fully-qualified audio IDs like:
##   "move.step", "ui.click", "amb.wind"
@export var name_space: StringName # e.g. "move", "ui", "amb"


@export_category("Content")

## Collection of AudioSets that belong to this namespace.
## Each AudioSet contributes one or more playable sound variations.
@export var audio_sets: Array[AudioSet] = []


@export_category("Runtime")

## Builds a lookup table mapping full audio IDs to AudioSet resources.
## Called by the AudioManager during startup.
##
## Example output:
## {
##   "move.step": AudioSet,
##   "ui.click": AudioSet
## }
func build_map() -> Dictionary:
	var map := {}

	for audio_set in audio_sets:
		if audio_set == null or audio_set.id == StringName():
			continue

		var full_id := StringName("%s.%s" % [name_space, audio_set.id])
		map[full_id] = audio_set

		## Also register individually named cues as single-cue AudioSet wrappers.
		## Allows addressing a specific cue by ID, e.g. "music.combat.main_theme".
		## Only cues with a non-empty id are registered; unnamed cues are unaffected.
		for cue in audio_set.cues:
			if cue == null or cue.id == StringName():
				continue
			var cue_full_id := StringName("%s.%s.%s" % [name_space, audio_set.id, cue.id])
			var wrapper := AudioSet.new()
			wrapper.id = cue.id
			wrapper.bus_name = audio_set.bus_name
			wrapper.cues = [cue]
			map[cue_full_id] = wrapper

	return map
