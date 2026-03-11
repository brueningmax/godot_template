extends Node
class_name AudioManager


@export_category("Content")

## Audio registries that define all available sound sets.
## Each registry contributes a namespace (e.g. "move", "ui", "amb")
## and a collection of AudioSets.
@export var registries: Array[AudioRegistry] = []


@export_category("Voice Limiting")

## Per-bus voice limit configuration.
## Defines how many simultaneous voices are allowed per audio bus.
## When the limit is exceeded, the oldest voice is reused (stolen).
@export var bus_configs: Array[AudioBusConfig] = []


@export_category("Runtime State")

## Resolved lookup table:
## full audio ID (e.g. "move.step") -> AudioSet
var _sets: Dictionary = {} # Dictionary[StringName, AudioSet]

## Pool of reusable 2D AudioStreamPlayers per bus.
## Used for non-positional one-shot sounds (UI, global SFX).
var _pool_2d: Dictionary = {} # Dictionary[StringName, Array[AudioStreamPlayer]]

## Tracks when each 2D AudioStreamPlayer started playing.
## Used to determine which voice to steal.
var _started_at_msec: Dictionary = {} # Dictionary[int, int]

## Pool of reusable 3D AudioStreamPlayers per bus.
## Used for positional one-shot sounds.
var _pool_3d: Dictionary = {} # Dictionary[StringName, Array[AudioStreamPlayer3D]]

## Tracks when each 3D AudioStreamPlayer started playing.
## Used to determine which voice to steal.
var _started_at_msec_3d: Dictionary = {} # Dictionary[int, int]

## Persistent 3D players that follow scene nodes.
## Key: owner instance id
## Value: Dictionary[full_audio_id, AudioStreamPlayer3D]
##
## This is intentionally NOT pooled:
## persistent emitters map 1:1 to world objects (machines, wind zones, etc.).
var _follow_players: Dictionary = {}


@export_category("Music Layers")

## Default bus used for music layers when AudioSet.bus_name is empty.
## Usually "Music", but you can rename your buses and keep the system working.
@export var default_music_bus: StringName = &"Music"

## Default fade duration for music layer transitions.
## Used when fade_sec is not provided (or is negative).
@export_range(0.0, 10.0, 0.05) var default_music_fade_sec: float = 1.0

## Global trim applied to all music layers and stingers.
## Useful for balancing without touching every AudioCue volume.
@export_range(-30.0, 12.0, 0.1) var music_layers_volume_db: float = 0.0

## Per-layer A/B players for smooth transitions.
## layer_name -> [playerA, playerB]
##
## We use two players per layer so we can crossfade within the layer:
## - old layer track fades out
## - new layer track fades in
var _music_layers: Dictionary = {} # Dictionary[StringName, Array[AudioStreamPlayer]]

## Which player is currently active per layer.
## layer_name -> 0 or 1
var _music_layer_active_idx: Dictionary = {}

## Active tween per layer (used to cancel previous fades).
## layer_name -> Tween
var _music_layer_tweens: Dictionary = {}

## Dedicated one-shot player for stingers (victory hits, accents, etc.)
## Plays on top of all layers without interrupting them.
var _music_stinger: AudioStreamPlayer


@export_category("Lifecycle")

## Initializes the audio system:
## - Builds the audio set lookup table
## - Initializes per-bus voice pools
## - Initializes music stinger playback
func _ready() -> void:
	_rebuild_index()
	_init_voice_pools()
	_init_music_layers()


## Creates the dedicated player used for "stingers" (one-shots over music).
## Layers themselves are created lazily when first referenced.
func _init_music_layers() -> void:
	_music_stinger = AudioStreamPlayer.new()
	_music_stinger.name = "MusicStinger"
	_music_stinger.bus = String(default_music_bus)
	_music_stinger.volume_db = 0.0
	add_child(_music_stinger)



@export_category("Registry Resolution")

