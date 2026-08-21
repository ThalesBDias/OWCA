class_name CharacterCalculator
extends RefCounted

## Pure character-creation engine for the Core Guardsman testing slice.
##
## The calculator has no scene-tree, file, clock, or random dependencies. Given
## identical state and repositories, it must return an identical result.

const CHARACTERISTIC_APTITUDES: Array[String] = [
	"Weapon Skill", "Ballistic Skill", "Strength", "Toughness", "Agility",
	"Intelligence", "Perception", "Willpower", "Fellowship"
]
const InventoryCalculatorScript = preload("res://OWCA/scripts/character_inventory_calculator.gd")


## Builds the complete UI/export contract from saved inputs and current rules.
## Callers must treat the returned Dictionary as derived data and recalculate it
## after every state change rather than editing result fields in place.
func calculate(state: CharacterState, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository) -> Dictionary:
	var result := {
		"valid": false,
		"regiment_name": state.get_regiment_name(),
		"speciality_name": "",
		"speciality": {},
		"characteristics": {},
		"characteristic_bonuses": {},
		"regiment_characteristic_modifiers": {},
		"speciality_characteristic_modifiers": {},
		"skills": {},
		"talents": {},
		"aptitudes": {},
		"special_rules": [],
		"equipment": {},
		"starting_equipment": [],
		"inventory": {},
		"wounds_modifier": 0,
		"wounds": 0,
		"fate_points": 0,
		"movement": {},
		"xp_budget": int(character_repository.data.get("starting_xp", 600)),
		"xp_spent": 0,
		"xp_remaining": int(character_repository.data.get("starting_xp", 600)),
		"bonus_xp": 0,
		"advancement_ready": false,
		"advancement_options": [],
		"purchased_advances": [],
		"invalid_advances": [],
		"advancement_wounds_bonus": 0,
		"regiment_choices": [],
		"speciality_choices": [],
		"resolved_choices": [],
		"unresolved_choices": [],
		"sources": [],
		"errors": [],
		"warnings": []
	}
	result["_source_keys"] = {}
	var unique_groups: Dictionary = {}

	if not state.has_regiment():
		(result["errors"] as Array).append("Load a regiment before creating a character.")
	else:
		_apply_regiment(state, regiment_repository, character_repository, result, unique_groups)

	var speciality := character_repository.get_speciality(state.speciality_id)
	if speciality.is_empty():
		(result["errors"] as Array).append("Choose one Guardsman Speciality.")
	else:
		result["speciality"] = speciality
		result["speciality_name"] = str(speciality.get("name", state.speciality_id))
		result["xp_budget"] = int(speciality.get("starting_xp", character_repository.data.get("starting_xp", 600)))
		result["xp_remaining"] = int(result["xp_budget"])
		_apply_effects(speciality.get("effects", {}) as Dictionary, result, regiment_repository, character_repository, "speciality")
		_add_source(speciality.get("source", {}) as Dictionary, result, character_repository.get_source_label(speciality.get("source", {}) as Dictionary))
		var speciality_choices: Array = speciality.get("choices", []) as Array
		for choice_value: Variant in speciality_choices:
			if choice_value is Dictionary:
				(result["speciality_choices"] as Array).append((choice_value as Dictionary).duplicate(true))
		_process_choices(speciality_choices, state.speciality_resolutions, "speciality", unique_groups, result, regiment_repository, character_repository)

	_process_duplicate_aptitudes(state, result, unique_groups, regiment_repository, character_repository)
	_add_grants(result["aptitudes"] as Dictionary, "General", 1)
	_calculate_characteristics(state, result)
	_calculate_duplicate_talent_compensation(result, regiment_repository, character_repository)
	CharacterAdvancementCalculator.new().apply(state, result, character_repository)
	_add_advancement_sources(result, character_repository)
	_calculate_derived_values(state, speciality, result)
	_finalize_aggregates(result, regiment_repository, character_repository)
	result["starting_equipment"] = (result["equipment"] as Array).duplicate(true)
	var inventory_calculator: RefCounted = InventoryCalculatorScript.new()
	var inventory: Dictionary = inventory_calculator.call("calculate", state, result, character_repository.equipment_repository, character_repository.inventory_rules_repository)
	result["inventory"] = inventory
	if state.loadout_state != CharacterState.LOADOUT_UNPREPARED:
		result["equipment"] = (inventory.get("items", []) as Array).duplicate(true)
		for warning: Variant in inventory.get("warnings", []):
			(result["warnings"] as Array).append(str(warning))
		if not bool(inventory.get("valid", true)):
			(result["errors"] as Array).append("Resolve owned equipment with missing catalogue definitions.")
	result.erase("_source_keys")
	result["valid"] = (result["errors"] as Array).is_empty() and (result["unresolved_choices"] as Array).is_empty()
	return result


