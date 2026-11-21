class_name MachineState
extends Node
## One state of a StateMachine. Add MachineState nodes as children of a StateMachine;
## the node's name is the state's name (&"Idle", &"Walk").
##
## Override what you need. The machine calls these only on the current state:
##
##   func enter(previous: StringName, data: Dictionary) -> void
##   func exit(next: StringName) -> void
##   func update(delta: float) -> void            # _process
##   func physics_update(delta: float) -> void    # _physics_process
##   func handle_input(event: InputEvent) -> void # _unhandled_input
##
## Switch with transition_to(&"Walk"). `target` is the node the machine
## controls (the machine's parent unless set), e.g. the player.

## The machine this state belongs to (set before enter() is first called).
var machine: StateMachine
## The node the machine controls.
var target: Node


## Called when the machine switches to this state. `data` is whatever the
## caller passed to transition_to().
func enter(_previous: StringName, _data: Dictionary) -> void:
	pass


## Called when the machine leaves this state, before the next one enters.
func exit(_next: StringName) -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass


## Shortcut for machine.transition_to().
func transition_to(state_name: StringName, data: Dictionary = {}) -> void:
	machine.transition_to(state_name, data)


func is_current() -> bool:
	return machine != null and machine.current == self
