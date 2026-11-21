extends GutTest
## Definition + DefinitionRegistry: scanning, lookups, validation, the sample
## cards and the debug commands. Scans fixture folders with a fresh registry.

const VALID := "res://test/fixtures/definitions/valid"
const BROKEN := "res://test/fixtures/definitions/broken"


func _registry(dir: String) -> Array:
	var registry: DefinitionRegistry = autofree(DefinitionRegistry.new())
	var problems := registry.scan(dir)
	return [registry, problems]


func test_scans_recursively_and_indexes_by_type() -> void:
	var r: Array = _registry(VALID)
	var registry: DefinitionRegistry = r[0]
	assert_eq(r[1], PackedStringArray(), "no problems")
	assert_eq(registry.ids(CardDefinition), [&"a", &"b", &"from_file_name"])
	assert_eq(registry.types(), [&"CardDefinition"])
	assert_eq(registry.count(), 3)


func test_lookup_by_class_or_name() -> void:
	var registry: DefinitionRegistry = _registry(VALID)[0]
	var a := registry.get_definition(CardDefinition, &"a") as CardDefinition
	assert_not_null(a)
	assert_eq(a.display_name, "A")
	assert_eq(registry.get_definition(&"CardDefinition", &"b"), registry.all(CardDefinition)[1])
	assert_true(registry.has(CardDefinition, &"a"))
	assert_false(registry.has(CardDefinition, &"zzz"))


func test_missing_id_returns_null() -> void:
	var registry: DefinitionRegistry = _registry(VALID)[0]
	assert_null(registry.get_definition(CardDefinition, &"nope"))


func test_empty_id_comes_from_file_name() -> void:
	var registry: DefinitionRegistry = _registry(VALID)[0]
	assert_true(registry.has(CardDefinition, &"from_file_name"))


func test_tags() -> void:
	var registry: DefinitionRegistry = _registry(VALID)[0]
	var starters := registry.with_tag(CardDefinition, &"starter")
	assert_eq(starters.size(), 1)
	assert_eq(starters[0].id, &"a")


func test_validation_reports_every_problem() -> void:
	var problems: PackedStringArray = _registry(BROKEN)[1]
	var text := "\n".join(problems)
	assert_eq(problems.size(), 3, text)
	assert_string_contains(text, "Duplicate CardDefinition id 'same'")
	assert_string_contains(text, "'no_name'")
	assert_string_contains(text, "display_name is required")
	assert_string_contains(text, "upgrade: no CardDefinition with id 'missing_card'")


func test_missing_folder_is_empty() -> void:
	var r: Array = _registry("res://does/not/exist")
	assert_eq(r[0].count(), 0)
	assert_eq(r[1], PackedStringArray())


func test_sample_cards_load_at_startup() -> void:
	var strike := Definitions.get_definition(CardDefinition, &"strike") as CardDefinition
	assert_not_null(strike)
	assert_eq(strike.upgrade, &"strike_plus")
	assert_true(Definitions.has(CardDefinition, strike.upgrade))
	assert_eq(Definitions.validate_all(), PackedStringArray(), "sample data is valid")


func test_debug_commands() -> void:
	assert_string_contains(Debug.execute("defs"), "CardDefinition (3)")
	assert_eq(Debug.execute("defs CardDefinition"), "defend, strike, strike_plus")
	assert_string_contains(Debug.execute("def CardDefinition strike"), "display_name = Strike")
	assert_string_contains(Debug.execute("def CardDefinition nope"), "No CardDefinition")
