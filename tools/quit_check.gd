extends SceneTree
## Smoke check run by tools/check.sh: plays a sound and quits through
## GameState.quit() while it's still playing. Godot must not report leaked
## resources at exit (check.sh scans the log for ERROR lines).
##
##   godot --headless --script res://tools/quit_check.gd


func _init() -> void:
	create_timer(10.0).timeout.connect(func(): quit(1))  # watchdog
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Autoload names aren't globals in a --script harness; fetch the nodes.
	root.get_node("Audio").play(&"ui.hover")
	await process_frame
	root.get_node("GameState").quit()
