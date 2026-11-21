class_name Definition
extends Resource
## Base class for game content defined as data: cards, items, enemies...
## Make a subclass per kind of content and save instances as .tres files
## under res://data/. The Definitions autoload finds and indexes them.
##
##   class_name CardDefinition
##   extends Definition
##   @export var cost := 1
##
##   var card := Definitions.get_definition(CardDefinition, &"strike") as CardDefinition

## Unique among definitions of the same type. Empty = the file name
## (strike.tres -> &"strike").
@export var id: StringName
## Free-form labels for grouping and lookups (Definitions.with_tag()).
@export var tags: Array[StringName] = []


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## Problems with this definition, e.g. a missing required field or a
## reference to an id that doesn't exist. Override _validate() to add checks;
## `registry` is the Definitions autoload (or the registry under test).
func validate(registry: DefinitionRegistry) -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("has no id")
	_validate(problems, registry)
	return problems


## Override to check your fields. Append one message per problem:
##   if display_name.is_empty(): problems.append("display_name is required")
func _validate(_problems: PackedStringArray, _registry: DefinitionRegistry) -> void:
	pass


## Helper for _validate(): checks that `ref_id` names an existing definition
## of `type` (empty ids are allowed: "no reference").
func check_ref(
	problems: PackedStringArray,
	registry: DefinitionRegistry,
	field: String,
	type: Variant,
	ref_id: StringName
) -> void:
	if ref_id != &"" and not registry.has(type, ref_id):
		problems.append(
			"%s: no %s with id '%s'" % [field, DefinitionRegistry.type_key(type), ref_id]
		)
