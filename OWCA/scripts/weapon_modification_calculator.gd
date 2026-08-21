class_name WeaponModificationCalculator
extends RefCounted

## Pure projection of a single owned weapon through craftsmanship and upgrades.

const DAMAGE_PATTERN := "^(\\d+)d(\\d+)([+-]\\d+)?\\s+([EIRX])$"
const WEAPON_CATEGORIES := ["ranged_weapon", "melee_weapon"]
const CRAFTSMANSHIP_TIERS := ["Poor", "Common", "Good", "Best"]


func calculate(owned: Dictionary, repository: EquipmentDataRepository) -> Dictionary:
	var result := _empty_result()
	var definition_id := str(owned.get("definition_id", ""))
	var selected_definition := repository.get_item(definition_id)
	if selected_definition.is_empty():
		return _fail(result, "missing_definition", "Weapon definition '%s' is unavailable." % definition_id)
	var definition := repository.get_canonical_item(definition_id)
	var canonical_id := str(definition.get("id", ""))
	result["canonical_definition_id"] = canonical_id
	var category := str(definition.get("category", ""))
	if category not in WEAPON_CATEGORIES:
		return _fail(result, "invalid_weapon_category", "Craftsmanship and weapon upgrades apply only to ranged or melee weapons.")
	var craftsmanship := str(owned.get("craftsmanship", selected_definition.get("craftsmanship", "Common")))
	if craftsmanship not in CRAFTSMANSHIP_TIERS:
		return _fail(result, "invalid_craftsmanship", "Unknown craftsmanship tier '%s'." % craftsmanship)

	var base_profile := (definition.get("profile", {}) as Dictionary).duplicate(true)
	var final_profile := base_profile.duplicate(true)
	var base_weight := float(definition.get("weight_kg", 0.0))
	var context := {"profile": final_profile, "weight_kg": base_weight}
	result["base_profile"] = base_profile
	result["final_profile"] = final_profile
	result["base_weight_kg"] = snappedf(base_weight, 0.01)
	result["final_weight_kg"] = snappedf(base_weight, 0.01)

	var modification_ids: Array[String] = []
	var seen_ids: Dictionary = {}
	for modification_value: Variant in owned.get("modification_ids", []):
		var modification_id := str(modification_value)
		if seen_ids.has(modification_id):
			return _fail(result, "duplicate_modification", "Weapon upgrade '%s' is installed more than once." % modification_id)
		seen_ids[modification_id] = true
		modification_ids.append(modification_id)

	var modifications: Array[Dictionary] = []
	for modification_id: String in modification_ids:
		var modification := repository.get_item(modification_id)
		if modification.is_empty() or str(modification.get("category", "")) != "weapon_upgrade":
			return _fail(result, "missing_modification", "Weapon upgrade '%s' is unavailable." % modification_id)
		if not _is_compatible(definition, modification):
			return _fail(result, "incompatible_modification", "%s is not compatible with %s." % [modification.get("name", modification_id), definition.get("name", canonical_id)])
		modifications.append(modification)
	modifications.sort_custom(_sort_modifications)

	var exclusive_groups: Dictionary = {}
	for modification: Dictionary in modifications:
		var modification_data := modification.get("modification", {}) as Dictionary
		var group := str(modification_data.get("exclusive_group", ""))
		if not group.is_empty():
			if exclusive_groups.has(group):
				return _fail(result, "exclusive_group_conflict", "%s conflicts with %s because only one %s may be installed." % [modification.get("name", "Upgrade"), exclusive_groups[group], group])
			exclusive_groups[group] = str(modification.get("name", modification.get("id", "Upgrade")))
		for conflict_value: Variant in modification_data.get("conflicts", []):
			if str(conflict_value) in modification_ids:
				return _fail(result, "modification_conflict", "%s conflicts with installed upgrade '%s'." % [modification.get("name", "Upgrade"), conflict_value])
	result["installed_modifications"] = modifications.duplicate(true)

	var craftsmanship_effects := repository.get_craftsmanship_effects(craftsmanship, category)
	var craftsmanship_error := _apply_effects(
		craftsmanship_effects,
		"craftsmanship",
		craftsmanship,
		"%s Craftsmanship" % craftsmanship,
		base_profile,
		context,
		result
	)
	if not craftsmanship_error.is_empty():
		return _fail(result, "invalid_damage_profile", craftsmanship_error)

	for modification: Dictionary in modifications:
		var modification_id := str(modification.get("id", ""))
		var modification_data := modification.get("modification", {}) as Dictionary
		var effects: Array[Dictionary] = []
		for effect_value: Variant in modification_data.get("effects", []):
			effects.append(effect_value as Dictionary)
		var modification_error := _apply_effects(
			effects,
			"modification",
			modification_id,
			str(modification.get("name", modification_id)),
			base_profile,
			context,
			result
		)
		if not modification_error.is_empty():
			return _fail(result, "invalid_damage_profile", modification_error)

	result["final_profile"] = (context["profile"] as Dictionary).duplicate(true)
	result["final_weight_kg"] = snappedf(float(context.get("weight_kg", 0.0)), 0.01)
	result["valid"] = true
	result["code"] = "ok"
	result["message"] = "Weapon profile calculated."
	return result


