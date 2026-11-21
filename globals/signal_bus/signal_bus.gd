extends Node
## Global signals for events that many unrelated systems care about.
##
## Use the typed form so typos fail when the script is parsed:
##   SignalBus.scene_change_finished.connect(_on_scene_change_finished)
##   SignalBus.pause_toggled.emit(true)
##
## Scene keys below are ints (SceneRegistry.SceneKey values) for brevity.

# --- Scenes -----------------------------------------------------------------

## A scene change has begun. `to_scene_key` is a SceneRegistry.SceneKey value.
signal scene_change_started(to_scene_key: int)

## A scene change has finished; `new_scene` is the scene now shown.
signal scene_change_finished(new_scene: Node)

# --- Settings ---------------------------------------------------------------

## A setting was changed through SettingsManager.set_setting().
signal setting_changed(section: String, key: String, value: Variant)

# --- Game state -------------------------------------------------------------

## GameState changed. Both values are GameState.State (MENU, PLAYING, PAUSED, LOADING).
signal game_state_changed(new_state: int, old_state: int)

## The game was paused or resumed (emitted by GameState).
signal pause_toggled(is_paused: bool)

# --- Saves ------------------------------------------------------------------

## SaveManager wrote `slot`.
signal game_saved(slot: String)

## SaveManager loaded `slot` (after migrating it).
signal game_loaded(slot: String)

# --- Game -------------------------------------------------------------------
# Add your game's global signals here, e.g.:
# signal player_died(reason: String)
