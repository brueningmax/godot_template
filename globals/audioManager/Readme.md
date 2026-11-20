# Modular Audio System (Godot 4)

A reusable, data-driven audio system with a clear separation between content, routing and playback policy. It's designed to be copied between projects with minimal setup and no hardcoded gameplay dependencies.

## Features

- Central `AudioManager` (autoloaded scene, global name `Audio`)
- Registries → Sets → Cues content structure
- 2D and 3D playback
- Per-bus voice limiting and pooling
- Scene-owned persistent 3D emitters
- Layered (adaptive) music and stingers
- Editor-friendly resources with tooltips and bus dropdowns
- Export-safe

## Core concepts

| Resource | Role |
| --- | --- |
| **AudioRegistry** | Groups related sets under a namespace (`move`, `ui`, `amb`). Organizational only; doesn't affect routing. |
| **AudioSet** | One logical sound event (`step`, `click`, `flow.base`). Picks the bus and holds one or more variations. |
| **AudioCue** | One playable variation: stream, volume trim, pitch, random pitch range, cooldown. |
| **AudioBusConfig** | Maximum simultaneous voices for one bus. |
| **AudioManager** | Global entry point: resolves IDs, enforces voice limits, pools players, runs music layers. |

## Files

```
globals/audioManager/
  audio_manager_node.tscn        # the autoload (assign registries here)
  audioManager.gd
  resource_files/
    audio_registry_resource.gd   # AudioRegistry
    audio_set_resource.gd        # AudioSet
    audio_cue_resource.gd        # AudioCue
    audio_bus_config.gd          # AudioBusConfig
resources/audio/
  bus_layout.tres                # project default bus layout
  audioRegistries/*.tres         # content
```

## Setup in a new project

This template already has all of this set up. The steps are for copying the system into another project.

1. **Copy** `globals/audioManager/` into the project.
2. **Create a bus layout:** open the **Audio** panel at the bottom of the editor and add buses, e.g. `UI`, `SFX`, `Ambient`, `Music`. Save it as `resources/audio/bus_layout.tres` and assign it in **Project Settings → Audio → Buses → Default Bus Layout**. Bus names are plain strings and must match exactly.
3. **Autoload** `audio_manager_node.tscn` with the name `Audio` (**Project Settings → Globals → Autoload**).

## Creating audio content

1. **Create an AudioRegistry** resource, set `name_space` (e.g. `ui`), and add sets to it.
2. **Create AudioSets** inside it: set the `id` (e.g. `click`), pick a bus from the dropdown, and add cues.
3. **Create AudioCues:** assign a stream and adjust the trim, pitch and random pitch.
4. **Register** the registry: add it to the `registries` array on `audio_manager_node.tscn`.

The final IDs are `<namespace>.<set_id>`, e.g. `ui.click`, `move.step`, `music.flow.base`. A cue with its own `id` can also be played on its own as `<namespace>.<set_id>.<cue_id>`.

## Playing sounds

```gdscript
# 2D one-shot (UI, global feedback). Optional dB offset.
Audio.play(&"ui.click")
Audio.play(&"move.step", -2.0)

# 3D one-shot at a world position (impacts, pickups).
Audio.play_at(&"sfx.explosion", global_position)

# 3D sound that follows a node (machine hum, engine). Returns the player.
var hum := Audio.play_follow(&"amb.machine_hum", self)
```

Follow emitters are attached to the owner node and aren't pooled, because they map 1:1 to world objects.

## Layered music

A *layer* is a named channel (`bed`, `base`, `drums`). Each layer has two internal players, so switching tracks crossfades within the layer.

```gdscript
Audio.music_layer_to(&"base", &"music.flow.base", 1.5)   # start / switch
Audio.music_layer_gain(&"drums", -12.0, 0.2)             # change intensity
Audio.music_layer_stop(&"drums", 0.8)                    # fade out
Audio.music_stinger(&"music.stinger.win", -3.0)          # one-shot over layers
```

Layers are fade-based, not beat-synced.

## Voice limiting

Default limits are `UI` 5, `SFX` 12, `Ambient` 4, `Music` 2. Override them with `AudioBusConfig` entries in `bus_configs`. When a bus is full, the **oldest** one-shot voice on it is reused. Follow emitters, music layers and stingers don't count towards the limits.

## Validation

- Unknown IDs log a warning and play nothing.
- Sets that reference a bus that doesn't exist are reported at startup.
- Buses without a config get a single player, created when first needed.
- `@tool` is used only for the inspector dropdowns and isn't needed at runtime.

## Known limitations

- `AudioCue.cooldown_sec` is defined but **not enforced** yet.
- `AudioSet.pick()` uses the global `randi()`, not `RngManager`, so variation picks aren't reproducible from the seed (usually what you want for audio).
