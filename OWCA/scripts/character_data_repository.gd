class_name CharacterDataRepository
extends RefCounted

## Loads character rules catalogs and provides stable-ID lookups.
##
## Repository methods expose data without applying character mechanics. Starting
## packages and advancement catalogs remain separate files so later complete
## Talent or equipment catalogs do not inflate Speciality definitions.

const DEFAULT_DATA_PATH := "res://OWCA/data/guardsman_specialities.json"
const DEFAULT_ADVANCEMENT_PATH := "res://OWCA/data/guardsman_advancements.json"
const InventoryRulesRepositoryScript = preload("res://OWCA/scripts/inventory_rules_repository.gd")

var data: Dictionary = {}
var advancement_data: Dictionary = {}
var last_error: String = ""
var equipment_repository := EquipmentDataRepository.new()
var inventory_rules_repository: RefCounted = InventoryRulesRepositoryScript.new()
var _specialities_by_id: Dictionary = {}
var _choices_by_id: Dictionary = {}


## Replaces every in-memory index only after both JSON documents parse and pass
## structural validation. `last_error` contains a player/developer-facing cause.
func load_data(path: String = DEFAULT_DATA_PATH, advancement_path: String = DEFAULT_ADVANCEMENT_PATH, equipment_path: String = EquipmentDataRepository.DEFAULT_DATA_PATH, inventory_rules_path: String = "res://OWCA/data/inventory_rules.json") -> Error:
	last_error = ""
	_specialities_by_id.clear()
	_choices_by_id.clear()
	advancement_data.clear()
	var equipment_error := equipment_repository.load_data(equipment_path)
	if equipment_error != OK:
		last_error = equipment_repository.last_error
		return equipment_error
	var inventory_error := int(inventory_rules_repository.call("load_data", inventory_rules_path))
	if inventory_error != OK:
		last_error = str(inventory_rules_repository.get("last_error"))
		return inventory_error

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Could not open character rules data: %s" % path
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		last_error = "Character rules JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return parse_error
	if not parser.data is Dictionary:
		last_error = "Character rules JSON root must be an object."
		return ERR_PARSE_ERROR

	data = parser.data as Dictionary
	if int(data.get("schema_version", 0)) != 1:
		last_error = "Unsupported character rules schema version."
		return ERR_INVALID_DATA

	var validation_error := _validate_loaded_data()
	if not validation_error.is_empty():
		last_error = validation_error
		_specialities_by_id.clear()
		_choices_by_id.clear()
		return ERR_INVALID_DATA

	var advancement_error := _load_advancement_data(advancement_path)
	if advancement_error != OK:
		_specialities_by_id.clear()
		_choices_by_id.clear()
		return advancement_error
	return OK


func get_specialities() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value: Variant in data.get("specialities", []):
		if value is Dictionary:
			output.append(value as Dictionary)
	return output


func get_speciality(speciality_id: String) -> Dictionary:
	return _specialities_by_id.get(speciality_id, {}) as Dictionary


func get_choice(choice_id: String) -> Dictionary:
	return _choices_by_id.get(choice_id, {}) as Dictionary


func get_catalog_entry(catalog: String, entry_id: String) -> Dictionary:
	if catalog == "equipment":
		return equipment_repository.get_item(entry_id)
	var starting_entry := (data.get(catalog, {}) as Dictionary).get(entry_id, {}) as Dictionary
	if not starting_entry.is_empty():
		return starting_entry
	return (advancement_data.get(catalog, {}) as Dictionary).get(entry_id, {}) as Dictionary


func get_catalog_name(catalog: String, entry_id: String) -> String:
	var entry := get_catalog_entry(catalog, entry_id)
	return str(entry.get("name", entry_id.replace("_", " ").capitalize()))


func get_source_label(source_reference: Dictionary) -> String:
	var source_id := str(source_reference.get("book", ""))
	var source := (data.get("sources", {}) as Dictionary).get(source_id, {}) as Dictionary
	if source.is_empty():
		source = (advancement_data.get("sources", {}) as Dictionary).get(source_id, {}) as Dictionary
	var title := str(source.get("short", source.get("title", source_id)))
	var page := int(source_reference.get("page", 0))
	var page_end := int(source_reference.get("page_end", 0))
	if page > 0 and page_end > page:
		return "%s pp. %d-%d" % [title, page, page_end]
	return "%s p. %d" % [title, page] if page > 0 else title