func evaluate_install(owned: Dictionary, modification_id: String, repository: EquipmentDataRepository) -> Dictionary:
	var candidate := owned.duplicate(true)
	var ids: Array = (candidate.get("modification_ids", []) as Array).duplicate()
	ids.append(modification_id)
	candidate["modification_ids"] = ids
	var result := calculate(candidate, repository)
	return {
		"compatible": bool(result.get("valid", false)),
		"code": str(result.get("code", "ok")),
		"message": str(result.get("message", "Compatible.")),
		"weapon": result
	}


func _empty_result() -> Dictionary:
	return {
		"valid": false,
		"code": "invalid",
		"message": "Weapon profile could not be calculated.",
		"canonical_definition_id": "",
		"base_profile": {},
		"final_profile": {},
		"base_weight_kg": 0.0,
		"final_weight_kg": 0.0,
		"installed_modifications": [],
		"situational_effects": [],
		"steps": []
	}


func _fail(result: Dictionary, code: String, message: String) -> Dictionary:
	result["valid"] = false
	result["code"] = code
	result["message"] = message
	return result


func _sort_modifications(a: Dictionary, b: Dictionary) -> bool:
	var a_data := a.get("modification", {}) as Dictionary
	var b_data := b.get("modification", {}) as Dictionary
	var a_order := int(a_data.get("order", 0))
	var b_order := int(b_data.get("order", 0))
	if a_order != b_order:
		return a_order < b_order
	return str(a.get("id", "")) < str(b.get("id", ""))


func _is_compatible(weapon: Dictionary, modification: Dictionary) -> bool:
	var modification_data := modification.get("modification", {}) as Dictionary
	var compatibility := modification_data.get("compatibility", {}) as Dictionary
	for selector_value: Variant in compatibility.get("any_of", []):
		var selector := selector_value as Dictionary
		if _matches_selector(weapon, selector):
			return true
	return false


func _matches_selector(weapon: Dictionary, selector: Dictionary) -> bool:
	if selector.has("categories") and str(weapon.get("category", "")) not in (selector.get("categories", []) as Array):
		return false
	var profile := weapon.get("profile", {}) as Dictionary
	if selector.has("classes") and str(profile.get("class", "")) not in (selector.get("classes", []) as Array):
		return false
	if selector.has("families") and str(weapon.get("family", "")) not in (selector.get("families", []) as Array):
		return false
	return true


func _apply_effects(
	effects: Array[Dictionary],
	source_type: String,
	source_id: String,
	label: String,
	base_profile: Dictionary,
	context: Dictionary,
	result: Dictionary
) -> String:
	for effect: Dictionary in effects:
		if not _condition_matches(effect.get("condition", {}) as Dictionary, base_profile, context["profile"] as Dictionary):
			continue
		var operation := str(effect.get("operation", ""))
		var target := str(effect.get("target", ""))
		var before: Variant = null
		var after: Variant = null
		var summary := str(effect.get("summary", ""))
		match operation:
			"quality_add":
				target = "profile.qualities"
				before = ((context["profile"] as Dictionary).get("qualities", []) as Array).duplicate()
				_add_quality(context["profile"] as Dictionary, str(effect.get("value", "")))
				after = ((context["profile"] as Dictionary).get("qualities", []) as Array).duplicate()
				if summary.is_empty():
					summary = "Adds %s." % effect.get("value", "")
			"quality_remove_prefix":
				target = "profile.qualities"
				before = ((context["profile"] as Dictionary).get("qualities", []) as Array).duplicate()
				_remove_quality_prefix(context["profile"] as Dictionary, str(effect.get("value", "")))
				after = ((context["profile"] as Dictionary).get("qualities", []) as Array).duplicate()
				if summary.is_empty():
					summary = "Removes %s variants." % effect.get("value", "")
			"numeric_add", "numeric_multiply":
				before = _target_value(context, target)
				var numeric_error := _apply_numeric(context, effect)
				if not numeric_error.is_empty():
					return numeric_error
				after = _target_value(context, target)
				if summary.is_empty():
					summary = "%s changes from %s to %s." % [target, before, after]
			"situational":
				target = "situational.%s" % effect.get("code", "")
				var situational := effect.duplicate(true)
				situational["source_type"] = source_type
				situational["source_id"] = source_id
				situational["label"] = label
				(result["situational_effects"] as Array).append(situational)
				after = situational.duplicate(true)
		(result["steps"] as Array).append({
			"source_type": source_type,
			"source_id": source_id,
			"label": label,
			"target": target,
			"before": before,
			"after": after,
			"summary": summary
		})
	return ""


