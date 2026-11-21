extends GutTest
## StateMachine + MachineState: initial state, transitions, data, callbacks,
## queued transitions, history, errors, debug command.


## Records every callback into the shared `log`.
class Rec:
	extends MachineState
	var log: Array
	var updates := 0
	var physics_updates := 0
	var inputs := 0
	## Transition to this state from inside enter() (tests queuing).
	var chain_to: StringName = &""

	func _init(state_name: String, into: Array) -> void:
		name = state_name
		log = into

	func enter(previous: StringName, data: Dictionary) -> void:
		log.append("enter %s from %s %s" % [name, previous, data])
		if chain_to != &"":
			var next := chain_to
			chain_to = &""
			transition_to(next)

	func exit(next: StringName) -> void:
		log.append("exit %s to %s" % [name, next])

	func update(_delta: float) -> void:
		updates += 1

	func physics_update(_delta: float) -> void:
		physics_updates += 1

	func handle_input(_event: InputEvent) -> void:
		inputs += 1


var _log: Array


func _machine(initial := "") -> StateMachine:
	_log = []
	var owner_node: Node = add_child_autofree(Node.new())
	owner_node.name = "Player"
	var sm := StateMachine.new()
	sm.name = "StateMachine"
	for state_name in ["Idle", "Walk", "Jump"]:
		sm.add_child(Rec.new(state_name, _log))
	if initial != "":
		sm.initial_state = sm.get_node(initial)
	owner_node.add_child(sm)  # _ready() enters the initial state
	return sm


func test_enters_first_state_by_default() -> void:
	var sm := _machine()
	assert_eq(sm.current_name(), &"Idle")
	assert_eq(_log, ["enter Idle from  {  }"])
	assert_eq(sm.current.target.name, &"Player", "target = machine's parent")


func test_initial_state_export() -> void:
	var sm := _machine("Walk")
	assert_eq(sm.current_name(), &"Walk")


func test_transition_order_and_data() -> void:
	var sm := _machine()
	watch_signals(sm)
	sm.transition_to(&"Jump", {"height": 2})
	assert_eq(
		_log, ["enter Idle from  {  }", "exit Idle to Jump", 'enter Jump from Idle { "height": 2 }']
	)
	assert_signal_emitted_with_parameters(sm, "state_changed", [&"Idle", &"Jump"])
	assert_true(sm.is_in(&"Jump"))
	assert_eq(sm.previous_name(), &"Idle")


func test_same_state_is_ignored_unless_reenter() -> void:
	var sm := _machine()
	sm.transition_to(&"Idle")
	assert_eq(_log.size(), 1)
	sm.transition_to(&"Idle", {}, true)
	assert_eq(_log.size(), 3, "exit + enter again")


func test_transition_from_enter_is_queued() -> void:
	var sm := _machine()
	(sm.get_state(&"Walk") as Rec).chain_to = &"Jump"
	sm.transition_to(&"Walk")
	assert_eq(sm.current_name(), &"Jump")
	assert_eq(
		_log.slice(1),
		[
			"exit Idle to Walk",
			"enter Walk from Idle {  }",
			"exit Walk to Jump",
			"enter Jump from Walk {  }",
		],
		"Walk fully entered before it exits"
	)


func test_only_current_state_is_updated() -> void:
	var sm := _machine()
	await wait_process_frames(3)
	await wait_physics_frames(3)
	var idle := sm.get_state(&"Idle") as Rec
	var walk := sm.get_state(&"Walk") as Rec
	assert_gt(idle.updates, 0)
	assert_gt(idle.physics_updates, 0)
	assert_eq(walk.updates, 0)
	sm._unhandled_input(InputEventAction.new())
	assert_eq(idle.inputs, 1)


func test_history_is_limited() -> void:
	var sm := _machine()
	sm.history_limit = 2
	for state_name in [&"Walk", &"Jump", &"Idle", &"Walk"]:
		sm.transition_to(state_name)
	assert_eq(sm.history, [&"Jump", &"Idle"] as Array[StringName])


func test_unknown_state_errors() -> void:
	var sm := _machine()
	sm.transition_to(&"Fly")
	assert_push_error("no state 'Fly'")
	assert_eq(sm.current_name(), &"Idle")


func test_debug_command() -> void:
	var sm := _machine()
	sm.transition_to(&"Walk")
	var out := Debug.execute("states")
	assert_string_contains(out, "StateMachine: Walk")
	assert_string_contains(out, "before: Idle")