## Builds the internal lookup table of all audio sets from all registries.
## Also validates that referenced audio buses exist.
func _rebuild_index() -> void:
	_sets.clear()

	for reg in registries:
		if reg == null:
			continue

		## Registry returns a map of full_id -> AudioSet
		var map: Dictionary = reg.build_map()

		for id in map.keys():
			if _sets.has(id):
				push_warning("AudioManager: duplicate audio id '%s' (keeping first)" % [id])
				continue

			var audio_set: AudioSet = map[id]
			_sets[id] = audio_set

			## Warn early if the set references a non-existent bus
			if audio_set != null \
			and audio_set.bus_name != StringName() \
			and not _bus_exists(audio_set.bus_name):
				push_warning(
					"AudioManager: AudioSet '%s' references missing bus '%s'"
					% [id, audio_set.bus_name]
				)


@export_category("Voice Pool Initialization")

## Creates per-bus pools of AudioStreamPlayers based on configured limits.
## Separate pools are created for 2D and 3D one-shot playback.
func _init_voice_pools() -> void:
	_pool_2d.clear()
	_pool_3d.clear()
	_started_at_msec.clear()
	_started_at_msec_3d.clear()

	var limits := _get_bus_limits()

	for bus_name in limits.keys():
		var max_voices: int = limits[bus_name]
		if max_voices <= 0:
			continue

		## 2D voice pool (non-positional)
		var arr2: Array[AudioStreamPlayer] = []
		for i in max_voices:
			var p2 := AudioStreamPlayer.new()
			p2.bus = String(bus_name)
			add_child(p2)
			arr2.append(p2)
			_started_at_msec[p2.get_instance_id()] = 0
		_pool_2d[bus_name] = arr2

		## 3D voice pool (positional one-shots)
		var arr3: Array[AudioStreamPlayer3D] = []
		for i in max_voices:
			var p3 := AudioStreamPlayer3D.new()
			p3.bus = String(bus_name)
			add_child(p3)
			arr3.append(p3)
			_started_at_msec_3d[p3.get_instance_id()] = 0
		_pool_3d[bus_name] = arr3


@export_category("Bus Configuration")

## Returns a map of bus_name -> max_voices.
## Uses sensible defaults and allows overrides via AudioBusConfig resources.
func _get_bus_limits() -> Dictionary:
	## Defaults for common bus layouts.
	## Adjust these or rely entirely on bus_configs overrides.
	var limits := {
		&"UI": 5,
		&"SFX": 12,
		&"Ambient": 4,
		&"Music": 2,
	}

	## Override / extend from inspector configs.
	for cfg in bus_configs:
		if cfg == null:
			continue
		if cfg.bus_name == StringName():
			continue
		limits[cfg.bus_name] = cfg.max_voices

	return limits


@export_category("Playback")

## Plays a non-positional (2D) one-shot sound.
## Intended for UI, global feedback, and non-spatial SFX.
func play(id: StringName, vol_db_offset := 0.0) -> void:
	var audio_set := _get_set_or_warn(id)
	if audio_set == null:
		return

	var cue := audio_set.pick()
	if cue == null or cue.stream == null:
		return

	var bus_name := _resolve_bus(audio_set)
	var p := _get_voice_2d(bus_name)
	if p == null:
		return

	_apply_cue_to_player_2d(p, bus_name, cue, vol_db_offset)
	p.play()
	_started_at_msec[p.get_instance_id()] = Time.get_ticks_msec()


## Plays a positional (3D) one-shot sound at a world position.
## Intended for impacts, pickups, explosions, etc.
func play_at(id: StringName, world_pos: Vector3, vol_db_offset := 0.0) -> void:
	var audio_set := _get_set_or_warn(id)
	if audio_set == null:
		return

	var cue := audio_set.pick()
	if cue == null or cue.stream == null:
		return

	var bus_name := _resolve_bus(audio_set)
	var p := _get_voice_3d(bus_name)
	if p == null:
		return

	_apply_cue_to_player_3d(p, bus_name, cue, vol_db_offset)
	p.global_position = world_pos
	p.play()

	_started_at_msec_3d[p.get_instance_id()] = Time.get_ticks_msec()


