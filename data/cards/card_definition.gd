class_name CardDefinition
extends Definition
## Example definition type for a card game. Replace or delete it: the
## Definitions autoload works with any Definition subclass.

@export var display_name := ""
@export_multiline var description := ""
@export_range(0, 10) var cost := 1
## Id of the card this one upgrades into ("" = none).
@export var upgrade: StringName


func _validate(problems: PackedStringArray, registry: DefinitionRegistry) -> void:
	if display_name.is_empty():
		problems.append("display_name is required")
	if cost < 0:
		problems.append("cost must not be negative")
	check_ref(problems, registry, "upgrade", CardDefinition, upgrade)