func _apply_regiment(state: CharacterState, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository, result: Dictionary, unique_groups: Dictionary) -> void:
	var regiment_state := RegimentState.new()
	var state_error := regiment_state.from_dict(state.regiment)
	if state_error != OK:
		(result["errors"] as Array).append("The loaded regiment snapshot is invalid.")
		return
	var regiment_result := RegimentCalculator.new().calculate(regiment_state, regiment_repository)
	result["regiment_name"] = regiment_state.regiment_name
	for error: Variant in regiment_result.get("errors", []):
		(result["errors"] as Array).append("Regiment: %s" % str(error))
	for choice: Dictionary in regiment_result.get("unresolved_choices", []):
		var unresolved := choice.duplicate(true)
		unresolved["scope"] = "regiment"
		(result["unresolved_choices"] as Array).append(unresolved)

	for characteristic: Variant in (regiment_result.get("characteristics", {}) as Dictionary):
		_add_characteristic_modifier(result, str(characteristic), int(regiment_result["characteristics"][characteristic]), "regiment")
	for skill: Dictionary in regiment_result.get("skills", []):
		_add_grants(result["skills"] as Dictionary, str(skill.get("id", "")), int(skill.get("grants", 1)))
	for talent: Dictionary in regiment_result.get("talents", []):
		_add_grants(result["talents"] as Dictionary, str(talent.get("id", "")), int(talent.get("grants", 1)))
	for aptitude: Variant in regiment_result.get("aptitudes", []):
		_add_grants(result["aptitudes"] as Dictionary, str(aptitude), 1)
	for special_rule: Dictionary in regiment_result.get("special_rules", []):
		(result["special_rules"] as Array).append(special_rule.duplicate(true))
	for item: Dictionary in regiment_result.get("equipment", []):
		_add_equipment(result["equipment"] as Dictionary, item, regiment_repository, character_repository, "standard_issue")
	result["wounds_modifier"] = int(regiment_result.get("wounds", 0))
	for source: Dictionary in regiment_result.get("sources", []):
		_add_source(source, result, str(source.get("label", regiment_repository.get_source_label(source))))

	var regiment_choices: Array = regiment_result.get("character_creation_choices", []) as Array
	for choice_value: Variant in regiment_choices:
		if choice_value is Dictionary:
			(result["regiment_choices"] as Array).append((choice_value as Dictionary).duplicate(true))
	_process_choices(regiment_choices, state.regiment_resolutions, "regiment", unique_groups, result, regiment_repository, character_repository)


