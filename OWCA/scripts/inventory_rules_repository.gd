class_name InventoryRulesRepository
extends RefCounted

## Loads the concise carrying-capacity lookup used by inventory calculations.

const DEFAULT_DATA_PATH := "res://OWCA/data/inventory_rules.json"

var data: Dictionary = {}
var last_error: String = ""
var _capacity_by_sum: Dictionary = {}


func load_data(path: String = DEFAULT_DATA_PATH) -> Error:
	data.clear()
	_capacity_by_sum.clear()
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "Could not open inventory rules: %s" % path
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		last_error = "Inventory rules root must be an object."
		return ERR_PARSE_ERROR
	data = (parsed as Dictionary).duplicate(true)
	if int(data.get("schema_version", 0)) != 1 or not data.get("carrying_capacity", []) is Array:
		last_error = "Unsupported inventory rules schema."
		return ERR_INVALID_DATA
	for row_value: Variant in data.get("carrying_capacity", []):
		if not row_value is Dictionary:
			last_error = "Every carrying-capacity row must be an object."
			return ERR_INVALID_DATA
		var row := row_value as Dictionary
		var bonus_sum := int(row.get("bonus_sum", -1))
		if bonus_sum < 0 or bonus_sum > 20 or _capacity_by_sum.has(bonus_sum):
			last_error = "Inventory rules contain an invalid or duplicate bonus sum."
			return ERR_INVALID_DATA
		if float(row.get("carrying_kg", -1.0)) < 0.0 or float(row.get("lifting_kg", -1.0)) < 0.0:
			last_error = "Carrying capacities cannot be negative."
			return ERR_INVALID_DATA
		_capacity_by_sum[bonus_sum] = row.duplicate(true)
	if _capacity_by_sum.size() != 21:
		last_error = "Inventory rules must define bonus sums 0 through 20."
		return ERR_INVALID_DATA
	return OK


func get_capacity(bonus_sum: int) -> Dictionary:
	return (_capacity_by_sum.get(clampi(bonus_sum, 0, 20), {}) as Dictionary).duplicate(true)


func get_content_version() -> String:
	return str(data.get("content_version", "unknown"))