func get_speciality_choice_ids(speciality_id: String) -> Array[String]:
	var output: Array[String] = []
	for value: Variant in get_speciality(speciality_id).get("choices", []):
		if value is Dictionary:
			output.append(str((value as Dictionary).get("id", "")))
	return output


func get_advancement_entries(kind: String) -> Dictionary:
	return advancement_data.get(kind, {}) as Dictionary


func get_advancement_entry(kind: String, entry_id: String) -> Dictionary:
	return get_advancement_entries(kind).get(entry_id, {}) as Dictionary


func get_advancement_costs(kind: String) -> Dictionary:
	return (advancement_data.get("costs", {}) as Dictionary).get(kind, {}) as Dictionary


func get_advancement_source(kind: String, entry: Dictionary) -> Dictionary:
	var source := entry.get("source", {}) as Dictionary
	if not source.is_empty():
		return source
	return ((advancement_data.get("source_defaults", {}) as Dictionary).get(kind, {}) as Dictionary).duplicate(true)


func _load_advancement_data(path: String) -> Error:
	advancement_data.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Could not open character advancement data: %s" % path
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		last_error = "Character advancement JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return parse_error
	if not parser.data is Dictionary:
		last_error = "Character advancement JSON root must be an object."
		return ERR_PARSE_ERROR
	advancement_data = parser.data as Dictionary
	if int(advancement_data.get("schema_version", 0)) != 1:
		last_error = "Unsupported character advancement schema version."
		return ERR_INVALID_DATA
	var validation_error := _validate_advancement_data()
	if not validation_error.is_empty():
		last_error = validation_error
		advancement_data.clear()
		return ERR_INVALID_DATA
	return OK


func _validate_advancement_data() -> String:
	for kind in ["characteristic", "skill", "talent"]:
		var cost_table := get_advancement_costs(kind)
		var expected_size := 3 if kind == "talent" else 4
		for match_key in ["two", "one", "zero"]:
			if not cost_table.get(match_key, []) is Array or (cost_table.get(match_key, []) as Array).size() != expected_size:
				return "Advancement %s costs need %d entries for '%s'." % [kind, expected_size, match_key]
	var valid_aptitudes: Dictionary = {}
	for speciality in get_specialities():
		for aptitude: Variant in (speciality.get("effects", {}) as Dictionary).get("aptitudes", []):
			valid_aptitudes[str(aptitude)] = true
	for aptitude in ["Agility", "Ballistic Skill", "Defence", "Fellowship", "Fieldcraft", "Finesse", "General", "Intelligence", "Knowledge", "Leadership", "Offence", "Perception", "Psyker", "Social", "Strength", "Tech", "Toughness", "Weapon Skill", "Willpower"]:
		valid_aptitudes[aptitude] = true
	for kind in ["characteristics", "skills", "talents"]:
		if not advancement_data.get(kind, {}) is Dictionary:
			return "Character advancements must contain a '%s' object." % kind
		for entry_id: Variant in get_advancement_entries(kind):
			var entry := get_advancement_entry(kind, str(entry_id))
			if str(entry.get("name", "")).is_empty():
				return "Advancement '%s:%s' needs a name." % [kind, entry_id]
			var aptitudes := entry.get("aptitudes", []) as Array
			if aptitudes.size() != 2:
				return "Advancement '%s:%s' needs exactly two Aptitudes." % [kind, entry_id]
			for aptitude: Variant in aptitudes:
				if not valid_aptitudes.has(str(aptitude)):
					return "Advancement '%s:%s' uses unknown Aptitude '%s'." % [kind, entry_id, aptitude]
			if kind == "talents":
				if int(entry.get("tier", 0)) not in [1, 2, 3]:
					return "Talent '%s' needs a tier from 1 to 3." % entry_id
				if str(entry.get("summary", "")).is_empty():
					return "Talent '%s' needs a brief effect summary." % entry_id
				if not bool(entry.get("purchase_supported", true)) and str(entry.get("unsupported_reason", "")).is_empty():
					return "Unsupported Talent '%s' needs a player-facing reason." % entry_id
				if not entry.get("prerequisites", []) is Array:
					return "Talent '%s' prerequisites must be an array." % entry_id
				for requirement_value: Variant in entry.get("prerequisites", []):
					if not requirement_value is Dictionary:
						return "Talent '%s' contains a non-object prerequisite." % entry_id
					var requirement := requirement_value as Dictionary
					if str(requirement.get("type", "")) not in ["aptitude", "characteristic", "skill", "skill_any", "skill_prefix", "special", "talent", "talent_any", "talent_prefix", "talent_prefix_count"]:
						return "Talent '%s' uses unsupported prerequisite type '%s'." % [entry_id, requirement.get("type", "")]
					if str(requirement.get("label", "")).is_empty():
						return "Talent '%s' has a prerequisite without a label." % entry_id
	return ""


