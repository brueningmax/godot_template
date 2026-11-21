class_name CommandQueue
extends RefCounted
## Runs Commands one after another. Each command finishes (including its
## awaits) before the next starts. Not an autoload: create one per context,
## e.g. one for a combat.
##
##   var queue := CommandQueue.new()
##   queue.enqueue(PlayCard.new(card))
##   await queue.run()          # until the queue is empty
##
## Order:
## - enqueue() adds at the end.
## - push_front() adds before everything already waiting. Several push_front()
##   calls in a row keep their order, so a command that pushes reactions A then
##   B gets A, B, then whatever was queued before.
## - Commands added while one runs follow these rules too, so reactions to a
##   command always run right after it.

signal command_started(command: Command)
signal command_finished(command: Command)
## The queue ran out of commands (also after cancel()).
signal queue_empty

static var _instances: Array[WeakRef] = []
static var _command_registered := false

## How many finished commands history keeps (for undo and debugging).
var history_limit := 50
## Start run() automatically when a command is added to an idle queue.
var auto_run := false
## Shown in logs and the debug console's `queue` command.
var debug_name := "CommandQueue"
## Finished commands, oldest first.
var history: Array[Command] = []

var _pending: Array[Command] = []
var _current: Command = null
var _running := false
# Where the next push_front() goes; reset when a command starts.
var _front_index := 0


func _init(name := "CommandQueue") -> void:
	debug_name = name
	_instances.append(weakref(self))
	_register_debug_command()


# --- Adding -----------------------------------------------------------------------


func enqueue(command: Command) -> void:
	_pending.append(command)
	_maybe_auto_run()


func enqueue_all(commands: Array) -> void:
	for command in commands:
		_pending.append(command)
	_maybe_auto_run()


## Runs `command` before everything already waiting (reactions, interrupts).
func push_front(command: Command) -> void:
	_pending.insert(mini(_front_index, _pending.size()), command)
	_front_index += 1
	_maybe_auto_run()


# --- Running ----------------------------------------------------------------------


## Runs commands until the queue is empty or cancel() is called. Calling it
## while it's already running does nothing (the running loop picks up new
## commands), so it's safe to call from inside a command.
func run() -> void:
	if _running:
		return
	_running = true
	while not _pending.is_empty():
		_current = _pending.pop_front()
		_front_index = 0
		_current.queue = self
		_current.cancelled = false
		Log.debug(&"Commands", "▶ %s" % _current.describe())
		command_started.emit(_current)
		await _current.execute()
		var done := _current
		_current = null
		done.queue = null  # history holds commands; don't let them hold us back
		_remember(done)
		command_finished.emit(done)
	_running = false
	_front_index = 0
	queue_empty.emit()


func is_running() -> bool:
	return _running


## The command executing right now, or null.
func current() -> Command:
	return _current


## Commands waiting to run, in the order they will run.
func pending() -> Array[Command]:
	return _pending.duplicate()


func size() -> int:
	return _pending.size()


## Removes every waiting command. The running one finishes normally.
func clear() -> void:
	_pending.clear()
	_front_index = 0


## Removes every waiting command and marks the running one `cancelled`, so it
## can stop early. run() returns once that command has returned.
func cancel() -> void:
	clear()
	if _current:
		_current.cancelled = true


# --- Undo -------------------------------------------------------------------------


## Undoes the most recent finished command that can be undone and removes it
## from history. Returns false if there's none, or while the queue runs.
func undo_last() -> bool:
	if _running:
		return false
	for i in range(history.size() - 1, -1, -1):
		var command := history[i]
		if command.can_undo():
			history.remove_at(i)
			Log.debug(&"Commands", "↶ %s" % command.describe())
			await command.undo()
			return true
	return false


func _remember(command: Command) -> void:
	history.append(command)
	while history.size() > history_limit:
		history.pop_front()


func _maybe_auto_run() -> void:
	if auto_run and not _running:
		run.call_deferred()


# --- Debug console ----------------------------------------------------------------


static func _register_debug_command() -> void:
	if _command_registered:
		return
	_command_registered = true
	Debug.register_command("queue", _cmd_queue, "Show command queues: running, pending, recent.")


static func _cmd_queue(_args: PackedStringArray) -> String:
	var lines := PackedStringArray()
	for ref in _instances.duplicate():
		var q: CommandQueue = ref.get_ref()
		if q == null:
			_instances.erase(ref)
			continue
		lines.append("%s: %s" % [q.debug_name, "running" if q.is_running() else "idle"])
		if q.current():
			lines.append("  now:     %s" % q.current().describe())
		var names := q.pending().map(func(c: Command): return c.describe())
		lines.append("  pending: %s" % (", ".join(names) if not names.is_empty() else "-"))
		var recent := q.history.slice(-5).map(func(c: Command): return c.describe())
		lines.append("  recent:  %s" % (", ".join(recent) if not recent.is_empty() else "-"))
	return "\n".join(lines) if not lines.is_empty() else "no command queues"
