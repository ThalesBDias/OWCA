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
const WEAPON_CATEGORIES := ["ranged_weapon", "melee_weapon"]
const CRAFTSMANSHIP_TIERS := ["Poor", "Common", "Good", "Best"]
const EFFECT_OPERATIONS := ["quality_add", "quality_remove_prefix", "numeric_add", "numeric_multiply", "situational"]
const EFFECT_TARGETS := ["weight_kg", "profile.range_m", "profile.magazine", "profile.penetration", "profile.damage_bonus"]
const INTEGER_MULTIPLIER_TARGETS := ["profile.range_m", "profile.magazine"]
const CONDITION_KEYS := ["base_quality_absent", "base_quality_present", "quality_absent", "quality_present"]

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


func get_canonical_item(item_id: String) -> Dictionary:
	var item := _items_by_id.get(item_id, {}) as Dictionary
	var base_id := str(item.get("base_definition_id", ""))
	return get_item(base_id) if not base_id.is_empty() else item.duplicate(true)


func get_item_name(item_id: String) -> String:
	var item := _items_by_id.get(item_id, {}) as Dictionary
	return str(item.get("name", item_id.replace("_", " ").capitalize()))


func get_items() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value: Variant in _items_by_id.values():
		output.append((value as Dictionary).duplicate(true))
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	return output


func get_selectable_items() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for item: Dictionary in get_items():
		if not bool(item.get("legacy_alias", false)):
			output.append(item)
	return output


func get_weapon_upgrades() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for item: Dictionary in get_items():
		if str(item.get("category", "")) == "weapon_upgrade":
			output.append(item)
	return output


func get_craftsmanship_effects(tier: String, category: String) -> Array[Dictionary]:
	var rules := data.get("craftsmanship_rules", {}) as Dictionary
	var tiers := rules.get("tiers", {}) as Dictionary
	var tier_rules := tiers.get(tier, {}) as Dictionary
	var output: Array[Dictionary] = []
	for effect_value: Variant in tier_rules.get(category, []):
		output.append((effect_value as Dictionary).duplicate(true))
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
	var known_families: Dictionary = {}
	var known_classes: Dictionary = {}
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
			var family := str(item.get("family", ""))
			if not family.is_empty():
				known_families[family] = true
			var weapon_class := str((item.get("profile", {}) as Dictionary).get("class", ""))
			if not weapon_class.is_empty():
				known_classes[weapon_class] = true
		_items_by_id[item_id] = item
	var craftsmanship_error := _validate_craftsmanship_rules(sources)
	if not craftsmanship_error.is_empty():
		return craftsmanship_error
	for item_value: Variant in _items_by_id.values():
		var item := item_value as Dictionary
		var ammunition_id := str(item.get("ammunition_id", ""))
		if not ammunition_id.is_empty():
			if not _items_by_id.has(ammunition_id):
				return "Equipment '%s' references unknown ammunition '%s'." % [item.get("id", ""), ammunition_id]
			if str((_items_by_id[ammunition_id] as Dictionary).get("category", "")) != "ammunition":
				return "Equipment '%s' ammunition '%s' is not an ammunition definition." % [item.get("id", ""), ammunition_id]
		var item_id := str(item.get("id", ""))
		var base_definition_id := str(item.get("base_definition_id", ""))
		if not base_definition_id.is_empty():
			if base_definition_id == item_id or not _items_by_id.has(base_definition_id):
				return "Equipment '%s' references invalid base definition '%s'." % [item_id, base_definition_id]
			var base_item := _items_by_id[base_definition_id] as Dictionary
			if not str(base_item.get("base_definition_id", "")).is_empty():
				return "Equipment '%s' creates an unsupported alias chain." % item_id
			if str(base_item.get("category", "")) != str(item.get("category", "")):
				return "Equipment '%s' aliases a different category." % item_id
		if bool(item.get("legacy_alias", false)) and base_definition_id.is_empty():
			return "Equipment '%s' marks a non-alias as legacy." % item_id
		var category := str(item.get("category", ""))
		if category == "weapon_upgrade":
			var modification_error := _validate_modification(item_id, item.get("modification", {}) as Dictionary, known_families, known_classes)
			if not modification_error.is_empty():
				return modification_error
		elif item.has("modification"):
			return "Equipment '%s' attaches modification rules outside weapon_upgrade." % item_id
	for item_value: Variant in _items_by_id.values():
		var item := item_value as Dictionary
		if str(item.get("category", "")) != "weapon_upgrade":
			continue
		var modification := item.get("modification", {}) as Dictionary
		for conflict_value: Variant in modification.get("conflicts", []):
			var conflict_id := str(conflict_value)
			if conflict_id == str(item.get("id", "")) or not _items_by_id.has(conflict_id):
				return "Upgrade '%s' references invalid conflict '%s'." % [item.get("id", ""), conflict_id]
			if str((_items_by_id[conflict_id] as Dictionary).get("category", "")) != "weapon_upgrade":
				return "Upgrade '%s' conflict '%s' is not an upgrade." % [item.get("id", ""), conflict_id]
	return ""


