class_name RegimentCalculator
extends RefCounted

## Pure rules engine: combines selected data and returns a UI/export-ready result.
## Like CharacterCalculator, it must remain deterministic and independent of UI.


## Validates selection counts, compatibility, budget, doctrines, and choices,
## then aggregates every supported effect into normalized result collections.
func calculate(state: RegimentState, repository: RegimentDataRepository) -> Dictionary:
	var result := {
		"valid": false,
		"points_budget": int(repository.data.get("budget", 12)),
		"points_spent": 0,
		"points_remaining": int(repository.data.get("budget", 12)),
		"doctrine_slots_used": 0,
		"doctrine_slots_maximum": int(repository.data.get("maximum_doctrines", 3)),
		"optional_doctrines_used": 0,
		"optional_doctrines_maximum": maxi(int(repository.data.get("maximum_doctrines", 3)) - 1, 0),
		"selected_options": [],
		"characteristics": {},
		"skills": {},
		"talents": {},
		"aptitudes": {},
		"special_rules": [],
		"wounds": 0,
		"bonus_xp": 0,
		"standard_kit_points_base": 30,
		"standard_kit_points": 30,
		"equipment": {},
		"sources": [],
		"resolved_choices": [],
		"unresolved_choices": [],
		"character_creation_choices": [],
		"errors": [],
		"warnings": []
	}
	result["_special_rules_by_name"] = {}
	result["_source_keys"] = {}
	result["_equipment_adjustments"] = []

	_apply_effects(repository.data.get("base_effects", {}) as Dictionary, result, repository)
	_add_source((repository.data.get("base_effects", {}) as Dictionary).get("source", {}) as Dictionary, result, repository)
	var rule_references := repository.data.get("rule_references", {}) as Dictionary
	_add_source(rule_references.get("regiment_budget", {}) as Dictionary, result, repository)
	_add_source(rule_references.get("doctrine_limit", {}) as Dictionary, result, repository)

	var selected_ids := state.get_all_selected_ids()
	_validate_category_counts(state, repository, result)
	result["optional_doctrines_used"] = state.get_selected_for_category("training_doctrine").size() + state.get_selected_for_category("equipment_doctrine").size()

	for category in repository.get_category_order():
		var rule := repository.get_selection_rule(category)
		for option_id in state.get_selected_for_category(category):
			var option := repository.get_option(option_id)
			if option.is_empty():
				(result["errors"] as Array).append("Saved selection '%s' is not present in the current rules data." % option_id)
				continue
			(result["selected_options"] as Array).append(option)
			result["points_spent"] = int(result["points_spent"]) + int(option.get("cost", 0))
			if bool(rule.get("counts_as_doctrine", false)):
				result["doctrine_slots_used"] = int(result["doctrine_slots_used"]) + 1
			_validate_option_relationships(option, selected_ids, repository, result)
			_apply_effects(option.get("effects", {}) as Dictionary, result, repository)
			_add_source(option.get("source", {}) as Dictionary, result, repository)

	result["points_remaining"] = int(repository.data.get("budget", 12)) - int(result["points_spent"])
	if int(result["points_remaining"]) < 0:
		(result["errors"] as Array).append("Regiment is over budget by %d point(s)." % -int(result["points_remaining"]))
	if int(result["optional_doctrines_used"]) > int(result["optional_doctrines_maximum"]):
		(result["errors"] as Array).append("Too many optional doctrines: %d selected, maximum %d (Regiment Type is tracked separately)." % [result["optional_doctrines_used"], result["optional_doctrines_maximum"]])

	_process_choices(state, repository, result)
	_apply_equipment_adjustments(result["_equipment_adjustments"] as Array, result)
	result["standard_kit_points"] = int(result["standard_kit_points_base"]) + (maxi(int(result["points_remaining"]), 0) * 2)
	_finalize_aggregates(result, repository)
	result.erase("_special_rules_by_name")
	result.erase("_source_keys")
	result.erase("_equipment_adjustments")
	result["valid"] = (result["errors"] as Array).is_empty() and (result["unresolved_choices"] as Array).is_empty()
	return result


