extends Node3D

@onready var back_button: Button = $UILayer/MarginContainer/Control/VBoxContainer/BackButton
@onready var camera_control_check: CheckBox = $UILayer/MarginContainer/Control/VBoxContainer/CameraControlCheck
@onready var stats_label: Label = $UILayer/MarginContainer/Control/StatsVBox/StatsLabel
@onready var fps_bar: ProgressBar = $UILayer/MarginContainer/Control/StatsVBox/FPSBar
@onready var camera_container: Node3D = $CameraContainer
@onready var scene_container: Node3D = $SceneContainer
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D

static var scene_to_launch: String = ""
static var use_external_camera: bool = false

var zoom_level: float = 10.0
var is_orbiting: bool = false

func _ready() -> void:
	# Set FPS Cap to 100 and disable VSync to allow reaching it
	Engine.max_fps = 100
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	back_button.pressed.connect(_on_back_pressed)
	
	if scene_to_launch != "":
		var path = scene_to_launch
		scene_to_launch = "" # Clear to prevent recursive stack overflow
		var scene_res = load(path)
		if scene_res is PackedScene:
			var instance = scene_res.instantiate()
			scene_container.add_child(instance)
			
			var is_3d = instance is Node3D
			
			if use_external_camera and is_3d:
				# Show 3D-specific debug nodes
				camera_container.visible = true
				directional_light.visible = true
				camera_control_check.visible = true
				
				# Force external camera priority: disable all cameras inside the scene
				for cam in instance.find_children("*", "Camera3D", true):
					if cam is Camera3D:
						cam.current = false
				
				# Make the external camera current
				var ext_cam = camera_container.get_node("Camera3D")
				if ext_cam is Camera3D:
					ext_cam.make_current()
			else:
				# Hide 3D-specific debug nodes if not using external camera
				camera_container.visible = false
				directional_light.visible = false
				camera_control_check.visible = false
				camera_control_check.button_pressed = false
	
	set_process(true)

func _input(event: InputEvent) -> void:
	if not camera_control_check.button_pressed:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = max(2.0, zoom_level - 1.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = min(50.0, zoom_level + 1.0)
			_update_camera()
			
	if event is InputEventMouseMotion and is_orbiting:
		var sensitivity = 0.5
		camera_container.rotate_y(deg_to_rad(-event.relative.x * sensitivity))
		var cam = camera_container.get_node("Camera3D")
		cam.rotate_x(deg_to_rad(-event.relative.y * sensitivity))
		cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _update_camera() -> void:
	var cam = camera_container.get_node("Camera3D")
	cam.position.z = zoom_level

func _process(_delta: float) -> void:
	var fps = Engine.get_frames_per_second()
	var draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	
	var dc_hint = "(Good: <500)" if draw_calls < 500 else "(High: >1000)"
	var obj_hint = "(Good: <1000)" if objects < 1000 else "(High: >2000)"
	
	stats_label.text = "FPS: %d\nDraw Calls: %d %s\nObjects: %d %s" % [fps, draw_calls, dc_hint, objects, obj_hint]
	
	# Update FPS Bar
	fps_bar.value = fps
	var style = StyleBoxFlat.new()
	if fps < 30:
		style.bg_color = Color.RED
	elif fps < 60:
		style.bg_color = Color.YELLOW
	else:
		style.bg_color = Color.GREEN
	fps_bar.add_theme_stylebox_override("fill", style)

func _on_back_pressed() -> void:
	# Reset FPS cap and VSync when leaving
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	SceneManager.change_scene(SceneRegistry.SceneKey.DebugViewer)
