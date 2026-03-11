extends CanvasLayer
class_name DebugHUD

@export var player: Player

@onready var current_state: Label = $MarginContainer/HBoxContainer/CurrentState
@onready var flow_bar: FlowBar = $Control/FlowBar

var visible_hud := true

func _ready():
	var flow_array: Array[int] = [100]
	flow_bar.thresholds = flow_array
	set_process(true)
	visible = visible_hud
	flow_bar.spawn_from_array(player.flow_config.thresholds)

func _process(_delta):
	if not player or not visible_hud:
		return

	var flow := player.flow.flow
	#var cap := player.flow.capf()
	#var mult := player.flow.speed_multiplier()
	#var level := player.flow.level

	# update current state
	var names := player.state_machine.get_active_state_names()
	current_state.text = " > ".join(names)

	# update bar
	#flow_bar.max_value = cap
	#flow_bar.value = flow
	flow_bar.updateValue(flow)
