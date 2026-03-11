Modular Audio System (Godot 4)

A reusable, data-driven audio system for Godot 4 with a clear separation between content, routing, and playback policy.

The system is designed to be copied between projects with minimal setup and no hardcoded gameplay dependencies.

Features

• Central AudioManager (autoloaded scene)
• Registries → Sets → Cues structure
• 2D and 3D playback support
• Per-bus voice limiting and pooling
• Scene-owned persistent 3D emitters
• Layered music playback (adaptive music)
• Music stingers (one-shots over layers)
• Editor-friendly Resources with tooltips
• Dynamic audio bus dropdowns
• Export-safe and portable

Core Concepts

AudioRegistry
Groups related sounds under a namespace (for example: move, ui, amb). Registries are organizational only and do not control routing or playback.

AudioSet
Represents one logical sound event (for example: step, jump.land, ui.click, music.flow.base). A set defines which audio bus the sound is routed to and contains multiple variations.

AudioCue
One playable variation of a sound. Contains the actual audio stream and small per-variation adjustments like volume trim, pitch, random pitch range, and cooldown.

AudioBusConfig
Defines how many simultaneous voices are allowed per audio bus. Used by the AudioManager to enforce limits and prevent audio spam.

AudioManager
Global playback entry point. Resolves audio IDs, enforces per-bus voice limits, manages pooling, plays sounds, and manages music layers and stingers.

Recommended Folder Structure

res://audio_system/
• AudioManager.tscn
• AudioManager.gd
• AudioRegistry.gd
• AudioSet.gd
• AudioCue.gd
• AudioBusConfig.gd
• bus_layout.tres
• README.md

The folder name can be changed freely.

Setup in a New Project

Step 1 – Copy the system
Copy the entire audio_system folder into your new project.

Step 2 – Create and assign an Audio Bus Layout
Open Audio → Audio Bus Layout in the editor.
Add the buses you want to use (recommended: UI, SFX, Ambient, Music).
Save the layout as res://audio_system/bus_layout.tres.
Assign it in Project Settings → Audio → Default Bus Layout.

Bus names are string-based and must match exactly.

Step 3 – Autoload the AudioManager scene
Open Project Settings → Autoload.
Add the AudioManager scene with the name Audio and the path:

res://audio_system/AudioManager.tscn

This makes the system globally accessible.

Creating Audio Content

Create an AudioRegistry
Create a new AudioRegistry resource.
Set name_space to something like ui, move, amb, or music.
Add AudioSets to the registry.

Create an AudioSet
Create a new AudioSet resource.
Set the id (for example: click, step, jump.land, flow.base, flow.drums).
Select a target audio bus from the dropdown (populated from the Audio Bus Layout).
Add one or more AudioCues.

Create AudioCues
Create AudioCue resources.
Assign the audio stream.
Adjust volume trim, pitch, random pitch range, and optional cooldown.

Final audio IDs are built automatically as:

<namespace>.<set_id>

Examples:
ui.click
move.step
amb.wind
music.flow.base
music.flow.drums
music.stinger.win

Playing Sounds at Runtime

The AudioManager exposes multiple playback methods depending on intent.

2D one-shot (non-positional)
Used for UI, global feedback, and non-spatial sounds.

Audio.play(&"ui.click")
Audio.play(&"move.step", -2.0)

The optional second parameter is a volume offset in decibels applied at call-time.

3D one-shot at a world position
Used for impacts, explosions, pickups, or any sound that originates from a point in space.

Audio.play_at(&"sfx.explosion", global_position)

These sounds are spatialized and attenuated based on listener position.

3D sound that follows a scene node
Used for persistent world emitters such as machine hums, wind sources, or engines.

Audio.play_follow(&"amb.machine_hum", self)

This creates or reuses an AudioStreamPlayer3D attached to the target node and returns it so it can be stopped or adjusted later.

Scene-owned 3D emitters are intentionally not pooled, as they represent persistent world objects rather than spam-prone events.

Layered Music (Adaptive Music)

For adaptive music systems (ambient → base layer → drums → intensity ramps), AudioManager supports layered music playback.

A “layer” is a named channel (for example: bed, base, drums, high). Each layer uses two internal players (A/B) so switching a layer can crossfade smoothly.

Layers are not voice-limited through the pooling system because they are persistent by design and should not be stolen.

Start or switch a music layer
Audio.music_layer_to(&"base", &"music.flow.base", 1.5)
Audio.music_layer_to(&"drums", &"music.flow.drums", 1.0)

Adjust a layer’s intensity without switching tracks
This is ideal for flow-based systems where drums ramp up/down continuously.

Audio.music_layer_gain(&"drums", -12.0, 0.2)

Stop a layer
Audio.music_layer_stop(&"drums", 0.8)

Music Stingers (one-shots over layers)

Stingers are short one-shots that play over the currently running layers without interrupting them. Examples: victory hits, flow tier-up accents, dramatic punches.

Audio.music_stinger(&"music.stinger.win", -3.0)

Note on Sync
Layered playback here is fade-based and not beat-locked. For most games this sounds great with good fades. If you later need beat/bar-aligned transitions, the system can be extended with a shared transport or timing metadata.

Voice Limiting and Pooling

Voice limits are configured per audio bus using AudioBusConfig resources.

For each bus you can define how many simultaneous sounds are allowed.

When the limit is reached:
• For 2D and 3D one-shots, the oldest playing voice is reused (stolen)
• Persistent follow sounds are unaffected
• Music layers and stingers are unaffected (persistent systems)

Recommended starting values:
UI: 4–6
SFX: 8–16
Ambient: 2–4
Music: 1–2 (for general one-shots routed to Music; layered music uses dedicated players)

Pooling prevents node spam and keeps performance stable under heavy audio load.

Validation and Safety

• Missing audio IDs produce warnings
• Missing or misspelled bus names are detected at startup
• Unconfigured buses fall back safely
• 2D and 3D playback are explicitly separated
• All runtime logic is export-safe

Editor-only logic (@tool) is used exclusively for inspector UI and never required at runtime.

Export and Reuse

The system is fully export-safe on all platforms supported by Godot 4.

All configuration is stored in Resources and scenes, not editor state.

To reuse in another project:

Copy the audio_system folder
Assign the audio bus layout
Autoload AudioManager.tscn
Create new registries, sets, and cues

No code changes required.

Design Philosophy

AudioSets define intent
AudioCues define variation
Registries define organization
AudioManager defines policy

Use scene-owned players for persistent world sounds.
Use the AudioManager for events, limits, and consistency.
Use music layers for adaptive intensity systems.

Keep assets clean, routing explicit, and limits enforced at the system level.