func _validate_craftsmanship_rules(sources: Dictionary) -> String:
	var rules := data.get("craftsmanship_rules", {}) as Dictionary
	if rules.is_empty():
		return "Equipment catalogue needs craftsmanship_rules."
	for key: Variant in rules.keys():
		if str(key) not in ["source", "tiers"]:
			return "Craftsmanship rules use unsupported field '%s'." % key
	var source := rules.get("source", {}) as Dictionary
	if not sources.has(str(source.get("book", ""))) or int(source.get("page", 0)) <= 0:
		return "Craftsmanship rules need a valid printed source reference."
	var tiers := rules.get("tiers", {}) as Dictionary
	if tiers.size() != CRAFTSMANSHIP_TIERS.size():
		return "Craftsmanship rules must define exactly four tiers."
	for tier: String in CRAFTSMANSHIP_TIERS:
		if not tiers.has(tier) or not tiers[tier] is Dictionary:
			return "Craftsmanship rules are missing tier '%s'." % tier
		var tier_rules := tiers[tier] as Dictionary
		if tier_rules.size() != WEAPON_CATEGORIES.size():
			return "Craftsmanship tier '%s' must define ranged and melee rules only." % tier
		for category: String in WEAPON_CATEGORIES:
			if not tier_rules.get(category, null) is Array:
				return "Craftsmanship tier '%s' needs an effects array for '%s'." % [tier, category]
			for effect_value: Variant in tier_rules[category]:
				if not effect_value is Dictionary:
					return "Craftsmanship tier '%s' has a non-object effect." % tier
				var error := _validate_effect(effect_value as Dictionary)
				if not error.is_empty():
					return "Craftsmanship tier '%s': %s" % [tier, error]
	return ""


func _validate_modification(item_id: String, modification: Dictionary, known_families: Dictionary, known_classes: Dictionary) -> String:
	if modification.is_empty() or int(modification.get("order", -1)) < 0:
		return "Upgrade '%s' needs a non-negative modification order." % item_id
	for key: Variant in modification.keys():
		if str(key) not in ["order", "compatibility", "effects", "exclusive_group", "conflicts"]:
			return "Upgrade '%s' uses unsupported modification field '%s'." % [item_id, key]
	var exclusive_group := str(modification.get("exclusive_group", ""))
	if modification.has("exclusive_group") and exclusive_group.is_empty():
		return "Upgrade '%s' has an empty exclusive group." % item_id
	if modification.has("conflicts") and not modification.get("conflicts") is Array:
		return "Upgrade '%s' conflicts must be an array." % item_id
	var compatibility := modification.get("compatibility", {}) as Dictionary
	if compatibility.size() != 1 or not compatibility.get("any_of", null) is Array or (compatibility.get("any_of", []) as Array).is_empty():
		return "Upgrade '%s' needs a non-empty compatibility any_of array." % item_id
	for selector_value: Variant in compatibility.get("any_of", []):
		if not selector_value is Dictionary or (selector_value as Dictionary).is_empty():
			return "Upgrade '%s' has an invalid compatibility selector." % item_id
		var selector := selector_value as Dictionary
		for key: Variant in selector.keys():
			if str(key) not in ["categories", "classes", "families"] or not selector[key] is Array:
				return "Upgrade '%s' uses unsupported compatibility selector '%s'." % [item_id, key]
		for category_value: Variant in selector.get("categories", []):
			if str(category_value) not in WEAPON_CATEGORIES:
				return "Upgrade '%s' uses unknown compatible category '%s'." % [item_id, category_value]
		for class_value: Variant in selector.get("classes", []):
			if not known_classes.has(str(class_value)):
				return "Upgrade '%s' uses unknown compatible class '%s'." % [item_id, class_value]
		for family_value: Variant in selector.get("families", []):
			if not known_families.has(str(family_value)):
				return "Upgrade '%s' uses unknown compatible family '%s'." % [item_id, family_value]
	if not modification.get("effects", null) is Array or (modification.get("effects", []) as Array).is_empty():
		return "Upgrade '%s' needs a non-empty effects array." % item_id
	for effect_value: Variant in modification.get("effects", []):
		if not effect_value is Dictionary:
			return "Upgrade '%s' has a non-object effect." % item_id
		var error := _validate_effect(effect_value as Dictionary)
		if not error.is_empty():
			return "Upgrade '%s': %s" % [item_id, error]
	return ""


func _validate_effect(effect: Dictionary) -> String:
	for key: Variant in effect.keys():
		if str(key) not in ["operation", "target", "value", "condition", "rounding", "code", "summary"]:
			return "Effect uses unsupported field '%s'." % key
	var operation := str(effect.get("operation", ""))
	if operation not in EFFECT_OPERATIONS:
		return "Effect uses unsupported operation '%s'." % operation
	var condition := effect.get("condition", {}) as Dictionary
	if effect.has("condition"):
		if condition.is_empty():
			return "Effect condition must be a non-empty object."
		for key: Variant in condition.keys():
			if str(key) not in CONDITION_KEYS or str(condition[key]).is_empty():
				return "Effect uses unsupported condition '%s'." % key
	if operation in ["numeric_add", "numeric_multiply"]:
		var target := str(effect.get("target", ""))
		if target not in EFFECT_TARGETS or not effect.get("value", null) is float and not effect.get("value", null) is int:
			return "Numeric effect needs a supported target and numeric value."
		if operation == "numeric_multiply" and target in INTEGER_MULTIPLIER_TARGETS and str(effect.get("rounding", "")) not in ["ceil", "floor", "round"]:
			return "Integer multiplier target '%s' needs explicit rounding." % target
	elif operation in ["quality_add", "quality_remove_prefix"]:
		if str(effect.get("value", "")).is_empty():
			return "Quality effect needs a value."
	elif operation == "situational":
		if str(effect.get("code", "")).is_empty() or str(effect.get("summary", "")).is_empty():
			return "Situational effect needs a code and summary."
	return ""


func _validate_weapon_profile(item_id: String, profile: Dictionary) -> String:
	for key in ["class", "damage", "penetration", "qualities"]:
		if not profile.has(key):
			return "Weapon '%s' is missing profile field '%s'." % [item_id, key]
	if not profile.get("qualities", []) is Array:
		return "Weapon '%s' qualities must be an array." % item_id
	return ""
