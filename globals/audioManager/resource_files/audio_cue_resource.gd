extends Resource
class_name AudioCue

@export_category("Identification")

## Optional identifier for debugging or tooling.
## Not required for playback, since AudioSets provide the lookup key.
@export var id: StringName


@export_category("Playback")

## The audio stream to be played (WAV, OGG, etc.).
@export var stream: AudioStream

## Volume offset in decibels for this specific variation.
## 0 = unchanged, negative = quieter, positive = louder.
## numbers are chosen since decibels are relative. +6 is double as loud.
@export_range(-80.0, 12.0, 0.1)
var volume_db: float = 0.0

## Base pitch multiplier.
## 1.0 = normal pitch, < 1.0 = lower, > 1.0 = higher.
@export_range(0.1, 3.0, 0.01)
var pitch: float = 1.0


@export_category("Variation & Anti-Spam")

## Minimum time (in seconds) before this cue can be played again.
## Useful to prevent rapid re-triggering (e.g. UI hover spam or footsteps).
@export_range(0.0, 1.0, 0.01)
var cooldown_sec: float = 0.0

## Random pitch variation added on top of the base pitch.
## Example: 0.1 means pitch will vary by ±0.1 each time.
@export_range(0.0, 0.5, 0.01)
var random_pitch_range: float = 0.0
