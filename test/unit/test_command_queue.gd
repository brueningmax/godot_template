extends GutTest
## CommandQueue: order, push_front, awaiting, re-entrancy, cancel, undo.


## Records its name into `log` when it runs; can wait and add follow-ups.
class Rec:
	extends Command
	var label: String
	var log: Array
	var wait := 0.0
	var fronts: Array = []  # pushed to the front while running
	var backs: Array = []  # enqueued while running
	var undone := false

	func _init(name: String, into: Array, seconds := 0.0) -> void:
		label = name
		log = into
		wait = seconds

	func execute() -> void:
		log.append(label)
		if wait > 0.0:
			await Engine.get_main_loop().create_timer(wait).timeout
			if cancelled:
				log.append(label + " cancelled")
				return
			log.append(label + " done")
		for c in fronts:
			queue.push_front(c)
		for c in backs:
			queue.enqueue(c)

	func can_undo() -> bool:
		return true

	func undo() -> void:
		undone = true
		log.append("undo " + label)

	func describe() -> String:
		return label


func test_runs_in_order() -> void:
	var log := []
	var q := CommandQueue.new()
	q.enqueue_all([Rec.new("a", log), Rec.new("b", log)])
	q.enqueue(Rec.new("c", log))
	await q.run()
	assert_eq(log, ["a", "b", "c"])
	assert_eq(q.size(), 0)
	assert_false(q.is_running())


func test_waits_for_awaiting_command() -> void:
	var log := []
	var q := CommandQueue.new()
	q.enqueue(Rec.new("slow", log, 0.1))
	q.enqueue(Rec.new("next", log))
	await q.run()
	assert_eq(log, ["slow", "slow done", "next"], "next starts after slow finished")


func test_push_front_runs_reactions_next_in_order() -> void:
	var log := []
	var q := CommandQueue.new()
	var play := Rec.new("play", log)
	var react_1 := Rec.new("react 1", log)
	react_1.fronts = [Rec.new("react 1a", log)]
	play.fronts = [react_1, Rec.new("react 2", log)]
	play.backs = [Rec.new("end of turn", log)]
	q.enqueue(play)
	q.enqueue(Rec.new("queued before", log))
	await q.run()
	assert_eq(log, ["play", "react 1", "react 1a", "react 2", "queued before", "end of turn"])


func test_push_front_while_idle_keeps_order() -> void:
	var log := []
	var q := CommandQueue.new()
	q.enqueue(Rec.new("c", log))
	q.push_front(Rec.new("a", log))
	q.push_front(Rec.new("b", log))
	await q.run()
	assert_eq(log, ["a", "b", "c"])


func test_run_while_running_is_ignored() -> void:
	var log := []
	var q := CommandQueue.new()
	q.enqueue(Rec.new("slow", log, 0.05))
	q.run()
	assert_true(q.is_running())
	q.enqueue(Rec.new("added", log))
	q.run()  # must not start a second loop
	await wait_until(func(): return not q.is_running(), 2.0)
	assert_eq(log, ["slow", "slow done", "added"])


func test_signals() -> void:
	var q := CommandQueue.new()
	watch_signals(q)
	var a := Rec.new("a", [])
	q.enqueue(a)
	await q.run()
	assert_signal_emitted_with_parameters(q, "command_started", [a])
	assert_signal_emitted_with_parameters(q, "command_finished", [a])
	assert_signal_emit_count(q, "queue_empty", 1)


func test_cancel_stops_after_current() -> void:
	var log := []
	var q := CommandQueue.new()
	q.enqueue(Rec.new("slow", log, 0.1))
	q.enqueue(Rec.new("never", log))
	q.run()
	await wait_process_frames(1)
	q.cancel()
	await wait_until(func(): return not q.is_running(), 2.0)
	assert_eq(log, ["slow", "slow cancelled"])


func test_clear_drops_pending() -> void:
	var log := []
	var q := CommandQueue.new()
	q.enqueue_all([Rec.new("a", log), Rec.new("b", log)])
	q.clear()
	await q.run()
	assert_eq(log, [])


func test_history_and_undo() -> void:
	var log := []
	var q := CommandQueue.new()
	q.history_limit = 2
	var a := Rec.new("a", log)
	var b := Rec.new("b", log)
	var c := Rec.new("c", log)
	q.enqueue_all([a, b, c])
	await q.run()
	assert_eq(q.history, [b, c] as Array[Command], "limited to 2")
	assert_true(await q.undo_last())
	assert_true(c.undone)
	assert_eq(q.history, [b] as Array[Command])


func test_auto_run() -> void:
	var log := []
	var q := CommandQueue.new()
	q.auto_run = true
	q.enqueue(Rec.new("a", log))
	await wait_until(func(): return log == ["a"], 1.0)
	assert_eq(log, ["a"])


func test_debug_command_lists_queues() -> void:
	var q := CommandQueue.new("Combat")
	q.enqueue(Rec.new("pending one", []))
	var out := Debug.execute("queue")
	assert_string_contains(out, "Combat: idle")
	assert_string_contains(out, "pending one")
