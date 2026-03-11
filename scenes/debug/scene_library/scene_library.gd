extends Control

@onready var scene_tree: Tree = $HSplitContainer/TreePanel/VBox/SceneTree
@onready var preview_viewport: SubViewport = $HSplitContainer/PreviewPanel/VBox/PreviewContainer/SubViewport
@onready var no_preview_label: Label = $HSplitContainer/PreviewPanel/VBox/PreviewContainer/NoPreviewLabel
@onready var launch_button: Button = $HSplitContainer/PreviewPanel/VBox/LaunchButton
@onready var back_button: Button = $HSplitContainer/TreePanel/VBox/BackToMenu
@onready var search_box: LineEdit = $HSplitContainer/TreePanel/VBox/Search
@onready var external_camera_check: CheckBox = $HSplitContainer/TreePanel/VBox/ExternalCameraCheck

@onready var preview_container: SubViewportContainer = $HSplitContainer/PreviewPanel/VBox/PreviewContainer

var selected_scene_path: String = ""
var current_preview_instance: Node = null
var is_orbiting: bool = false
var orbit_camera: Camera3D = null
var launched_scene_container: Node = null
var launched_scene_instance: Node = null

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	launch_button.pressed.connect(_on_launch_pressed)
	scene_tree.item_selected.connect(_on_item_selected)
	search_box.text_changed.connect(_on_search_changed)
	preview_container.gui_input.connect(_on_preview_gui_input)
	
	# Create container for launched scenes
	launched_scene_container = Node.new()
	launched_scene_container.name = "LaunchedSceneContainer"
	add_child(launched_scene_container)
	
	_populate_tree()

func _populate_tree() -> void:
	scene_tree.clear()
	var root = scene_tree.create_item()
	_scan_dir("res://scenes", root)

func _scan_dir(path: String, parent_item: TreeItem) -> void:
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if not file_name.begins_with("."):
					var dir_item = scene_tree.create_item(parent_item)
					dir_item.set_text(0, file_name)
					dir_item.set_selectable(0, false)
					dir_item.collapsed = true
					_scan_dir(path.path_join(file_name), dir_item)
			else:
				if file_name.ends_with(".tscn"):
					var file_item = scene_tree.create_item(parent_item)
					file_item.set_text(0, file_name)
					var full_path = path.path_join(file_name)
					file_item.set_metadata(0, full_path)
					file_item.set_custom_color(0, Color.AQUAMARINE)
					_try_set_icon(file_item, full_path)
			file_name = dir.get_next()
		dir.list_dir_end()

func _try_set_icon(item: TreeItem, path: String) -> void:
	# Use folder/name keywords to colorize entries
	if "3d" in path.to_lower() or "level" in path.to_lower():
		item.set_custom_color(0, Color.ORANGE)
	elif "menu" in path.to_lower() or "ui" in path.to_lower():
		item.set_custom_color(0, Color.CYAN)

func _on_search_changed(query: String) -> void:
	_filter_tree(scene_tree.get_root(), query.to_lower())

func _filter_tree(item: TreeItem, query: String) -> bool:
	var any_visible = false
	var text = item.get_text(0).to_lower()
	
	if query == "" or text.contains(query):
		any_visible = true
	
	var child = item.get_first_child()
	while child:
		if _filter_tree(child, query):
			any_visible = true
		child = child.get_next_sibling()
	
	item.visible = any_visible
	# Expand folders that have visible results
	if any_visible and query != "" and item.get_metadata(0) == null:
		item.collapsed = false
	elif query == "":
		item.collapsed = true
		
	return any_visible

func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_orbiting = event.pressed
	
	if event is InputEventMouseMotion and is_orbiting and orbit_camera:
		var sensitivity = 0.5
		var pivot = orbit_camera.get_parent()
		if pivot and pivot.name == "OrbitPivot":
			pivot.rotate_y(deg_to_rad(-event.relative.x * sensitivity))
			orbit_camera.rotate_x(deg_to_rad(-event.relative.y * sensitivity))
			orbit_camera.rotation.x = clamp(orbit_camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _on_item_selected() -> void:
	var selected = scene_tree.get_selected()
	if selected:
		selected_scene_path = selected.get_metadata(0)
		if selected_scene_path != "":
			launch_button.disabled = false
			_update_preview(selected_scene_path)
			_check_3d_support(selected_scene_path)
		else:
			launch_button.disabled = true
			_clear_preview()

func _check_3d_support(_path: String) -> void:
	if current_preview_instance:
		external_camera_check.visible = (current_preview_instance is Node3D)
		if not external_camera_check.visible:
			external_camera_check.button_pressed = false

func _clear_preview() -> void:
	if current_preview_instance:
		current_preview_instance.queue_free()
		current_preview_instance = null
	orbit_camera = null
	no_preview_label.visible = true

func _update_preview(scene_path: String) -> void:
	_clear_preview()
	
	if ResourceLoader.exists(scene_path):
		var scene_resource = load(scene_path)
		if scene_resource is PackedScene:
			current_preview_instance = scene_resource.instantiate()
			preview_viewport.add_child(current_preview_instance)
			no_preview_label.visible = false
			_setup_preview_environment(current_preview_instance)

func _setup_preview_environment(node: Node) -> void:
	if node is Node3D:
		var has_camera = false
		for child in node.find_children("*", "Camera3D", true):
			has_camera = true
			break
		
		# Always create an orbit pivot for 3D scenes in preview
		var pivot = Node3D.new()
		pivot.name = "OrbitPivot"
		node.add_child(pivot)
		
		orbit_camera = Camera3D.new()
		pivot.add_child(orbit_camera)
		orbit_camera.position = Vector3(0, 5, 10)
		orbit_camera.look_at(Vector3.ZERO)
		
		if not has_camera:
			orbit_camera.make_current()

func _on_launch_pressed() -> void:
	if selected_scene_path != "":
		var scene_resource = load(selected_scene_path)
		if scene_resource is PackedScene:
			# Clear any previously launched scene
			if launched_scene_instance:
				launched_scene_instance.queue_free()
				launched_scene_instance = null
			
			launched_scene_instance = scene_resource.instantiate()
			if launched_scene_instance is Node3D and external_camera_check.button_pressed:
				# Add external camera setup for 3D scenes if requested
				var pivot = Node3D.new()
				pivot.name = "OrbitPivot"
				launched_scene_instance.add_child(pivot)
				
				var camera = Camera3D.new()
				pivot.add_child(camera)
				camera.position = Vector3(0, 5, 10)
				camera.look_at(Vector3.ZERO)
				camera.make_current()
			
			# Add scene to the internal container
			launched_scene_container.add_child(launched_scene_instance)
			
			# Hide library UI
			visible = false

func _on_back_pressed() -> void:
	if launched_scene_instance:
		# Return from launched scene to library
		launched_scene_instance.queue_free()
		launched_scene_instance = null
		visible = true
	else:
		# Back to main menu
		SceneManager.change_scene(SceneRegistry.SceneKey.MainMenu)