func _process_choices(choices: Array, resolutions: Dictionary, scope: String, unique_groups: Dictionary, result: Dictionary, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository) -> void:
	for choice_value: Variant in choices:
		if not choice_value is Dictionary:
			continue
		var choice := choice_value as Dictionary
		var choice_id := str(choice.get("id", ""))
		var selected: Array[String] = []
		for answer_id: Variant in resolutions.get(choice_id, []):
			selected.append(str(answer_id))
		var minimum := int(choice.get("minimum", 1))
		var maximum := int(choice.get("maximum", 1))
		if selected.size() < minimum:
			var unresolved := choice.duplicate(true)
			unresolved["scope"] = scope
			(result["unresolved_choices"] as Array).append(unresolved)
			if selected.is_empty():
				continue
		if maximum > 0 and selected.size() > maximum:
			(result["errors"] as Array).append("%s allows at most %d answer(s)." % [choice.get("prompt", choice_id), maximum])

		var labels: Array[String] = []
		for answer_id in selected:
			var answer := _find_choice_option(choice, answer_id)
			if answer.is_empty():
				(result["errors"] as Array).append("Choice '%s' contains an unknown answer '%s'." % [choice_id, answer_id])
				continue
			var unique_group := str(choice.get("unique_group", ""))
			if not unique_group.is_empty():
				var unique_key := "%s:%s" % [unique_group, answer_id]
				if unique_groups.has(unique_key):
					(result["errors"] as Array).append("%s must use a different answer from %s." % [choice.get("prompt", choice_id), unique_groups[unique_key]])
				else:
					unique_groups[unique_key] = str(choice.get("prompt", choice_id))
			labels.append(str(answer.get("label", answer_id)))
			_apply_effects(answer.get("effects", {}) as Dictionary, result, regiment_repository, character_repository, scope)
		if not labels.is_empty():
			(result["resolved_choices"] as Array).append({
				"id": choice_id,
				"prompt": str(choice.get("prompt", choice_id)),
				"scope": scope,
				"answers": labels
			})


func _process_duplicate_aptitudes(state: CharacterState, result: Dictionary, unique_groups: Dictionary, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository) -> void:
	var aptitude_grants := result["aptitudes"] as Dictionary
	var duplicates: Array[String] = []
	for aptitude: Variant in aptitude_grants:
		for duplicate_index in range(maxi(int(aptitude_grants[aptitude]) - 1, 0)):
			duplicates.append("%s|%d" % [aptitude, duplicate_index + 1])
	duplicates.sort()
	for duplicate_key in duplicates:
		var parts := duplicate_key.split("|")
		var aptitude_name := parts[0]
		var choice_id := "duplicate_aptitude_%s_%s" % [_slug(aptitude_name), parts[1]]
		var options: Array[Dictionary] = []
		for replacement in CHARACTERISTIC_APTITUDES:
			if int(aptitude_grants.get(replacement, 0)) > 0:
				continue
			options.append({
				"id": _slug(replacement),
				"label": replacement,
				"effects": { "aptitudes": [replacement] }
			})
		var choice := {
			"id": choice_id,
			"prompt": "Replacement for duplicate %s Aptitude" % aptitude_name,
			"minimum": 1,
			"maximum": 1,
			"unique_group": "duplicate_aptitude_replacements",
			"options": options
		}
		(result["speciality_choices"] as Array).append(choice)
		_process_choices([choice], state.speciality_resolutions, "speciality", unique_groups, result, regiment_repository, character_repository)


func _apply_effects(effects: Dictionary, result: Dictionary, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository, modifier_source: String) -> void:
	for characteristic: Variant in (effects.get("characteristics", {}) as Dictionary):
		_add_characteristic_modifier(result, str(characteristic), int(effects["characteristics"][characteristic]), modifier_source)
	for skill_id: Variant in effects.get("skills", []):
		_add_grants(result["skills"] as Dictionary, str(skill_id), 1)
	for talent_id: Variant in effects.get("talents", []):
		_add_grants(result["talents"] as Dictionary, str(talent_id), 1)
	for aptitude: Variant in effects.get("aptitudes", []):
		_add_grants(result["aptitudes"] as Dictionary, str(aptitude), 1)
	for rule_value: Variant in effects.get("special_rules", []):
		if rule_value is Dictionary:
			(result["special_rules"] as Array).append((rule_value as Dictionary).duplicate(true))
	for equipment_value: Variant in effects.get("equipment", []):
		if equipment_value is Dictionary:
			_add_equipment(result["equipment"] as Dictionary, equipment_value as Dictionary, regiment_repository, character_repository, "speciality_issue" if modifier_source == "speciality" else "standard_issue")


func _add_characteristic_modifier(result: Dictionary, characteristic: String, value: int, source: String) -> void:
	var target_key := "regiment_characteristic_modifiers" if source == "regiment" else "speciality_characteristic_modifiers"
	var target := result[target_key] as Dictionary
	target[characteristic] = int(target.get(characteristic, 0)) + value


