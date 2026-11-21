class_name LoadingScreen
extends Control
## Shown by SceneManager while a scene loads for longer than
## SceneManager.loading_screen_delay. Restyle it freely: SceneManager only
## calls set_progress(), and only if the method exists.

@onready var _bar: ProgressBar = %Bar


## `value` is 0..1.
func set_progress(value: float) -> void:
	_bar.value = clampf(value, 0.0, 1.0) * 100.0


## Current progress, 0..1.
func get_progress() -> float:
	return _bar.value / 100.0