func _validate_category_counts(state: RegimentState, repository: RegimentDataRepository, result: Dictionary) -> void:
	for category in repository.get_category_order():
		var rule := repository.get_selection_rule(category)
		var count := state.get_selected_for_category(category).size()
		var minimum := int(rule.get("minimum", 0))
		var maximum := int(rule.get("maximum", 0))
		var label := str(rule.get("label", category.capitalize()))
		if count < minimum:
			(result["errors"] as Array).append("%s requires %d selection(s)." % [label, minimum])
		if maximum > 0 and count > maximum:
			(result["errors"] as Array).append("%s allows at most %d selection(s)." % [label, maximum])


func _validate_option_relationships(option: Dictionary, selected_ids: Array[String], repository: RegimentDataRepository, result: Dictionary) -> void:
	var requirements := option.get("requirements", {}) as Dictionary
	for required: Variant in requirements.get("all", []):
		if str(required) not in selected_ids:
			(result["errors"] as Array).append("%s requires %s." % [option.get("name", option.get("id")), _option_name(str(required), repository)])
	var any_requirements: Array = requirements.get("any", []) as Array
	if not any_requirements.is_empty():
		var met := false
		for required: Variant in any_requirements:
			if str(required) in selected_ids:
				met = true
				break
		if not met:
			var names: Array[String] = []
			for required: Variant in any_requirements:
				names.append(_option_name(str(required), repository))
			(result["errors"] as Array).append("%s requires one of: %s." % [option.get("name", option.get("id")), ", ".join(names)])

	for excluded: Variant in option.get("excludes", []):
		if str(excluded) in selected_ids:
			var message := "%s cannot be combined with %s." % [option.get("name", option.get("id")), _option_name(str(excluded), repository)]
			if message not in result["errors"]:
				(result["errors"] as Array).append(message)


func _process_choices(state: RegimentState, repository: RegimentDataRepository, result: Dictionary) -> void:
	var unique_groups: Dictionary = {}
	for option: Dictionary in result["selected_options"]:
		for value: Variant in option.get("choices", []):
			if not value is Dictionary:
				continue
			var choice := value as Dictionary
			if str(choice.get("scope", "regiment")) == "per_character":
				(result["character_creation_choices"] as Array).append(choice.duplicate(true))
				continue
			var choice_id := str(choice.get("id", ""))
			var selected := state.get_choice(choice_id)
			var minimum := int(choice.get("minimum", 1))
			var maximum := int(choice.get("maximum", 1))
			if selected.size() < minimum:
				(result["unresolved_choices"] as Array).append(choice)
				continue
			if maximum > 0 and selected.size() > maximum:
				(result["errors"] as Array).append("%s allows at most %d answer(s)." % [choice.get("prompt", choice_id), maximum])

			var resolved_labels: Array[String] = []
			for selected_id in selected:
				var choice_option := _find_choice_option(choice, selected_id)
				if choice_option.is_empty():
					(result["errors"] as Array).append("Choice '%s' contains an unknown answer '%s'." % [choice_id, selected_id])
					continue
				resolved_labels.append(str(choice_option.get("label", selected_id)))
				var unique_group := str(choice.get("unique_group", ""))
				if not unique_group.is_empty():
					var unique_key := "%s:%s" % [unique_group, selected_id]
					if unique_groups.has(unique_key):
						(result["errors"] as Array).append("%s must use a different answer from %s." % [choice.get("prompt", choice_id), unique_groups[unique_key]])
					else:
						unique_groups[unique_key] = str(choice.get("prompt", choice_id))
				_apply_effects(choice_option.get("effects", {}) as Dictionary, result, repository)
			if not resolved_labels.is_empty():
				(result["resolved_choices"] as Array).append({
					"id": choice_id,
					"prompt": str(choice.get("prompt", choice_id)),
					"scope": str(choice.get("scope", "regiment")),
					"answers": resolved_labels
				})


func _find_choice_option(choice: Dictionary, option_id: String) -> Dictionary:
	for value: Variant in choice.get("options", []):
		if value is Dictionary and str(value.get("id", "")) == option_id:
			return value as Dictionary
	return {}