func _calculate_characteristics(state: CharacterState, result: Dictionary) -> void:
	var missing: Array[String] = []
	for characteristic in CharacterState.CHARACTERISTIC_ORDER:
		if not state.base_characteristics.has(characteristic):
			missing.append(characteristic)
			continue
		var base := int(state.base_characteristics[characteristic])
		if base < 22 or base > 40:
			(result["warnings"] as Array).append("%s base value %d is outside the usual 2d10+20 range." % [characteristic, base])
		var manual := int(state.manual_adjustments.get(characteristic, 0))
		if manual != 0:
			(result["warnings"] as Array).append("%s has a manual adjustment of %s." % [characteristic, _signed(manual)])
		var final_value := base
		final_value += int((result["regiment_characteristic_modifiers"] as Dictionary).get(characteristic, 0))
		final_value += int((result["speciality_characteristic_modifiers"] as Dictionary).get(characteristic, 0))
		final_value += manual
		(result["characteristics"] as Dictionary)[characteristic] = final_value
		(result["characteristic_bonuses"] as Dictionary)[characteristic] = floori(float(final_value) / 10.0)
	if not missing.is_empty():
		(result["errors"] as Array).append("Enter all nine base Characteristics. Missing: %s." % ", ".join(missing))


func _calculate_derived_values(state: CharacterState, speciality: Dictionary, result: Dictionary) -> void:
	if not speciality.is_empty():
		if state.wounds_roll < 1 or state.wounds_roll > 5:
			(result["errors"] as Array).append("Enter the physical 1d5 Wounds roll (1-5).")
		else:
			result["wounds"] = int(speciality.get("wounds_base", 0)) + state.wounds_roll + int(result["wounds_modifier"]) + int(result.get("advancement_wounds_bonus", 0))
	if state.fate_roll < 1 or state.fate_roll > 10:
		(result["errors"] as Array).append("Enter the physical 1d10 Fate roll (1-10).")
	elif state.fate_roll <= 7:
		result["fate_points"] = 1
	elif state.fate_roll <= 9:
		result["fate_points"] = 2
	else:
		result["fate_points"] = 3

	if (result["characteristic_bonuses"] as Dictionary).has("Agility"):
		var agility_bonus := int(result["characteristic_bonuses"]["Agility"])
		if agility_bonus <= 0:
			result["movement"] = { "half": 0.5, "full": 1, "charge": 2, "run": 3 }
		else:
			result["movement"] = {
				"half": agility_bonus,
				"full": agility_bonus * 2,
				"charge": agility_bonus * 3,
				"run": agility_bonus * 6
			}


func _finalize_aggregates(result: Dictionary, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository) -> void:
	var skill_output: Array[Dictionary] = []
	for skill_id: Variant in (result["skills"] as Dictionary):
		var grants := int(result["skills"][skill_id])
		var catalog := _catalog_entry("skills", str(skill_id), regiment_repository, character_repository)
		var rank := mini(grants, int(catalog.get("maximum_rank", 4)))
		var rank_label := "Known"
		if rank == 2:
			rank_label = "Trained (+10)"
		elif rank == 3:
			rank_label = "Experienced (+20)"
		elif rank >= 4:
			rank_label = "Veteran (+30)"
		skill_output.append({ "id": str(skill_id), "name": _catalog_name("skills", str(skill_id), regiment_repository, character_repository), "grants": grants, "rank": rank, "rank_label": rank_label })
	skill_output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	result["skills"] = skill_output

	var talent_output: Array[Dictionary] = []
	for talent_id: Variant in (result["talents"] as Dictionary):
		var grants := int(result["talents"][talent_id])
		var catalog := _catalog_entry("talents", str(talent_id), regiment_repository, character_repository)
		var stackable := bool(catalog.get("stackable", false)) or bool(catalog.get("repeatable", false))
		talent_output.append({ "id": str(talent_id), "name": _catalog_name("talents", str(talent_id), regiment_repository, character_repository), "grants": grants, "count": grants if stackable else 1, "stackable": stackable })
	talent_output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	result["talents"] = talent_output
	result["xp_remaining"] = int(result["xp_budget"]) - int(result["xp_spent"])

	var aptitude_output: Array[String] = []
	for aptitude: Variant in (result["aptitudes"] as Dictionary):
		aptitude_output.append(str(aptitude))
	aptitude_output.sort()
	result["aptitudes"] = aptitude_output

	var equipment_output: Array[Dictionary] = []
	for equipment_key: Variant in (result["equipment"] as Dictionary):
		equipment_output.append(result["equipment"][equipment_key] as Dictionary)
	equipment_output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	result["equipment"] = equipment_output


