extends TemplateTest
## Audio: ID-based and direct playback.

var _wav: AudioStreamWAV


func before_each() -> void:
	_wav = AudioStreamWAV.new()
	var data := PackedByteArray()
	data.resize(44100)
	_wav.data = data
	_wav.mix_rate = 22050


func test_play_by_id_uses_registry_bus() -> void:
	Audio.play(&"ui.click")
	assert_true(_playing(load("res://assets/audio/ui/click.ogg"), "UI"))


func test_unknown_id_warns_and_plays_nothing() -> void:
	Audio.play(&"ui.does_not_exist")
	pass_test("no crash")


func test_play_sound_stream_defaults_to_sfx() -> void:
	Audio.play_sound(_wav)
	assert_true(_playing(_wav, "SFX"))


func test_play_sound_bus_override() -> void:
	Audio.play_sound(_wav, 0.0, &"Ambient")
	assert_true(_playing(_wav, "Ambient"))


func test_play_sound_cue_applies_volume() -> void:
	var cue := AudioCue.new()
	cue.stream = _wav
	cue.volume_db = -6.0
	Audio.play_sound(cue, 0.0, &"UI")
	var found := false
	for p in Audio.get_children():
		if p is AudioStreamPlayer and p.stream == _wav and p.bus == "UI":
			found = is_equal_approx(p.volume_db, -6.0)
	assert_true(found)


func test_play_sound_set_uses_set_bus() -> void:
	var cue := AudioCue.new()
	cue.stream = _wav
	var audio_set := AudioSet.new()
	audio_set.bus_name = &"Music"
	audio_set.cues = [cue]
	Audio.play_sound(audio_set)
	assert_true(_playing(_wav, "Music"))


func test_play_sound_at_positions_voice() -> void:
	Audio.play_sound_at(_wav, Vector3(1, 2, 3))
	var pos := Vector3.ZERO
	for p in Audio.get_children():
		if p is AudioStreamPlayer3D and p.stream == _wav and p.playing:
			pos = p.position
	assert_eq(pos, Vector3(1, 2, 3))


func test_follow_player_reused_and_cleaned_up() -> void:
	var owner3d := Node3D.new()
	get_tree().root.add_child(owner3d)
	var p1 := Audio.play_sound_follow(_wav, owner3d)
	var p2 := Audio.play_sound_follow(_wav, owner3d)
	assert_not_null(p1)
	assert_eq(p1, p2, "same player for same owner + sound")
	assert_eq(p1.get_parent(), owner3d)
	var p3 := Audio.play_follow(&"move.step", owner3d)
	assert_ne(p3, p1, "different sound gets its own player")
	var owner_id := owner3d.get_instance_id()
	owner3d.queue_free()
	await wait_process_frames(2)
	assert_false(Audio._follow_players.has(owner_id), "mapping cleaned up")


func test_unsupported_resource_returns_null() -> void:
	var owner3d: Node3D = autofree(Node3D.new())
	assert_null(Audio.play_sound_follow(Resource.new(), owner3d))


func _playing(stream: AudioStream, bus: String) -> bool:
	for p in Audio.get_children():
		if (p is AudioStreamPlayer or p is AudioStreamPlayer3D) and p.stream == stream:
			if p.bus == bus and p.playing:
				return true
	return false
