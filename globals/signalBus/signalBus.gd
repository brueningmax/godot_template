extends Node

signal player_died(reason: String)

func subscribe(signal_name: StringName, target: Node, method: StringName) -> void:
	if not has_signal(signal_name):
		push_error("SignalBus: Unknown signal '%s'" % signal_name)
		return

	var callable := Callable(target, method)

	if not is_connected(signal_name, callable):
		connect(signal_name, callable)

	target.tree_exited.connect(
		func():
			if is_connected(signal_name, callable):
				disconnect(signal_name, callable),
		CONNECT_ONE_SHOT
	)