## Plays a 3D sound that follows a Node3D.
## Intended for persistent emitters like machine hums or wind sources.
##
## Returns the AudioStreamPlayer3D so callers can stop or tweak it later.
## This does NOT use pooling; it attaches the player to the owner node.
func play_follow(
	id: StringName,
	sound_owner: Node3D,
	vol_db_offset := 0.0,
	autoplay := true
) -> AudioStreamPlayer3D:
	if sound_owner == null:
		return null

	var audio_set := _get_set_or_warn(id)
	if audio_set == null:
		return null

	var cue := audio_set.pick()
	if cue == null or cue.stream == null:
		return null

	var owner_id := sound_owner.get_instance_id()
	var per_owner: Dictionary = _follow_players.get(owner_id, {})

	## Reuse existing follow player for this (sound_owner, id) pair
	var existing: AudioStreamPlayer3D = per_owner.get(id)
	if existing != null and is_instance_valid(existing):
		_apply_cue_to_player_3d(existing, _resolve_bus(audio_set), cue, vol_db_offset)
		if autoplay and not existing.playing:
			existing.play()
		_follow_players[owner_id] = per_owner
		return existing

	## Create a new follow player and attach it to the sound_owner
	var p := AudioStreamPlayer3D.new()
	p.name = "FollowAudio_%s" % String(id)
	sound_owner.add_child(p)

	_apply_cue_to_player_3d(p, _resolve_bus(audio_set), cue, vol_db_offset)

	per_owner[id] = p
	_follow_players[owner_id] = per_owner

	## Cleanup mapping when the sound_owner leaves the scene tree
	sound_owner.tree_exited.connect(func():
		_follow_players.erase(owner_id)
	)

	if autoplay:
		p.play()

	return p


@export_category("Music Playback")

## Starts or switches a looping music layer by ID, crossfading within that layer.
##
## Example usage:
##   Audio.music_layer_to(&"bed", &"music.flow.base", 1.5)
##   Audio.music_layer_to(&"drums", &"music.flow.drums", 1.0)
##
## Notes:
## - Each layer has two players (A/B) so the old track can fade out while new fades in.
## - This is layered music, not beat-locked. If you later need bar/beat sync, we can extend it.
func music_layer_to(
	layer: StringName,
	id: StringName,
	fade_sec: float = -1.0,
	target_db_override: float = NAN
) -> void:
	if fade_sec < 0.0:
		fade_sec = default_music_fade_sec

	var audio_set := _get_set_or_warn(id)
	if audio_set == null:
		return

	var cue := audio_set.pick()
	if cue == null or cue.stream == null:
		return

	_ensure_music_layer(layer)

	var players: Array[AudioStreamPlayer] = _music_layers[layer]
	var active_idx: int = int(_music_layer_active_idx.get(layer, 0))
	var from_p := players[active_idx]
	var to_idx := 1 - active_idx
	var to_p := players[to_idx]

	## Resolve bus for music layer (fallback to default_music_bus)
	var bus_name := audio_set.bus_name
	if bus_name == StringName():
		bus_name = default_music_bus

	## Configure incoming player
	to_p.stop()
	to_p.bus = String(bus_name)
	to_p.stream = cue.stream
	to_p.pitch_scale = 1.0
	to_p.volume_db = -80.0
	to_p.play()

	## Compute target dB (cue volume + global trim, unless override is passed)
	var target_db := cue.volume_db + music_layers_volume_db
	if not is_nan(target_db_override):
		target_db = target_db_override

	## Cancel any in-progress fade for this layer
	_kill_layer_tween(layer)

	## Crossfade old -> new
	var tw := create_tween()
	tw.set_parallel(true)

	if from_p.playing:
		tw.tween_property(from_p, "volume_db", -80.0, fade_sec)
	else:
		from_p.volume_db = -80.0

	tw.tween_property(to_p, "volume_db", target_db, fade_sec)

	## Finalize: stop old, remember which player is active for this layer
	tw.set_parallel(false)
	tw.tween_callback(func():
		from_p.stop()
		from_p.volume_db = -80.0
		_music_layer_active_idx[layer] = to_idx
	)

	_music_layer_tweens[layer] = tw


