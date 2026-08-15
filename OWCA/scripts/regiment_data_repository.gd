class_name RegimentDataRepository
extends RefCounted

## Loads regiment rules and provides stable-ID lookups to the rest of the app.
## It validates catalog structure but never applies selection mechanics.

const DEFAULT_DATA_PATH := "res://OWCA/data/regiment_options.json"

var data: Dictionary = {}
var last_error: String = ""
var equipment_repository := EquipmentDataRepository.new()
var _options_by_id: Dictionary = {}
var _choices_by_id: Dictionary = {}


## Parses and validates a complete catalog before exposing any indexed options.
func load_data(path: String = DEFAULT_DATA_PATH, equipment_path: String = EquipmentDataRepository.DEFAULT_DATA_PATH) -> Error:
	last_error = ""
	_options_by_id.clear()
	_choices_by_id.clear()
	var equipment_error := equipment_repository.load_data(equipment_path)
	if equipment_error != OK:
		last_error = equipment_repository.last_error
		return equipment_error

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Could not open rules data: %s" % path
		return FileAccess.get_open_error()

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		last_error = "Rules JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return parse_error
	if not parser.data is Dictionary:
		last_error = "Rules JSON root must be an object."
		return ERR_PARSE_ERROR

	data = parser.data as Dictionary
	if int(data.get("schema_version", 0)) != 1:
		last_error = "Unsupported rules schema version: %s" % data.get("schema_version", "missing")
		return ERR_INVALID_DATA

	for value: Variant in data.get("options", []):
		if not value is Dictionary:
			continue
		var option := value as Dictionary
		var option_id := str(option.get("id", ""))
		if option_id.is_empty() or _options_by_id.has(option_id):
			last_error = "Every regiment option needs a unique, non-empty id."
			return ERR_INVALID_DATA
		_options_by_id[option_id] = option

	var validation_error := _validate_loaded_data()
	if not validation_error.is_empty():
		last_error = validation_error
		_options_by_id.clear()
		_choices_by_id.clear()
		return ERR_INVALID_DATA

	for option: Dictionary in _options_by_id.values():
		for choice_value: Variant in option.get("choices", []):
			if choice_value is Dictionary:
				var choice := choice_value as Dictionary
				_choices_by_id[str(choice.get("id", ""))] = choice

	return OK


func get_option(option_id: String) -> Dictionary:
	return _options_by_id.get(option_id, {}) as Dictionary


func get_choice(choice_id: String) -> Dictionary:
	return _choices_by_id.get(choice_id, {}) as Dictionary


func get_options_for_category(category: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for value: Variant in data.get("options", []):
		if value is Dictionary and str(value.get("category", "")) == category:
			matches.append(value as Dictionary)
	return matches


func get_selection_rule(category: String) -> Dictionary:
	var rules := data.get("selection_rules", {}) as Dictionary
	return rules.get(category, {}) as Dictionary


func get_category_order() -> Array[String]:
	var categories: Array[String] = []
	for key: Variant in (data.get("selection_rules", {}) as Dictionary).keys():
		categories.append(str(key))
	return categories


func get_catalog_entry(catalog: String, entry_id: String) -> Dictionary:
	if catalog == "equipment":
		return equipment_repository.get_item(entry_id)
	var entries := data.get(catalog, {}) as Dictionary
	return entries.get(entry_id, {}) as Dictionary


func get_catalog_name(catalog: String, entry_id: String) -> String:
	var entry := get_catalog_entry(catalog, entry_id)
	return str(entry.get("name", entry_id.replace("_", " ").capitalize()))


func get_source_label(source_reference: Dictionary) -> String:
	var source_id := str(source_reference.get("book", ""))
	var source := (data.get("sources", {}) as Dictionary).get(source_id, {}) as Dictionary
	var title := str(source.get("short", source.get("title", source_id)))
	var page := int(source_reference.get("page", 0))
	var page_end := int(source_reference.get("page_end", 0))
	if page > 0 and page_end > page:
		return "%s pp. %d-%d" % [title, page, page_end]
	return "%s p. %d" % [title, page] if page > 0 else title


func _validate_loaded_data() -> String:
	var selection_rules := data.get("selection_rules", {}) as Dictionary
	var choice_ids: Dictionary = {}
	var base_error := _validate_effect_references(data.get("base_effects", {}) as Dictionary, "base_effects")
	if not base_error.is_empty():
		return base_error

	for value: Variant in data.get("options", []):
		var option := value as Dictionary
		var option_id := str(option.get("id", ""))
		var category := str(option.get("category", ""))
		if not selection_rules.has(category):
			return "Option '%s' uses unknown category '%s'." % [option_id, category]
		var source_error := _validate_source(option.get("source", {}) as Dictionary, "option '%s'" % option_id)
		if not source_error.is_empty():
			return source_error
		var effect_error := _validate_effect_references(option.get("effects", {}) as Dictionary, "option '%s'" % option_id)
		if not effect_error.is_empty():
			return effect_error

		for choice_value: Variant in option.get("choices", []):
			if not choice_value is Dictionary:
				return "Option '%s' contains a choice that is not an object." % option_id
			var choice := choice_value as Dictionary
			var choice_id := str(choice.get("id", ""))
			if choice_id.is_empty() or choice_ids.has(choice_id):
				return "Choice IDs must be globally unique; invalid id '%s'." % choice_id
			choice_ids[choice_id] = true
			var answers := choice.get("options", []) as Array
			if answers.is_empty():
				return "Choice '%s' has no answers." % choice_id
			var answer_ids: Dictionary = {}
			for answer_value: Variant in answers:
				if not answer_value is Dictionary:
					return "Choice '%s' contains an answer that is not an object." % choice_id
				var answer := answer_value as Dictionary
				var answer_id := str(answer.get("id", ""))
				if answer_id.is_empty() or answer_ids.has(answer_id):
					return "Choice '%s' has a missing or duplicate answer id '%s'." % [choice_id, answer_id]
				answer_ids[answer_id] = true
				var answer_error := _validate_effect_references(answer.get("effects", {}) as Dictionary, "choice '%s' answer '%s'" % [choice_id, answer_id])
				if not answer_error.is_empty():
					return answer_error
	return ""


func _validate_effect_references(effects: Dictionary, context: String) -> String:
	for catalog_name in ["skills", "talents"]:
		var catalog := data.get(catalog_name, {}) as Dictionary
		for entry_id: Variant in effects.get(catalog_name, []):
			if not catalog.has(str(entry_id)):
				return "%s references unknown %s id '%s'." % [context, catalog_name, entry_id]
	for value: Variant in effects.get("equipment", []):
		if not value is Dictionary:
			return "%s contains an equipment grant that is not an object." % context
		var equipment_id := str(value.get("id", ""))
		if not equipment_repository.has_item(equipment_id):
			return "%s references unknown equipment id '%s'." % [context, equipment_id]
	return ""


func _validate_source(source_reference: Dictionary, context: String) -> String:
	var book := str(source_reference.get("book", ""))
	if book.is_empty() or not (data.get("sources", {}) as Dictionary).has(book):
		return "%s references unknown source '%s'." % [context, book]
	return ""