func _condition_matches(condition: Dictionary, base_profile: Dictionary, final_profile: Dictionary) -> bool:
	for key_value: Variant in condition.keys():
		var key := str(key_value)
		var quality := str(condition[key_value])
		match key:
			"base_quality_absent":
				if _has_quality(base_profile, quality):
					return false
			"base_quality_present":
				if not _has_quality(base_profile, quality):
					return false
			"quality_absent":
				if _has_quality(final_profile, quality):
					return false
			"quality_present":
				if not _has_quality(final_profile, quality):
					return false
	return true


func _has_quality(profile: Dictionary, prefix: String) -> bool:
	for value: Variant in profile.get("qualities", []):
		var quality := str(value)
		if quality == prefix or quality.begins_with(prefix + " ("):
			return true
	return false


func _add_quality(profile: Dictionary, quality: String) -> void:
	var qualities := profile.get("qualities", []) as Array
	if quality not in qualities:
		qualities.append(quality)
	profile["qualities"] = qualities


func _remove_quality_prefix(profile: Dictionary, prefix: String) -> void:
	var output: Array = []
	for value: Variant in profile.get("qualities", []):
		var quality := str(value)
		if quality == prefix or quality.begins_with(prefix + " ("):
			continue
		output.append(value)
	profile["qualities"] = output


func _target_value(context: Dictionary, target: String) -> Variant:
	if target == "weight_kg":
		return float(context.get("weight_kg", 0.0))
	var profile := context["profile"] as Dictionary
	if target == "profile.damage_bonus":
		return str(profile.get("damage", ""))
	return profile.get(target.trim_prefix("profile."))


func _apply_numeric(context: Dictionary, effect: Dictionary) -> String:
	var operation := str(effect.get("operation", ""))
	var target := str(effect.get("target", ""))
	var operand := float(effect.get("value", 0.0))
	if target == "profile.damage_bonus":
		var profile := context["profile"] as Dictionary
		var damage := str(profile.get("damage", ""))
		var parsed := _parse_damage(damage)
		if parsed.is_empty():
			return "Damage profile '%s' cannot receive a numeric modifier." % damage
		var bonus := float(parsed.get("bonus", 0))
		bonus = bonus + operand if operation == "numeric_add" else bonus * operand
		parsed["bonus"] = int(bonus)
		profile["damage"] = _format_damage(parsed)
		return ""
	if target == "weight_kg":
		var current_weight := float(context.get("weight_kg", 0.0))
		context["weight_kg"] = current_weight + operand if operation == "numeric_add" else current_weight * operand
		return ""
	var profile := context["profile"] as Dictionary
	var key := target.trim_prefix("profile.")
	var current := float(profile.get(key, 0.0))
	var calculated := current + operand if operation == "numeric_add" else current * operand
	if operation == "numeric_multiply" and effect.has("rounding"):
		match str(effect.get("rounding", "")):
			"ceil":
				calculated = ceilf(calculated)
			"floor":
				calculated = floorf(calculated)
			"round":
				calculated = roundf(calculated)
	profile[key] = int(calculated) if current == int(current) and operand == int(operand) or target in ["profile.range_m", "profile.magazine", "profile.penetration"] else calculated
	return ""


func _parse_damage(damage: String) -> Dictionary:
	var expression := RegEx.new()
	if expression.compile(DAMAGE_PATTERN) != OK:
		return {}
	var matched := expression.search(damage)
	if matched == null:
		return {}
	var bonus_text := matched.get_string(3)
	return {
		"dice": int(matched.get_string(1)),
		"sides": int(matched.get_string(2)),
		"bonus": int(bonus_text) if not bonus_text.is_empty() else 0,
		"type": matched.get_string(4)
	}


func _format_damage(parsed: Dictionary) -> String:
	var bonus := int(parsed.get("bonus", 0))
	var bonus_text := ""
	if bonus > 0:
		bonus_text = "+%d" % bonus
	elif bonus < 0:
		bonus_text = str(bonus)
	return "%dd%d%s %s" % [parsed.get("dice", 0), parsed.get("sides", 0), bonus_text, parsed.get("type", "")]
