extends MenuBase
class_name ResultsMenu

signal restart_pressed
signal quit_pressed

@onready var btn_quit: UIButton = %Quit
@onready var btn_restart: UIButton = %Restart
@onready var results: GridContainer = %Results
@onready var high_scores: GridContainer = %HighScores

func _ready() -> void:
	default_focus = btn_restart.get_path()
	btn_restart.pressed.connect(func(): restart_pressed.emit())
	btn_quit.pressed.connect(func(): quit_pressed.emit())

	# keyboard shortcuts (Enter = restart, Esc = quit)
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		restart_pressed.emit()
	elif event.is_action_pressed("ui_cancel"):
		quit_pressed.emit()

func display(run_score: Dictionary, high_score_data: ScoreClasses.ResultObject) -> void:
	for child in results.get_children():
		child.queue_free()
	var keys = run_score.keys()
	for key in keys:
		var value = str(run_score[key]) 
		create_summary_line(key, value)
	
	var lists = build_display_lists(high_score_data)
	for run in lists.top3:
		create_high_score_line("someGuy", run.score, run.time)
		
	for run in lists.window:
		create_high_score_line("someGuy", run.score, run.time)
	
func build_display_lists(result: ScoreClasses.ResultObject) -> Dictionary:
	var top3 := result.top3
	var window := result.window

	# window without entries already in top3
	var top_ids: Dictionary = {}
	for r in top3:
		top_ids[r.id] = true

	var window_unique: Array[ScoreClasses.RunEntry] = []
	for r in window:
		if not top_ids.has(r.id):
			window_unique.append(r)

	return {
		"top3": top3,
		"window": window_unique
	}

func create_summary_line(key: String, value: String) -> void:
	var key_label = Label.new()
	key_label.text = key
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	results.add_child(key_label)
	
	var value_label = Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_child(value_label)

func create_high_score_line(player_name: String, score: int, time: int ) -> void: 
	var player_label = Label.new()
	player_label.text = str(player_name)
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
	high_scores.add_child(player_label)
	
	var score_label = Label.new()
	score_label.text = str(score)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
	high_scores.add_child(score_label)
	
	var time_label = Label.new()
	time_label.text = str(Utils.format_time_msec(time))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
	high_scores.add_child(time_label)
