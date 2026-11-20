extends Node
## Global signals for events that many unrelated systems care about.
##
## Use the typed form so typos fail when the script is parsed:
##   SignalBus.scene_change_finished.connect(_on_scene_change_finished)
##   SignalBus.pause_toggled.emit(true)
##
## Keep this script free of references to SceneRegistry or game classes.
## SignalBus is the first autoload: anything it references is compiled before
## the other autoloads exist. That's why scene keys below are plain ints.

# --- Scenes -----------------------------------------------------------------

## A scene change has begun. `to_scene_key` is a SceneRegistry.SceneKey value.
signal scene_change_started(to_scene_key: int)

## A scene change has finished; `new_scene` is the scene now shown.
signal scene_change_finished(new_scene: Node)

# --- Settings ---------------------------------------------------------------

## A setting was changed through SettingsManager.set_setting().
signal setting_changed(section: String, key: String, value: Variant)

# --- Game state -------------------------------------------------------------

## The game was paused or resumed.
signal pause_toggled(is_paused: bool)

# --- Game -------------------------------------------------------------------
# Add your game's global signals here, e.g.:
# signal player_died(reason: String)