func _apply_effects(effects: Dictionary, result: Dictionary, repository: RegimentDataRepository) -> void:
	var characteristics := result["characteristics"] as Dictionary
	for name: Variant in (effects.get("characteristics", {}) as Dictionary):
		characteristics[str(name)] = int(characteristics.get(str(name), 0)) + int(effects["characteristics"][name])

	var skill_grants := result["skills"] as Dictionary
	for skill_id: Variant in effects.get("skills", []):
		var id := str(skill_id)
		skill_grants[id] = int(skill_grants.get(id, 0)) + 1

	var talent_grants := result["talents"] as Dictionary
	for talent_id: Variant in effects.get("talents", []):
		var id := str(talent_id)
		talent_grants[id] = int(talent_grants.get(id, 0)) + 1

	var aptitude_grants := result["aptitudes"] as Dictionary
	for aptitude: Variant in effects.get("aptitudes", []):
		aptitude_grants[str(aptitude)] = true

	var rule_map := result["_special_rules_by_name"] as Dictionary
	for value: Variant in effects.get("special_rules", []):
		if value is Dictionary:
			var special_rule := value as Dictionary
			rule_map[str(special_rule.get("name", "Unnamed rule"))] = special_rule

	result["wounds"] = int(result["wounds"]) + int(effects.get("wounds", 0))
	if effects.has("standard_kit_points_base"):
		result["standard_kit_points_base"] = int(effects["standard_kit_points_base"])
	_apply_equipment(effects.get("equipment", []) as Array, result, repository)
	(result["_equipment_adjustments"] as Array).append_array(effects.get("equipment_adjustments", []) as Array)


func _apply_equipment(entries: Array, result: Dictionary, repository: RegimentDataRepository) -> void:
	var equipment := result["equipment"] as Dictionary
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		var item_id := str(entry.get("id", ""))
		var scope := str(entry.get("scope", "per_character"))
		var slot := str(entry.get("slot", ""))
		if bool(entry.get("replace_slot", false)) and not slot.is_empty():
			for existing_key: Variant in equipment.keys():
				var existing := equipment[existing_key] as Dictionary
				if str(existing.get("slot", "")) == slot and str(existing.get("scope", "")) == scope:
					equipment.erase(existing_key)

		var key := "%s|%s|%s" % [item_id, scope, slot]
		var quantity := int(entry.get("quantity", 1))
		var merge_mode := str(entry.get("merge", "add"))
		if equipment.has(key):
			var existing := equipment[key] as Dictionary
			if merge_mode == "replace":
				existing["quantity"] = quantity
			elif merge_mode != "unique":
				existing["quantity"] = int(existing.get("quantity", 0)) + quantity
			equipment[key] = existing
		else:
			var output := entry.duplicate(true)
			var catalog := repository.get_catalog_entry("equipment", item_id)
			output["name"] = repository.get_catalog_name("equipment", item_id)
			if not output.has("tags") and catalog.has("tags"):
				output["tags"] = (catalog.get("tags", []) as Array).duplicate()
			elif not output.has("tags") and str(catalog.get("category", "")) == "grenade_missile" and item_id.ends_with("_grenade"):
				output["tags"] = ["grenade"]
			if catalog.has("ammunition_id"):
				output["ammunition_id"] = str(catalog["ammunition_id"])
			output["quantity"] = quantity
			equipment[key] = output


func _apply_equipment_adjustments(adjustments: Array, result: Dictionary) -> void:
	var equipment := result["equipment"] as Dictionary
	for value: Variant in adjustments:
		if not value is Dictionary:
			continue
		var adjustment := value as Dictionary
		var target := str(adjustment.get("target", ""))
		var tag := str(adjustment.get("tag", ""))
		var quantity := int(adjustment.get("quantity", 0))
		if target == "main_weapon_ammunition":
			var ammunition_targets: Dictionary = {}
			for key: Variant in equipment:
				var weapon := equipment[key] as Dictionary
				if str(weapon.get("slot", "")) == "main_weapon" and not str(weapon.get("ammunition_id", "")).is_empty():
					ammunition_targets["%s|%s" % [weapon["ammunition_id"], weapon.get("scope", "per_character")]] = true
			for key: Variant in equipment:
				var item := equipment[key] as Dictionary
				var ammunition_key := "%s|%s" % [item.get("id", ""), item.get("scope", "per_character")]
				if ammunition_targets.has(ammunition_key):
					item["quantity"] = int(item.get("quantity", 0)) + quantity
					equipment[key] = item
			continue
		for key: Variant in equipment:
			var item := equipment[key] as Dictionary
			if not tag.is_empty() and tag in (item.get("tags", []) as Array):
				item["quantity"] = int(item.get("quantity", 0)) + quantity
				equipment[key] = item