func _calculate_duplicate_talent_compensation(result: Dictionary, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository) -> void:
	for talent_id: Variant in (result["talents"] as Dictionary):
		var grants := int(result["talents"][talent_id])
		var catalog := _catalog_entry("talents", str(talent_id), regiment_repository, character_repository)
		var stackable := bool(catalog.get("stackable", false)) or bool(catalog.get("repeatable", false))
		if not stackable and grants > 1:
			result["bonus_xp"] = int(result["bonus_xp"]) + ((grants - 1) * 100)
	result["xp_budget"] = int(result["xp_budget"]) + int(result["bonus_xp"])
	result["xp_remaining"] = int(result["xp_budget"])


func _add_advancement_sources(result: Dictionary, character_repository: CharacterDataRepository) -> void:
	for purchase: Dictionary in result.get("purchased_advances", []):
		if not bool(purchase.get("valid", false)):
			continue
		var source := purchase.get("source", {}) as Dictionary
		_add_source(source, result, character_repository.get_source_label(source))


func _add_equipment(target: Dictionary, entry: Dictionary, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository, origin: String) -> void:
	var item_id := str(entry.get("id", ""))
	if item_id.is_empty():
		return
	var scope := str(entry.get("scope", "per_character"))
	var definition := character_repository.equipment_repository.get_item(item_id)
	var craftsmanship := str(entry.get("craftsmanship", definition.get("craftsmanship", "Common")))
	var key := "%s|%s|%s" % [item_id, scope, craftsmanship]
	if not target.has(key):
		target[key] = {
			"id": item_id,
			"name": _catalog_name("equipment", item_id, regiment_repository, character_repository),
			"quantity": 0,
			"scope": scope,
			"craftsmanship": craftsmanship,
			"origins": [],
			"origin_quantities": {}
		}
	var output := target[key] as Dictionary
	var quantity := int(entry.get("quantity", 1))
	output["quantity"] = int(output.get("quantity", 0)) + quantity
	if origin not in (output["origins"] as Array):
		(output["origins"] as Array).append(origin)
	var origin_quantities := output["origin_quantities"] as Dictionary
	origin_quantities[origin] = int(origin_quantities.get(origin, 0)) + quantity


func _add_grants(target: Dictionary, entry_id: String, count: int) -> void:
	if entry_id.is_empty() or count <= 0:
		return
	target[entry_id] = int(target.get(entry_id, 0)) + count


func _find_choice_option(choice: Dictionary, option_id: String) -> Dictionary:
	for value: Variant in choice.get("options", []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) == option_id:
			return value as Dictionary
	return {}


func _catalog_entry(catalog: String, entry_id: String, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository) -> Dictionary:
	var character_entry := character_repository.get_catalog_entry(catalog, entry_id)
	return character_entry if not character_entry.is_empty() else regiment_repository.get_catalog_entry(catalog, entry_id)


func _catalog_name(catalog: String, entry_id: String, regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository) -> String:
	var character_entry := character_repository.get_catalog_entry(catalog, entry_id)
	return character_repository.get_catalog_name(catalog, entry_id) if not character_entry.is_empty() else regiment_repository.get_catalog_name(catalog, entry_id)


func _add_source(source_reference: Dictionary, result: Dictionary, label: String) -> void:
	if source_reference.is_empty():
		return
	var key := "%s:%s:%s" % [source_reference.get("book", ""), source_reference.get("page", 0), source_reference.get("page_end", 0)]
	var keys := result["_source_keys"] as Dictionary
	if keys.has(key):
		return
	keys[key] = true
	var output := source_reference.duplicate(true)
	output["label"] = label
	(result["sources"] as Array).append(output)


func _slug(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace("-", "_")


func _signed(value: int) -> String:
	return "+%d" % value if value >= 0 else str(value)