## Smoothly changes a layer’s volume (intensity) without switching its stream.
## Perfect for "flow" systems where drums ramp up/down.
func music_layer_gain(
	layer: StringName,
	target_db: float,
	fade_sec: float = -1.0
) -> void:
	if fade_sec < 0.0:
		fade_sec = default_music_fade_sec

	## Nothing to adjust if the layer hasn't been created/started
	if not _music_layers.has(layer):
		return

	var players: Array[AudioStreamPlayer] = _music_layers[layer]
	var active_idx: int = int(_music_layer_active_idx.get(layer, 0))
	var p := players[active_idx]

	if not p.playing:
		return

	_kill_layer_tween(layer)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target_db, fade_sec)
	_music_layer_tweens[layer] = tw


## Fades out and stops a layer.
func music_layer_stop(layer: StringName, fade_sec: float = -1.0) -> void:
	if fade_sec < 0.0:
		fade_sec = default_music_fade_sec

	if not _music_layers.has(layer):
		return

	var players: Array[AudioStreamPlayer] = _music_layers[layer]
	var active_idx: int = int(_music_layer_active_idx.get(layer, 0))
	var p := players[active_idx]

	if not p.playing:
		return

	_kill_layer_tween(layer)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -80.0, fade_sec)
	tw.tween_callback(func():
		p.stop()
		p.volume_db = -80.0
	)
	_music_layer_tweens[layer] = tw


## Plays a one-shot "stinger" over the currently running layers.
## Examples: victory hits, flow tier up accents, dramatic punches.
func music_stinger(id: StringName, vol_db_offset := 0.0) -> void:
	var audio_set := _get_set_or_warn(id)
	if audio_set == null:
		return

	var cue := audio_set.pick()
	if cue == null or cue.stream == null:
		return

	var bus_name := audio_set.bus_name
	if bus_name == StringName():
		bus_name = default_music_bus

	_music_stinger.bus = String(bus_name)
	_music_stinger.stream = cue.stream
	_music_stinger.volume_db = cue.volume_db + music_layers_volume_db + vol_db_offset
	_music_stinger.pitch_scale = 1.0

	_music_stinger.stop()
	_music_stinger.play()


@export_category("Voice Pooling")

## Returns an available pooled 2D AudioStreamPlayer for a given bus.
## Reuses idle players or steals the oldest active one if necessary.
func _get_voice_2d(bus_name: StringName) -> AudioStreamPlayer:
	var arr: Array = _pool_2d.get(bus_name, [])

	## Fallback: if bus wasn’t configured, create a tiny pool on-demand
	if arr.is_empty():
		var p := AudioStreamPlayer.new()
		p.bus = String(bus_name)
		add_child(p)
		_pool_2d[bus_name] = [p]
		_started_at_msec[p.get_instance_id()] = 0
		return p

	## Prefer idle
	for p in arr:
		if not p.playing:
			return p

	## Otherwise steal oldest
	var oldest: AudioStreamPlayer = arr[0]
	var oldest_t := int(_started_at_msec.get(oldest.get_instance_id(), 0))
	for p in arr:
		var t := int(_started_at_msec.get(p.get_instance_id(), 0))
		if t < oldest_t:
			oldest = p
			oldest_t = t

	oldest.stop()
	return oldest