func _add_source(source_reference: Dictionary, result: Dictionary, repository: RegimentDataRepository) -> void:
	if source_reference.is_empty():
		return
	var key := "%s:%s:%s" % [source_reference.get("book", ""), source_reference.get("page", 0), source_reference.get("page_end", 0)]
	var keys := result["_source_keys"] as Dictionary
	if keys.has(key):
		return
	keys[key] = true
	var output := source_reference.duplicate(true)
	output["label"] = repository.get_source_label(source_reference)
	(result["sources"] as Array).append(output)


func _finalize_aggregates(result: Dictionary, repository: RegimentDataRepository) -> void:
	var skill_output: Array[Dictionary] = []
	var has_duplicate_grant := false
	for skill_id: Variant in (result["skills"] as Dictionary):
		var grants := int(result["skills"][skill_id])
		var catalog := repository.get_catalog_entry("skills", str(skill_id))
		var maximum_rank := int(catalog.get("maximum_rank", 4))
		var rank := mini(grants, maximum_rank)
		var rank_label := "Known"
		if rank == 2:
			rank_label = "Trained (+10)"
		elif rank == 3:
			rank_label = "Experienced (+20)"
		elif rank >= 4:
			rank_label = "Veteran (+30)"
		if grants > 1:
			has_duplicate_grant = true
		skill_output.append({
			"id": str(skill_id),
			"name": repository.get_catalog_name("skills", str(skill_id)),
			"grants": grants,
			"rank": rank,
			"rank_label": rank_label
		})
	skill_output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	result["skills"] = skill_output
	if not skill_output.is_empty():
		var references := repository.data.get("rule_references", {}) as Dictionary
		_add_source(references.get("skill_ranks", {}) as Dictionary, result, repository)

	var talent_output: Array[Dictionary] = []
	for talent_id: Variant in (result["talents"] as Dictionary):
		var grants := int(result["talents"][talent_id])
		var catalog := repository.get_catalog_entry("talents", str(talent_id))
		var stackable := bool(catalog.get("stackable", false))
		if not stackable and grants > 1:
			result["bonus_xp"] = int(result["bonus_xp"]) + ((grants - 1) * 100)
			has_duplicate_grant = true
		talent_output.append({
			"id": str(talent_id),
			"name": repository.get_catalog_name("talents", str(talent_id)),
			"grants": grants,
			"count": grants if stackable else 1,
			"stackable": stackable
		})
	talent_output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	result["talents"] = talent_output
	if has_duplicate_grant:
		var references := repository.data.get("rule_references", {}) as Dictionary
		_add_source(references.get("duplicate_grants", {}) as Dictionary, result, repository)

	var aptitude_output: Array[String] = []
	for aptitude: Variant in (result["aptitudes"] as Dictionary):
		aptitude_output.append(str(aptitude))
	aptitude_output.sort()
	result["aptitudes"] = aptitude_output

	var equipment_output: Array[Dictionary] = []
	for key: Variant in (result["equipment"] as Dictionary):
		equipment_output.append(result["equipment"][key] as Dictionary)
	equipment_output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	result["equipment"] = equipment_output

	var rule_output: Array[Dictionary] = []
	for key: Variant in (result["_special_rules_by_name"] as Dictionary):
		rule_output.append(result["_special_rules_by_name"][key] as Dictionary)
	rule_output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	result["special_rules"] = rule_output


func _option_name(option_id: String, repository: RegimentDataRepository) -> String:
	var option := repository.get_option(option_id)
	return str(option.get("name", option_id))
