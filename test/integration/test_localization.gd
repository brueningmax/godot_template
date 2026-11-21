extends TemplateTest
## Localization: the .po files load, every template UI string is translated,
## and the language setting switches the language live.

## Scenes whose texts must all have a translation.
const SCENES := [
	"res://scenes/ui/menus/main_menu/main_menu.tscn",
	"res://scenes/ui/menus/pause_menu/pause_menu.tscn",
	"res://scenes/ui/menus/settings_menu/settings_menu.tscn",
	"res://scenes/ui/loading_screen/loading_screen.tscn",
	"res://scenes/debug/scene_library/scene_library.tscn",
	"res://scenes/debug/scene_library/debug_launcher_3d.tscn",
]
## Node texts that aren't meant to be translated.
const UNTRANSLATED := ["Button", "FPS: 60\nDraw Calls: 0\nObjects: 0"]

var _orig_language: String


func before_each() -> void:
	_orig_language = SettingsManager.get_setting("interface", "language", "")


func after_each() -> void:
	SettingsManager.set_setting("interface", "language", _orig_language, false)
	await super.after_each()


func test_english_and_german_are_loaded() -> void:
	var locales := TranslationServer.get_loaded_locales()
	assert_has(locales, "en")
	assert_has(locales, "de")


func test_german_translates_every_message() -> void:
	var de := TranslationServer.get_translation_object("de")
	for msgid in de.get_message_list():
		assert_ne(str(de.get_message(msgid)), "", "de translates '%s'" % msgid)


func test_every_scene_text_has_a_translation() -> void:
	var de := TranslationServer.get_translation_object("de")
	for text in _scene_texts():
		assert_ne(str(de.get_message(text)), "", "de.po has '%s'" % text)


func test_every_settings_row_has_a_translation() -> void:
	var de := TranslationServer.get_translation_object("de")
	for row in SettingsMenu.ROWS:
		var texts: Array = [row.label, row.tab]
		if row.has("tooltip"):
			texts.append(row.tooltip)
		if row.get("options") is Array:
			for option in row.options:
				if not str(option[1]).is_valid_int():
					texts.append(option[1])
		for text in texts:
			assert_ne(str(de.get_message(text)), "", "de.po has '%s'" % text)


func test_language_setting_switches_live() -> void:
	SettingsManager.set_setting("interface", "language", "de", false)
	assert_eq(tr("Play"), "Spielen")
	SettingsManager.set_setting("interface", "language", "en", false)
	assert_eq(tr("Play"), "Play")


func test_hello_world_updates_on_language_change() -> void:
	SettingsManager.set_setting("interface", "language", "en", false)
	var scene := await goto(SceneRegistry.SceneKey.GAME_SCENE)
	var info: Label = scene.get_node("%Info")
	assert_string_starts_with(info.text, "Hello, world!")
	SettingsManager.set_setting("interface", "language", "de", false)
	await wait_process_frames(2)
	assert_string_starts_with(info.text, "Hallo, Welt!")


func test_language_list_uses_native_names() -> void:
	var menu: SettingsMenu = autofree(
		load("res://scenes/ui/menus/settings_menu/settings_menu.tscn").instantiate()
	)
	var options: Array = menu._language_options()
	assert_eq(options[0], ["", "System"])
	assert_has(options, ["de", "Deutsch"])
	assert_has(options, ["en", "English"])


# Every text / placeholder_text in SCENES, as stored in the .tscn files.
func _scene_texts() -> Array:
	var regex := RegEx.create_from_string(
		'(?m)^(?:text|placeholder_text) = "((?:[^"\\\\]|\\\\.)*)"'
	)
	var texts := []
	for path in SCENES:
		var source := FileAccess.get_file_as_string(path)
		for m in regex.search_all(source):
			var text := m.get_string(1).c_unescape()
			if not UNTRANSLATED.has(text) and not texts.has(text):
				texts.append(text)
	assert_gt(texts.size(), 10, "found the scene texts")
	return texts
