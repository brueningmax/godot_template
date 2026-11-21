class_name Command
extends RefCounted
## One step of game logic for a CommandQueue: "draw a card", "deal 6 damage",
## "play the hit animation". Subclass it and override execute(), which may
## await (animations, timers, player input, other commands).
##
##   class DealDamage:
##       extends Command
##       var target: Unit
##       var amount: int
##
##       func execute() -> void:
##           target.health -= amount
##           await target.play_hit()
##           if target.health <= 0:
##               queue.push_front(Die.new(target))   # runs next, before the rest

## The queue running this command, set only while execute() runs. Use it to add
## follow-up commands: queue.push_front() for reactions, queue.enqueue() for
## things that happen after everything already queued.
var queue: CommandQueue
## Set by CommandQueue.cancel() while this command runs. Long commands can
## check it after an await and stop early.
var cancelled := false


## Does the work. May await; the queue waits for it to return.
func execute() -> void:
	pass


## Optional: reverses execute(). Only called if can_undo() is true.
func undo() -> void:
	pass


func can_undo() -> bool:
	return false


## Shown in logs, the history and the debug console. Defaults to the class name.
func describe() -> String:
	var script: Script = get_script()
	while script != null:
		if script.get_global_name() != &"":
			return script.get_global_name()
		script = script.get_base_script()
	return "Command"
