class_name EquipmentDataRepository
extends RefCounted

## Loads OWCA's immutable equipment definitions and exposes stable-ID lookups.
##
## A definition describes a rules object shared by every character. Ownership,
## current ammunition, craftsmanship, and installed modifications deliberately
## live outside this repository and belong to later character-state versions.

const DEFAULT_DATA_PATH := "res://OWCA/data/equipment_catalog.json"
const SUPPORTED_SCHEMA_VERSION := 1
const CATEGORIES := [
	"ranged_weapon", "melee_weapon", "grenade_missile", "ammunition",
	"armour", "wargear", "weapon_upgrade", "placeholder"
]

var data: Dictionary = {}
var last_error: String = ""
var _items_by_id: Dictionary = {}


func load_data(path: String = DEFAULT_DATA_PATH) -> Error:
	last_error = ""
	data.clear()
	_items_by_id.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Could not open equipment catalogue: %s" % path
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		last_error = "Equipment JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return parse_error
	if not parser.data is Dictionary:
		last_error = "Equipment catalogue root must be an object."
		return ERR_PARSE_ERROR
	data = parser.data as Dictionary
	if int(data.get("schema_version", 0)) != SUPPORTED_SCHEMA_VERSION:
		last_error = "Unsupported equipment schema version."
		return ERR_INVALID_DATA
	var validation_error := _validate()
	if not validation_error.is_empty():
		last_error = validation_error
		data.clear()
		_items_by_id.clear()
		return ERR_INVALID_DATA
	return OK


func get_content_version() -> String:
	return str(data.get("content_version", "unknown"))


func has_item(item_id: String) -> bool:
	return _items_by_id.has(item_id)


func get_item(item_id: String) -> Dictionary:
	return (_items_by_id.get(item_id, {}) as Dictionary).duplicate(true)


func get_item_name(item_id: String) -> String:
	var item := _items_by_id.get(item_id, {}) as Dictionary
	return str(item.get("name", item_id.replace("_", " ").capitalize()))


func get_items() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value: Variant in _items_by_id.values():
		output.append((value as Dictionary).duplicate(true))
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	return output


func get_source_label(source_reference: Dictionary) -> String:
	var source_id := str(source_reference.get("book", ""))
	var source := (data.get("sources", {}) as Dictionary).get(source_id, {}) as Dictionary
	var title := str(source.get("short", source.get("title", source_id)))
	var page := int(source_reference.get("page", 0))
	var page_end := int(source_reference.get("page_end", 0))
	if page > 0 and page_end > page:
		return "%s pp. %d-%d" % [title, page, page_end]
	return "%s p. %d" % [title, page] if page > 0 else title


func _validate() -> String:
	if str(data.get("content_version", "")).is_empty():
		return "Equipment catalogue needs a content_version."
	if not data.get("items", []) is Array:
		return "Equipment catalogue needs an items array."
	var sources := data.get("sources", {}) as Dictionary
	var id_pattern := RegEx.new()
	if id_pattern.compile("^[a-z0-9][a-z0-9_]*$") != OK:
		return "Could not initialize equipment ID validation."
	for value: Variant in data.get("items", []):
		if not value is Dictionary:
			return "Every equipment entry must be an object."
		var item := value as Dictionary
		var item_id := str(item.get("id", ""))
		if item_id.is_empty() or id_pattern.search(item_id) == null or _items_by_id.has(item_id):
			return "Every equipment entry needs a unique, non-empty id; invalid '%s'." % item_id
		if str(item.get("name", "")).is_empty():
			return "Equipment '%s' needs a name." % item_id
		var category := str(item.get("category", ""))
		if category not in CATEGORIES:
			return "Equipment '%s' uses unknown category '%s'." % [item_id, category]
		var source := item.get("source", {}) as Dictionary
		if not sources.has(str(source.get("book", ""))) or int(source.get("page", 0)) <= 0:
			return "Equipment '%s' needs a valid printed source reference." % item_id
		if category in ["ranged_weapon", "melee_weapon", "grenade_missile"]:
			var profile_error := _validate_weapon_profile(item_id, item.get("profile", {}) as Dictionary)
			if not profile_error.is_empty():
				return profile_error
		_items_by_id[item_id] = item
	for item_value: Variant in _items_by_id.values():
		var item := item_value as Dictionary
		var ammunition_id := str(item.get("ammunition_id", ""))
		if not ammunition_id.is_empty():
			if not _items_by_id.has(ammunition_id):
				return "Equipment '%s' references unknown ammunition '%s'." % [item.get("id", ""), ammunition_id]
			if str((_items_by_id[ammunition_id] as Dictionary).get("category", "")) != "ammunition":
				return "Equipment '%s' ammunition '%s' is not an ammunition definition." % [item.get("id", ""), ammunition_id]
		var base_definition_id := str(item.get("base_definition_id", ""))
		if not base_definition_id.is_empty() and (base_definition_id == str(item.get("id", "")) or not _items_by_id.has(base_definition_id)):
			return "Equipment '%s' references invalid base definition '%s'." % [item.get("id", ""), base_definition_id]
	return ""


func _validate_weapon_profile(item_id: String, profile: Dictionary) -> String:
	for key in ["class", "damage", "penetration", "qualities"]:
		if not profile.has(key):
			return "Weapon '%s' is missing profile field '%s'." % [item_id, key]
	if not profile.get("qualities", []) is Array:
		return "Weapon '%s' qualities must be an array." % item_id
	return ""