## Returns an available pooled 3D AudioStreamPlayer for a given bus.
## Reuses idle players or steals the oldest active one if necessary.
func _get_voice_3d(bus_name: StringName) -> AudioStreamPlayer3D:
	var arr: Array = _pool_3d.get(bus_name, [])

	## Fallback: if bus wasn’t configured, create a tiny pool on-demand
	if arr.is_empty():
		var p := AudioStreamPlayer3D.new()
		p.bus = String(bus_name)
		add_child(p)
		_pool_3d[bus_name] = [p]
		_started_at_msec_3d[p.get_instance_id()] = 0
		return p

	## Prefer idle
	for p in arr:
		if not p.playing:
			return p

	## Otherwise steal oldest
	var oldest: AudioStreamPlayer3D = arr[0]
	var oldest_t := int(_started_at_msec_3d.get(oldest.get_instance_id(), 0))
	for p in arr:
		var t := int(_started_at_msec_3d.get(p.get_instance_id(), 0))
		if t < oldest_t:
			oldest = p
			oldest_t = t

	oldest.stop()
	return oldest


@export_category("Helpers")

## Resolves an AudioSet by ID and warns if it does not exist.
func _get_set_or_warn(id: StringName) -> AudioSet:
	var audio_set: AudioSet = _sets.get(id)
	if audio_set == null:
		push_warning("AudioManager: unknown id '%s'" % [id])
	return audio_set


## Resolves the target bus for an AudioSet with a safe fallback.
## Used by one-shot systems (2D/3D) and follow emitters.
func _resolve_bus(audio_set: AudioSet) -> StringName:
	var bus_name: StringName = audio_set.bus_name
	if bus_name == StringName():
		bus_name = &"SFX"
	return bus_name


## Applies cue parameters to a 2D AudioStreamPlayer.
func _apply_cue_to_player_2d(
	p: AudioStreamPlayer,
	bus_name: StringName,
	cue: AudioCue,
	vol_db_offset: float
) -> void:
	p.bus = String(bus_name)
	p.stream = cue.stream
	p.volume_db = cue.volume_db + vol_db_offset

	var pitch := cue.pitch
	if cue.random_pitch_range > 0.0:
		pitch += randf_range(-cue.random_pitch_range, cue.random_pitch_range)
	p.pitch_scale = max(0.01, pitch)


## Applies cue parameters to a 3D AudioStreamPlayer.
func _apply_cue_to_player_3d(
	p: AudioStreamPlayer3D,
	bus_name: StringName,
	cue: AudioCue,
	vol_db_offset: float
) -> void:
	p.bus = String(bus_name)
	p.stream = cue.stream
	p.volume_db = cue.volume_db + vol_db_offset

	var pitch := cue.pitch
	if cue.random_pitch_range > 0.0:
		pitch += randf_range(-cue.random_pitch_range, cue.random_pitch_range)
	p.pitch_scale = max(0.01, pitch)


## Ensures a named music layer exists.
## Creates two 2D players (A/B) for smooth crossfades inside that layer.
func _ensure_music_layer(layer: StringName) -> void:
	if _music_layers.has(layer):
		return

	var a := AudioStreamPlayer.new()
	a.name = "MusicLayer_%s_A" % String(layer)
	a.bus = String(default_music_bus)
	a.volume_db = -80.0
	add_child(a)

	var b := AudioStreamPlayer.new()
	b.name = "MusicLayer_%s_B" % String(layer)
	b.bus = String(default_music_bus)
	b.volume_db = -80.0
	add_child(b)

	_music_layers[layer] = [a, b]
	_music_layer_active_idx[layer] = 0


## Cancels any active fade tween for a given music layer.
## Called before applying new fades so layers feel responsive.
func _kill_layer_tween(layer: StringName) -> void:
	var tw: Tween = _music_layer_tweens.get(layer)
	if tw != null and is_instance_valid(tw):
		tw.kill()
	_music_layer_tweens.erase(layer)


@export_category("Validation")

## Checks whether a given audio bus exists in the current AudioServer layout.
func _bus_exists(bus_name: StringName) -> bool:
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i) == String(bus_name):
			return true
	return false