func _validate_loaded_data() -> String:
	if not data.get("specialities", []) is Array:
		return "Character rules must contain a specialities array."
	for value: Variant in data.get("specialities", []):
		if not value is Dictionary:
			return "Every Speciality must be an object."
		var speciality := value as Dictionary
		var speciality_id := str(speciality.get("id", ""))
		if speciality_id.is_empty() or _specialities_by_id.has(speciality_id):
			return "Every Speciality needs a unique, non-empty id."
		_specialities_by_id[speciality_id] = speciality
		if str(speciality.get("group", "")) != "guardsman":
			return "This character-data slice only accepts Guardsman Specialities."
		var effect_error := _validate_effects(speciality.get("effects", {}) as Dictionary, "Speciality '%s'" % speciality_id)
		if not effect_error.is_empty():
			return effect_error
		for choice_value: Variant in speciality.get("choices", []):
			if not choice_value is Dictionary:
				return "Speciality '%s' contains a choice that is not an object." % speciality_id
			var choice := choice_value as Dictionary
			var choice_id := str(choice.get("id", ""))
			if choice_id.is_empty() or _choices_by_id.has(choice_id):
				return "Character choice IDs must be globally unique; invalid id '%s'." % choice_id
			_choices_by_id[choice_id] = choice
			var minimum := int(choice.get("minimum", 1))
			var maximum := int(choice.get("maximum", 1))
			if minimum < 0 or maximum < minimum:
				return "Choice '%s' has invalid selection limits." % choice_id
			var option_ids: Dictionary = {}
			for answer_value: Variant in choice.get("options", []):
				if not answer_value is Dictionary:
					return "Choice '%s' contains an answer that is not an object." % choice_id
				var answer := answer_value as Dictionary
				var answer_id := str(answer.get("id", ""))
				if answer_id.is_empty() or option_ids.has(answer_id):
					return "Choice '%s' has a missing or duplicate answer id '%s'." % [choice_id, answer_id]
				option_ids[answer_id] = true
				var answer_error := _validate_effects(answer.get("effects", {}) as Dictionary, "Choice '%s' answer '%s'" % [choice_id, answer_id])
				if not answer_error.is_empty():
					return answer_error
			if option_ids.size() < maximum:
				return "Choice '%s' does not contain enough answers for its maximum." % choice_id
	return ""


func _validate_effects(effects: Dictionary, context: String) -> String:
	for catalog_name in ["skills", "talents"]:
		var catalog := data.get(catalog_name, {}) as Dictionary
		for entry_id: Variant in effects.get(catalog_name, []):
			if not catalog.has(str(entry_id)):
				return "%s references unknown %s id '%s'." % [context, catalog_name, entry_id]
	for equipment_value: Variant in effects.get("equipment", []):
		if not equipment_value is Dictionary:
			return "%s contains a non-object equipment grant." % context
		var equipment_id := str((equipment_value as Dictionary).get("id", ""))
		if not equipment_repository.has_item(equipment_id):
			return "%s references unknown equipment id '%s'." % [context, equipment_id]
	return ""
