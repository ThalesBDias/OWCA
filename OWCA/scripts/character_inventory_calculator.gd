class_name CharacterInventoryCalculator
extends RefCounted

## Pure projection of authoritative owned inventory through immutable rules.


func calculate(state: CharacterState, character_calculation: Dictionary, equipment_repository: EquipmentDataRepository, rules_repository: RefCounted) -> Dictionary:
	var result := {
		"valid": true,
		"items": [],
		"unresolved_items": [],
		"unknown_weight_items": [],
		"armour_by_location": {
			"Head": { "ap": 0, "sources": [] },
			"Arms": { "ap": 0, "sources": [] },
			"Body": { "ap": 0, "sources": [] },
			"Legs": { "ap": 0, "sources": [] }
		},
		"encumbrance": {},
		"warnings": []
	}
	var known_weight := 0.0
	for owned: Dictionary in state.owned_items:
		var item := owned.duplicate(true)
		var definition_id := str(owned.get("definition_id", ""))
		item["id"] = definition_id
		var custodian := owned.get("custodian", {}) as Dictionary
		var affects_character := str(custodian.get("type", "")) == "character"
		var carried := str(owned.get("location", "")) in ["equipped", "carried"]
		var definition := equipment_repository.get_item(definition_id)
		if definition.is_empty():
			item["name"] = "Missing definition: %s" % definition_id
			(result["unresolved_items"] as Array).append(item.duplicate(true))
			(result["items"] as Array).append(item)
			if affects_character and carried:
				(result["unknown_weight_items"] as Array).append(item.duplicate(true))
			result["valid"] = false
			continue
		item["name"] = str(definition.get("name", definition_id))
		item["category"] = str(definition.get("category", ""))
		(result["items"] as Array).append(item)
		if affects_character and carried:
			if definition.has("weight_kg"):
				known_weight += float(definition.get("weight_kg", 0.0)) * float(owned.get("quantity", 1))
			else:
				(result["unknown_weight_items"] as Array).append(item.duplicate(true))
		if affects_character and str(owned.get("location", "")) == "equipped" and definition.has("armour"):
			_apply_armour(result["armour_by_location"] as Dictionary, owned, definition)
	var bonuses := character_calculation.get("characteristic_bonuses", {}) as Dictionary
	var bonus_sum := int(bonuses.get("Strength", 0)) + int(bonuses.get("Toughness", 0))
	var capacity: Dictionary = rules_repository.call("get_capacity", bonus_sum)
	var carrying_limit := float(capacity.get("carrying_kg", 0.0))
	var lifting_limit := float(capacity.get("lifting_kg", 0.0))
	var complete := (result["unknown_weight_items"] as Array).is_empty()
	var status := "partial"
	if complete:
		if known_weight <= carrying_limit:
			status = "within_limit"
		elif known_weight <= lifting_limit:
			status = "encumbered"
		else:
			status = "over_lift_limit"
	result["encumbrance"] = {
		"known_weight_kg": snappedf(known_weight, 0.01),
		"complete": complete,
		"bonus_sum": bonus_sum,
		"carrying_limit_kg": carrying_limit,
		"lifting_limit_kg": lifting_limit,
		"status": status
	}
	if not complete:
		(result["warnings"] as Array).append("Carried weight is partial because one or more items have no verified weight.")
	return result


func _apply_armour(locations: Dictionary, owned: Dictionary, definition: Dictionary) -> void:
	var armour := definition.get("armour", {}) as Dictionary
	var ap := int(armour.get("ap", 0))
	for location_value: Variant in armour.get("locations", []):
		var location := str(location_value)
		if not locations.has(location):
			continue
		var record := locations[location] as Dictionary
		if ap > int(record.get("ap", 0)):
			record["ap"] = ap
			record["sources"] = [str(owned.get("instance_id", ""))]
		elif ap == int(record.get("ap", 0)) and ap > 0:
			(record["sources"] as Array).append(str(owned.get("instance_id", "")))
