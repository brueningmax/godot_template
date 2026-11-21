extends Node
## Autoload "GameFeel": small effects that make hits and actions feel solid.
##
##   GameFeel.shake(0.4)                 # screen shake (needs a CameraShaker)
##   GameFeel.hit_stop(0.06)             # freeze gameplay for a moment
##   GameFeel.flash($Sprite2D)           # flash a sprite white
##   GameFeel.punch($Button)             # quick scale pop
##
## Everything respects pause (no hit-stop while paused; flashes and punches
## freeze with their node) and the player's "Screen shake" setting
## (interface/screen_shake, 0 turns shaking off).

## Multiplies all shake() trauma. Follows the interface/screen_shake setting.
var shake_scale := 1.0

var _hit_stop_until_usec := 0
var _time_scale_before := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shake_scale = float(SettingsManager.get_setting("interface", "screen_shake", 1.0))
	SignalBus.setting_changed.connect(_on_setting_changed)
	_register_commands.call_deferred()


func _process(_delta: float) -> void:
	if _hit_stop_until_usec != 0 and Time.get_ticks_usec() >= _hit_stop_until_usec:
		_end_hit_stop()


# --- Shake ------------------------------------------------------------------------


## Adds `trauma` (0..1, typical hits 0.2–0.6) to every CameraShaker, scaled by
## the player's screen shake setting.
func shake(trauma: float) -> void:
	var amount := trauma * shake_scale
	if amount <= 0.0:
		return
	for shaker in get_tree().get_nodes_in_group(CameraShaker.GROUP):
		(shaker as CameraShaker).add_trauma(amount)


# --- Hit-stop ---------------------------------------------------------------------


## Freezes (or slows) gameplay for `duration` real seconds by setting
## Engine.time_scale to `time_scale`, then restores the previous scale. A
## second hit-stop during one extends it. Ignored while the game is paused.
func hit_stop(duration := 0.06, time_scale := 0.0) -> void:
	if get_tree().paused or duration <= 0.0:
		return
	if not is_hit_stopped():
		_time_scale_before = Engine.time_scale
	Engine.time_scale = clampf(time_scale, 0.0, _time_scale_before)
	var until := Time.get_ticks_usec() + int(duration * 1_000_000.0)
	_hit_stop_until_usec = maxi(_hit_stop_until_usec, until)


func is_hit_stopped() -> bool:
	return _hit_stop_until_usec != 0


func _end_hit_stop() -> void:
	_hit_stop_until_usec = 0
	Engine.time_scale = _time_scale_before


# --- Tweens on nodes --------------------------------------------------------------


## Tints `node` with `color` and fades back over `duration`. The default is
## an over-bright white, so the sprite flashes white. Returns the tween.
func flash(node: CanvasItem, color := Color(3, 3, 3), duration := 0.12) -> Tween:
	node.modulate = color
	var tween := node.create_tween()
	tween.tween_property(node, "modulate", Color.WHITE, duration)
	return tween


## Pops `node`'s scale up by `amount` and springs back (UI buttons, pickups,
## a card being played). Works on Node2D and Control. Returns the tween.
func punch(node: CanvasItem, amount := 0.2, duration := 0.18) -> Tween:
	var base := Vector2.ONE
	if node is Control:
		var control := node as Control
		control.pivot_offset = control.size / 2.0
	node.set("scale", base * (1.0 + amount))
	var tween := node.create_tween()
	tween.tween_property(node, "scale", base, duration).set_trans(Tween.TRANS_ELASTIC).set_ease(
		Tween.EASE_OUT
	)
	return tween


# --- Internals --------------------------------------------------------------------


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "interface" and key == "screen_shake":
		shake_scale = clampf(float(value), 0.0, 1.0)


func _register_commands() -> void:
	Debug.register_command("shake", _cmd_shake, "Shake the screen.", "[trauma 0..1]")
	Debug.register_command("hitstop", _cmd_hitstop, "Freeze gameplay briefly.", "[seconds]")


func _cmd_shake(args: PackedStringArray) -> String:
	var trauma := args[0].to_float() if not args.is_empty() else 0.5
	shake(trauma)
	var count := get_tree().get_nodes_in_group(CameraShaker.GROUP).size()
	return "shake %.2f (x%.2f setting) on %d camera(s)" % [trauma, shake_scale, count]


func _cmd_hitstop(args: PackedStringArray) -> String:
	var seconds := args[0].to_float() if not args.is_empty() else 0.1
	hit_stop(seconds)
	return "hit-stop %.2f s" % seconds
