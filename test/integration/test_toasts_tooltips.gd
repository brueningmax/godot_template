extends TemplateTest
## Toasts (notifications) and Tooltips (tooltips on keyboard/controller focus).


func after_each() -> void:
	Toasts.clear()
	Tooltips.hide_tooltip()
	await super.after_each()


# --- Toasts ---


func test_toast_shows_and_fades_out() -> void:
	var toast := Toasts.show("Game saved", Toasts.Kind.SUCCESS, 0.1)
	assert_eq(Toasts.visible_toasts().size(), 1)
	assert_eq((toast.get_child(0) as Label).text, "Game saved")
	assert_eq(toast.get_meta(&"kind"), Toasts.Kind.SUCCESS)
	await _wait_freed(toast, 2.0)
	assert_false(is_instance_valid(toast), "removed after its duration")


func test_oldest_toast_makes_room() -> void:
	var first := Toasts.show("one")
	for i in Toasts.max_visible:
		Toasts.show("more %d" % i)
	assert_eq(Toasts.visible_toasts().size(), Toasts.max_visible)
	await wait_process_frames(1)
	assert_false(is_instance_valid(first))


func test_toasts_run_while_paused() -> void:
	await goto(SceneRegistry.SceneKey.GAME_SCENE)
	GameState.pause(false)
	var toast := Toasts.show("paused", Toasts.Kind.INFO, 0.1)
	await _wait_freed(toast, 2.0)
	assert_false(is_instance_valid(toast), "faded out while paused")


func test_dismiss() -> void:
	var toast := Toasts.show("bye", Toasts.Kind.INFO, 60.0)
	Toasts.dismiss(toast)
	assert_eq(Toasts.visible_toasts().size(), 0)
	await _wait_freed(toast, 1.0)
	assert_false(is_instance_valid(toast))


# A lambda must not capture the node itself: it's freed while we wait.
func _wait_freed(node: Node, seconds: float) -> void:
	var ref: WeakRef = weakref(node)
	await wait_until(func(): return ref.get_ref() == null, seconds)


# --- Tooltips ---


func _button_with_tooltip() -> Button:
	var button := Button.new()
	button.text = "Hi"
	button.tooltip_text = "Says hello."
	add_child_autofree(button)
	return button


func _key_press() -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_SHIFT
	e.pressed = true
	Input.parse_input_event(e)
	await wait_process_frames(2)


func test_tooltip_on_keyboard_focus() -> void:
	var button := _button_with_tooltip()
	await _key_press()
	button.grab_focus()
	await wait_until(func(): return Tooltips.shown_for() == button, 2.0)
	assert_eq(Tooltips.shown_for(), button)
	var label: Label = Tooltips.get_node("TooltipLayer/Tooltip").get_child(0)
	assert_eq(label.text, "Says hello.")


func test_no_tooltip_for_mouse_focus_and_mouse_hides_it() -> void:
	var button := _button_with_tooltip()
	var motion := InputEventMouseMotion.new()
	Input.parse_input_event(motion)
	await wait_process_frames(2)
	button.grab_focus()
	await wait_seconds(Tooltips.DELAY + 0.2)
	assert_null(Tooltips.shown_for(), "mouse users get Godot's hover tooltip")
	button.release_focus()
	await _key_press()
	button.grab_focus()
	await wait_until(func(): return Tooltips.shown_for() == button, 2.0)
	Input.parse_input_event(motion)
	await wait_process_frames(2)
	assert_null(Tooltips.shown_for(), "moving the mouse hides it")


func test_focus_change_hides_tooltip() -> void:
	var a := _button_with_tooltip()
	var b := Button.new()
	add_child_autofree(b)
	await _key_press()
	a.grab_focus()
	await wait_until(func(): return Tooltips.shown_for() == a, 2.0)
	b.grab_focus()
	assert_null(Tooltips.shown_for(), "no tooltip text on b")


func test_settings_rows_have_tooltips() -> void:
	var menu: SettingsMenu = autofree(
		load("res://scenes/ui/menus/settings_menu/settings_menu.tscn").instantiate()
	)
	add_child(menu)
	var vsync: Control = menu._controls["display/vsync"]
	assert_ne(vsync.tooltip_text, "")
