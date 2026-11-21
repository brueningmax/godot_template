class_name StateMachine
extends Node
## A finite state machine made of nodes: every child MachineState is a state, named
## after its node. Only the current state gets update / physics_update /
## handle_input calls.
##
##   Player (CharacterBody2D)
##     StateMachine       initial_state = Idle
##       Idle  (MachineState)
##       Walk  (MachineState)
##       Jump  (MachineState)
##
## Change state from a state (transition_to(&"Jump")) or from outside
## ($StateMachine.transition_to(&"Hurt", {"damage": 3})). A transition asked
## for while one is in progress (e.g. from inside enter()) runs right after it,
## so enter()/exit() calls never interleave.
##
## Debugging: transitions are logged at debug level (category State), and the
## console command `states` lists every machine with its current state.

## Emitted after a transition: `from` has exited and `to` has entered.
signal state_changed(from: StringName, to: StringName)

const GROUP := &"state_machines"

static var _command_registered := false

## State entered when the machine is ready. Empty = the first child MachineState.
@export var initial_state: MachineState
## Node the states control. Empty = this machine's parent.
@export var target: Node
## How many previous state names `history` keeps.
@export var history_limit := 10

## The current state, or null before the machine is ready.
var current: MachineState = null
## Names of earlier states, oldest first.
var history: Array[StringName] = []

var _states: Dictionary[StringName, MachineState] = {}
var _transitioning := false
var _queued: Array = []  # [[name, data], ...] asked for during a transition


func _ready() -> void:
	add_to_group(GROUP)
	if target == null:
		target = get_parent()
	for child in get_children():
		if child is MachineState:
			_states[StringName(child.name)] = child
			child.machine = self
			child.target = target
	if _states.is_empty():
		Log.warn(&"State", "%s has no MachineState children" % get_path())
		return
	if initial_state == null:
		initial_state = _states.values()[0]
	_register_debug_command()
	_enter(initial_state, &"", {})


func _process(delta: float) -> void:
	if current:
		current.update(delta)


func _physics_process(delta: float) -> void:
	if current:
		current.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current:
		current.handle_input(event)


# --- Public API -------------------------------------------------------------------


## Switches to the state named `state_name`, passing `data` to its enter().
## Switching to the current state does nothing unless `reenter` is true.
func transition_to(state_name: StringName, data: Dictionary = {}, reenter := false) -> void:
	if not _states.has(state_name):
		Log.error(&"State", "%s: no state '%s'" % [get_path(), state_name])
		return
	if _transitioning:
		_queued.append([state_name, data, reenter])
		return
	if current and current.name == state_name and not reenter:
		return
	_transitioning = true
	var from := current_name()
	current.exit(state_name)
	history.append(from)
	while history.size() > history_limit:
		history.pop_front()
	_enter(_states[state_name], from, data)


## The current state's name, or &"" before the machine is ready.
func current_name() -> StringName:
	return StringName(current.name) if current else &""


## The previous state's name, or &"".
func previous_name() -> StringName:
	return history.back() if not history.is_empty() else &""


func has_state(state_name: StringName) -> bool:
	return _states.has(state_name)


func get_state(state_name: StringName) -> MachineState:
	return _states.get(state_name)


func is_in(state_name: StringName) -> bool:
	return current_name() == state_name


# --- Internals --------------------------------------------------------------------


func _enter(state: MachineState, from: StringName, data: Dictionary) -> void:
	_transitioning = true
	current = state
	Log.debug(&"State", "%s: %s -> %s" % [_label(), from, state.name])
	state.enter(from, data)
	_transitioning = false
	state_changed.emit(from, current_name())  # from is &"" for the initial state
	if not _queued.is_empty():
		var next: Array = _queued.pop_front()
		transition_to(next[0], next[1], next[2])


func _label() -> String:
	return "%s/%s" % [target.name if target else "?", name]


static func _register_debug_command() -> void:
	if _command_registered:
		return
	_command_registered = true
	Debug.register_command("states", _cmd_states, "List state machines and their states.")


static func _cmd_states(_args: PackedStringArray) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var lines := PackedStringArray()
	for node in tree.get_nodes_in_group(GROUP):
		var sm := node as StateMachine
		var before := ", ".join(sm.history.slice(-3))
		lines.append(
			(
				"%s: %s%s"
				% [sm.get_path(), sm.current_name(), "  (before: %s)" % before if before else ""]
			)
		)
	return "\n".join(lines) if not lines.is_empty() else "no state machines"
