class_name CharacterInventoryService
extends RefCounted

## Owns deterministic mutations to a character's authoritative inventory.
## UI controllers provide timestamps so tests and migrations remain repeatable.


## Converts the calculator's starting grants into authoritative owned records.
## Once prepared, repeated calls are deliberately no-ops so durable IDs and
## the original issue ledger cannot be duplicated accidentally.
func materialize_starting_loadout(state: CharacterState, grants: Array, repository: EquipmentDataRepository, timestamp_utc: String) -> Dictionary:
	if state.loadout_state != CharacterState.LOADOUT_UNPREPARED:
		return { "error": OK, "message": "Starting loadout was already prepared." }
	if timestamp_utc.strip_edges().is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "Inventory events require a UTC timestamp." }
	var prepared_grants: Array[Dictionary] = []
	var prepared_items: Array[Dictionary] = []
	var prepared_events: Array[Dictionary] = []
	var grant_index := 0
	for grant_value: Variant in grants:
		if not grant_value is Dictionary:
			return { "error": ERR_INVALID_DATA, "message": "Starting equipment contains a malformed grant." }
		var grant := grant_value as Dictionary
		var definition_id := str(grant.get("id", ""))
		var quantity := int(grant.get("quantity", 1))
		var scope := str(grant.get("scope", "per_character"))
		if not repository.has_item(definition_id) or quantity <= 0 or scope not in ["per_character", "per_squad"]:
			return { "error": ERR_INVALID_DATA, "message": "Starting equipment grant '%s' is invalid." % definition_id }
		var definition := repository.get_item(definition_id)
		var craftsmanship := str(grant.get("craftsmanship", definition.get("craftsmanship", "Common")))
		if craftsmanship not in CharacterState.CRAFTSMANSHIP_VALUES or (str(definition.get("category", "")) == "grenade_missile" and craftsmanship != "Common"):
			return { "error": ERR_INVALID_DATA, "message": "Starting equipment grant '%s' has invalid craftsmanship." % definition_id }
		var origin_splits := _starting_origin_splits(grant, quantity)
		if origin_splits.is_empty():
			return { "error": ERR_INVALID_DATA, "message": "Starting equipment grant '%s' has inconsistent issue origins." % definition_id }
		for split: Dictionary in origin_splits:
			grant_index += 1
			var split_quantity := int(split.get("quantity", 0))
			var grant_origin := str(split.get("origin", "standard_issue"))
			var separate_instances := str(definition.get("category", "")) in ["ranged_weapon", "melee_weapon", "armour"]
			var starting_location := "equipped" if str(definition.get("category", "")) == "armour" else "carried"
			var instance_count := split_quantity if separate_instances else 1
			var issued_instance_ids: Array[String] = []
			for _instance_index in instance_count:
				var item_quantity := 1 if separate_instances else split_quantity
				var item := _build_item(
					definition_id,
					item_quantity,
					craftsmanship,
					grant_origin,
					starting_location,
					{ "type": "squad" if scope == "per_squad" else "character", "id": "" },
					""
				)
				prepared_items.append(item)
				issued_instance_ids.append(str(item.get("instance_id", "")))
				prepared_events.append(_build_event("issue", item, "Starting loadout", timestamp_utc))
			prepared_grants.append({
				"grant_id": "%s|%s|%d" % [definition_id, scope, grant_index],
				"definition_id": definition_id,
				"quantity": split_quantity,
				"scope": scope,
				"craftsmanship": craftsmanship,
				"origin": grant_origin,
				"issued_instance_ids": issued_instance_ids,
				"reconciliation": "present",
				"note": ""
			})
	state.starting_loadout = prepared_grants
	state.owned_items = prepared_items
	state.inventory_events = prepared_events
	state.loadout_state = CharacterState.LOADOUT_DRAFT
	state.changed.emit()
	return { "error": OK, "message": "Prepared %d starting equipment record(s)." % prepared_items.size() }


## Creates or renames the deliberately minimal Comrade identity used by item
## custody. It does not add campaign status or advancement fields.
func set_comrade(state: CharacterState, name: String) -> Dictionary:
	var clean_name := name.strip_edges()
	if clean_name.is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "Enter a Comrade name." }
	if state.comrade.is_empty():
		state.comrade = { "id": DocumentIdentity.generate(), "name": clean_name }
	else:
		state.comrade["name"] = clean_name
	state.changed.emit()
	return { "error": OK, "message": "Comrade identity saved." }


func transfer_item(state: CharacterState, instance_id: String, custodian_type: String, custodian_id: String, reason: String, timestamp_utc: String) -> Dictionary:
	var item := _find_item(state.owned_items, instance_id)
	if item.is_empty():
		return { "error": ERR_DOES_NOT_EXIST, "message": "Owned item was not found." }
	if not _custodian_is_available(state, custodian_type, custodian_id) or timestamp_utc.strip_edges().is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "The selected custodian is not available." }
	var new_custodian := { "type": custodian_type, "id": custodian_id if custodian_type == "comrade" else "" }
	if (item.get("custodian", {}) as Dictionary) == new_custodian:
		return { "error": OK, "message": "Equipment custody was already current." }
	item["custodian"] = new_custodian
	state.inventory_events.append(_build_event("transfer", item, reason, timestamp_utc))
	state.changed.emit()
	return { "error": OK, "message": "Equipment custody updated." }


func add_item(state: CharacterState, repository: EquipmentDataRepository, definition_id: String, quantity: int, craftsmanship: String, origin: String, location: String, custodian_type: String, custodian_id: String, reason: String, timestamp_utc: String, note: String = "") -> Dictionary:
	var definition := repository.get_item(definition_id)
	if definition.is_empty() or str(definition.get("category", "")) == "weapon_upgrade":
		return { "error": ERR_INVALID_DATA, "message": "Select a supported non-upgrade equipment definition." }
	if quantity <= 0 or craftsmanship not in CharacterState.CRAFTSMANSHIP_VALUES or origin not in CharacterState.ITEM_ORIGINS or location not in CharacterState.ITEM_LOCATIONS:
		return { "error": ERR_INVALID_PARAMETER, "message": "Equipment quantity, craftsmanship, origin, or location is invalid." }
	if str(definition.get("category", "")) == "grenade_missile" and craftsmanship != "Common":
		return { "error": ERR_INVALID_PARAMETER, "message": "Grenades and missiles use Common craftsmanship only." }
	if not _custodian_is_available(state, custodian_type, custodian_id) or timestamp_utc.strip_edges().is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "Equipment custodian or timestamp is invalid." }
	var custodian := { "type": custodian_type, "id": custodian_id if custodian_type == "comrade" else "" }
	var event_type := "exchange" if origin == "exchange" else ("issue" if origin == "later_issue" else "acquisition")
	var separate_instances := str(definition.get("category", "")) in ["ranged_weapon", "melee_weapon", "armour"]
	var instance_ids: Array[String] = []
	if not separate_instances:
		# Starting-grant rows remain exclusively owned by their grant. Otherwise a
		# later issue could merge into one and be deleted wholesale by a rebuild.
		var merge_target := _find_stack(state.owned_items, definition_id, craftsmanship, origin, location, custodian, _issued_instance_ids(state))
		if not merge_target.is_empty():
			merge_target["quantity"] = int(merge_target.get("quantity", 0)) + quantity
			if not note.strip_edges().is_empty():
				merge_target["note"] = note.strip_edges()
			state.inventory_events.append(_build_event(event_type, _event_quantity_snapshot(merge_target, quantity), reason, timestamp_utc))
			instance_ids.append(str(merge_target.get("instance_id", "")))
		else:
			var item := _build_item(definition_id, quantity, craftsmanship, origin, location, custodian, note)
			state.owned_items.append(item)
			state.inventory_events.append(_build_event(event_type, item, reason, timestamp_utc))
			instance_ids.append(str(item.get("instance_id", "")))
	else:
		for _index in quantity:
			var item := _build_item(definition_id, 1, craftsmanship, origin, location, custodian, note)
			state.owned_items.append(item)
			state.inventory_events.append(_build_event(event_type, item, reason, timestamp_utc))
			instance_ids.append(str(item.get("instance_id", "")))
	state.changed.emit()
	return { "error": OK, "message": "Equipment added.", "instance_ids": instance_ids }


func update_item(state: CharacterState, repository: EquipmentDataRepository, instance_id: String, quantity: int, craftsmanship: String, location: String, note: String, reason: String, timestamp_utc: String, origin_override: String = "") -> Dictionary:
	var item := _find_item(state.owned_items, instance_id)
	if item.is_empty():
		return { "error": ERR_DOES_NOT_EXIST, "message": "Owned item was not found." }
	var clean_craftsmanship := craftsmanship.strip_edges()
	var clean_note := note.strip_edges()
	var definition := repository.get_item(str(item.get("definition_id", "")))
	if quantity <= 0 or clean_craftsmanship not in CharacterState.CRAFTSMANSHIP_VALUES or location not in CharacterState.ITEM_LOCATIONS or timestamp_utc.strip_edges().is_empty() or (not origin_override.is_empty() and origin_override not in CharacterState.ITEM_ORIGINS):
		return { "error": ERR_INVALID_PARAMETER, "message": "Equipment update is invalid." }
	if not definition.is_empty() and str(definition.get("category", "")) == "grenade_missile" and clean_craftsmanship != "Common":
		return { "error": ERR_INVALID_PARAMETER, "message": "Grenades and missiles use Common craftsmanship only." }
	if not definition.is_empty() and str(definition.get("category", "")) in ["ranged_weapon", "melee_weapon", "armour"] and quantity != 1:
		return { "error": ERR_INVALID_PARAMETER, "message": "Weapons and armour must remain separate quantity-one instances." }
	var is_starting_instance := instance_id in _issued_instance_ids(state)
	var origin_changed := not origin_override.is_empty() and origin_override != str(item.get("origin", ""))
	if is_starting_instance and (quantity != int(item.get("quantity", 0)) or origin_changed):
		return { "error": ERR_INVALID_PARAMETER, "message": "A starting-grant item's quantity and origin are fixed; split/remove it or add later equipment separately." }
	var new_origin := str(item.get("origin", "")) if origin_override.is_empty() else origin_override
	if int(item.get("quantity", 0)) == quantity and str(item.get("craftsmanship", "")) == clean_craftsmanship and str(item.get("location", "")) == location and str(item.get("origin", "")) == new_origin and str(item.get("note", "")) == clean_note:
		return { "error": OK, "message": "Equipment record was already current." }
	item["quantity"] = quantity
	item["craftsmanship"] = clean_craftsmanship
	item["location"] = location
	item["origin"] = new_origin
	item["note"] = clean_note
	state.inventory_events.append(_build_event("correction", item, reason, timestamp_utc))
	state.changed.emit()
	return { "error": OK, "message": "Equipment record updated." }


## Splits a stack without fabricating an acquisition. Both resulting records
## keep the same definition and provenance while receiving independent IDs.
func split_stack(state: CharacterState, repository: EquipmentDataRepository, instance_id: String, split_quantity: int, reason: String, timestamp_utc: String) -> Dictionary:
	var item := _find_item(state.owned_items, instance_id)
	if item.is_empty():
		return { "error": ERR_DOES_NOT_EXIST, "message": "Owned stack was not found." }
	var definition := repository.get_item(str(item.get("definition_id", "")))
	if definition.is_empty() or str(definition.get("category", "")) in ["ranged_weapon", "melee_weapon", "armour"]:
		return { "error": ERR_INVALID_DATA, "message": "Weapons and armour cannot be split into quantity stacks." }
	var current_quantity := int(item.get("quantity", 0))
	if split_quantity <= 0 or split_quantity >= current_quantity or timestamp_utc.strip_edges().is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "Split quantity must leave a positive remainder." }
	item["quantity"] = current_quantity - split_quantity
	var separated := item.duplicate(true)
	separated["instance_id"] = DocumentIdentity.generate()
	separated["quantity"] = split_quantity
	state.owned_items.append(separated)
	for grant: Dictionary in state.starting_loadout:
		var issued_ids := grant.get("issued_instance_ids", []) as Array
		if instance_id in issued_ids:
			issued_ids.append(str(separated.get("instance_id", "")))
	state.inventory_events.append(_build_event("quantity", item, reason, timestamp_utc))
	state.inventory_events.append(_build_event("quantity", separated, "Split from %s: %s" % [instance_id, reason], timestamp_utc))
	state.changed.emit()
	return { "error": OK, "message": "Equipment stack split.", "instance_id": separated.get("instance_id", "") }


func remove_item(state: CharacterState, instance_id: String, reason: String, timestamp_utc: String) -> Dictionary:
	if timestamp_utc.strip_edges().is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "Inventory events require a UTC timestamp." }
	for index in state.owned_items.size():
		var item := state.owned_items[index]
		if str(item.get("instance_id", "")) != instance_id:
			continue
		state.inventory_events.append(_build_event("loss", item, reason, timestamp_utc))
		state.owned_items.remove_at(index)
		_invalidate_grants_for_instance(state, instance_id)
		state.changed.emit()
		return { "error": OK, "message": "Equipment removed from current inventory." }
	return { "error": ERR_DOES_NOT_EXIST, "message": "Owned item was not found." }


func finalize_loadout(state: CharacterState, repository: EquipmentDataRepository, expected_grants: Array) -> Dictionary:
	if state.loadout_state == CharacterState.LOADOUT_UNPREPARED or state.starting_loadout.is_empty():
		return { "error": ERR_INVALID_DATA, "message": "Prepare the starting loadout before finalizing it." }
	if not starting_loadout_matches(state, expected_grants):
		return { "error": ERR_INVALID_DATA, "message": "Creation inputs changed. Rebuild starting grants before finalizing this loadout." }
	var grant_consistency_error := state.get_starting_grant_consistency_error()
	if not grant_consistency_error.is_empty():
		return { "error": ERR_INVALID_DATA, "message": grant_consistency_error }
	for grant: Dictionary in state.starting_loadout:
		if not repository.has_item(str(grant.get("definition_id", ""))):
			return { "error": ERR_INVALID_DATA, "message": "A starting grant no longer exists in the current catalogue." }
	for item: Dictionary in state.owned_items:
		var definition := repository.get_item(str(item.get("definition_id", "")))
		if definition.is_empty():
			return { "error": ERR_INVALID_DATA, "message": "Resolve missing catalogue definitions before finalizing the loadout." }
		if str(definition.get("category", "")) in ["ranged_weapon", "melee_weapon", "armour"] and int(item.get("quantity", 0)) != 1:
			return { "error": ERR_INVALID_DATA, "message": "Weapons and armour must remain separate quantity-one instances." }
	state.loadout_state = CharacterState.LOADOUT_FINALIZED
	state.changed.emit()
	return { "error": OK, "message": "Loadout finalized." }


## Compares the materialized grant totals with the character calculator's
## current package. Owned acquisitions are intentionally outside this check.
func starting_loadout_matches(state: CharacterState, expected_grants: Array) -> bool:
	return _materialized_grant_signature(state.starting_loadout) == _expected_grant_signature(expected_grants, state.starting_loadout)


## Replaces only prior starting-issue records after creation inputs change.
## Later acquisitions survive, and removed issued records remain in history as
## explicit corrections before the newly calculated issue events are appended.
func rebuild_starting_loadout(state: CharacterState, expected_grants: Array, repository: EquipmentDataRepository, timestamp_utc: String) -> Dictionary:
	if timestamp_utc.strip_edges().is_empty() or _expected_grant_signature(expected_grants, state.starting_loadout).is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "Current calculated starting grants are not ready to rebuild." }
	for grant_value: Variant in expected_grants:
		if not grant_value is Dictionary or not repository.has_item(str((grant_value as Dictionary).get("id", ""))):
			return { "error": ERR_INVALID_DATA, "message": "Current starting grants contain an unknown definition." }
		var grant := grant_value as Dictionary
		if _starting_origin_splits(grant, int(grant.get("quantity", 0))).is_empty():
			return { "error": ERR_INVALID_DATA, "message": "Current starting grants contain inconsistent issue origins." }
	var issued_ids: Dictionary = {}
	for grant: Dictionary in state.starting_loadout:
		for issued_value: Variant in grant.get("issued_instance_ids", []):
			issued_ids[str(issued_value)] = true
	var retained_items: Array[Dictionary] = []
	var retained_events: Array[Dictionary] = state.inventory_events.duplicate(true)
	for item: Dictionary in state.owned_items:
		if issued_ids.has(str(item.get("instance_id", ""))):
			retained_events.append(_build_event("correction", item, "Starting issue replaced after creation input change", timestamp_utc))
		else:
			retained_items.append(item.duplicate(true))
	state.loadout_state = CharacterState.LOADOUT_UNPREPARED
	state.starting_loadout.clear()
	state.owned_items.clear()
	state.inventory_events.clear()
	var materialized := materialize_starting_loadout(state, expected_grants, repository, timestamp_utc)
	if int(materialized.get("error", ERR_INVALID_DATA)) != OK:
		return materialized
	var new_items: Array[Dictionary] = state.owned_items.duplicate(true)
	var new_events: Array[Dictionary] = state.inventory_events.duplicate(true)
	state.owned_items = retained_items
	state.owned_items.append_array(new_items)
	state.inventory_events = retained_events
	state.inventory_events.append_array(new_events)
	state.loadout_state = CharacterState.LOADOUT_DRAFT
	state.changed.emit()
	return { "error": OK, "message": "Starting grants rebuilt from current creation choices." }


## Records how a starting grant that is no longer present was resolved. The
## current owned inventory remains authoritative; this record only proves that
## the discrepancy was reviewed before finalization.
func reconcile_starting_grant(state: CharacterState, grant_id: String, reconciliation: String, note: String, timestamp_utc: String) -> Dictionary:
	if reconciliation not in CharacterState.STARTING_GRANT_RECONCILIATIONS or reconciliation == "unresolved" or timestamp_utc.strip_edges().is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "Choose a supported reconciliation and timestamp." }
	if reconciliation != "present" and note.strip_edges().is_empty():
		return { "error": ERR_INVALID_PARAMETER, "message": "Explain how the starting grant was accounted for." }
	for grant: Dictionary in state.starting_loadout:
		if str(grant.get("grant_id", "")) != grant_id:
			continue
		if str(grant.get("reconciliation", "")) == reconciliation and str(grant.get("note", "")) == note.strip_edges():
			return { "error": OK, "message": "Starting grant reconciliation was already current." }
		grant["reconciliation"] = reconciliation
		grant["note"] = note.strip_edges()
		var issued_ids := grant.get("issued_instance_ids", []) as Array
		var snapshot := _find_item(state.owned_items, str(issued_ids[0])) if not issued_ids.is_empty() else {}
		if snapshot.is_empty():
			snapshot = {
				"instance_id": str(issued_ids[0]) if not issued_ids.is_empty() else DocumentIdentity.generate(),
				"definition_id": str(grant.get("definition_id", "")),
				"quantity": int(grant.get("quantity", 1))
			}
		state.inventory_events.append(_build_event("correction", snapshot, "Starting grant reconciled as %s: %s" % [reconciliation, note.strip_edges()], timestamp_utc))
		state.changed.emit()
		return { "error": OK, "message": "Starting grant reconciliation updated." }
	return { "error": ERR_DOES_NOT_EXIST, "message": "Starting grant was not found." }


func _build_item(definition_id: String, quantity: int, craftsmanship: String, origin: String, location: String, custodian: Dictionary, note: String) -> Dictionary:
	return {
		"instance_id": DocumentIdentity.generate(),
		"definition_id": definition_id,
		"quantity": quantity,
		"craftsmanship": craftsmanship,
		"modification_ids": [],
		"origin": origin,
		"location": location,
		"custodian": custodian.duplicate(true),
		"note": note.strip_edges()
	}


func _build_event(event_type: String, item: Dictionary, reason: String, timestamp_utc: String) -> Dictionary:
	var snapshot := item.duplicate(true)
	if not snapshot.get("modification_ids", null) is Array:
		snapshot["modification_ids"] = []
	return {
		"event_id": DocumentIdentity.generate(),
		"timestamp_utc": timestamp_utc,
		"type": event_type,
		"instance_id": str(item.get("instance_id", "")),
		"definition_id": str(item.get("definition_id", "")),
		"quantity": int(item.get("quantity", 1)),
		"reason": reason.strip_edges(),
		"item_snapshot": snapshot
	}


func _find_item(items: Array[Dictionary], instance_id: String) -> Dictionary:
	for item: Dictionary in items:
		if str(item.get("instance_id", "")) == instance_id:
			return item
	return {}


func _find_stack(items: Array[Dictionary], definition_id: String, craftsmanship: String, origin: String, location: String, custodian: Dictionary, excluded_ids: Dictionary) -> Dictionary:
	for item: Dictionary in items:
		if excluded_ids.has(str(item.get("instance_id", ""))):
			continue
		if str(item.get("definition_id", "")) == definition_id and str(item.get("craftsmanship", "")) == craftsmanship and str(item.get("origin", "")) == origin and str(item.get("location", "")) == location and (item.get("custodian", {}) as Dictionary) == custodian:
			return item
	return {}


func _issued_instance_ids(state: CharacterState) -> Dictionary:
	var output: Dictionary = {}
	for grant: Dictionary in state.starting_loadout:
		for instance_value: Variant in grant.get("issued_instance_ids", []):
			output[str(instance_value)] = true
	return output


func _event_quantity_snapshot(item: Dictionary, event_quantity: int) -> Dictionary:
	var snapshot := item.duplicate(true)
	snapshot["quantity"] = event_quantity
	return snapshot


func _custodian_is_available(state: CharacterState, custodian_type: String, custodian_id: String) -> bool:
	if custodian_type in ["character", "squad"]:
		return custodian_id.is_empty()
	return custodian_type == "comrade" and not state.comrade.is_empty() and custodian_id == str(state.comrade.get("id", ""))


func _invalidate_grants_for_instance(state: CharacterState, instance_id: String) -> void:
	for grant: Dictionary in state.starting_loadout:
		if instance_id in (grant.get("issued_instance_ids", []) as Array):
			grant["reconciliation"] = "unresolved"
			grant["note"] = ""


func _starting_origin_splits(grant: Dictionary, total_quantity: int) -> Array[Dictionary]:
	var quantities := grant.get("origin_quantities", {}) as Dictionary
	if quantities.is_empty():
		var origins := grant.get("origins", []) as Array
		var origin := "speciality_issue" if origins.size() == 1 and str(origins[0]) == "speciality_issue" else "standard_issue"
		return [{ "origin": origin, "quantity": total_quantity }]
	var output: Array[Dictionary] = []
	var split_total := 0
	for origin in ["standard_issue", "speciality_issue"]:
		var quantity := int(quantities.get(origin, 0))
		if quantity <= 0:
			continue
		output.append({ "origin": origin, "quantity": quantity })
		split_total += quantity
	return output if split_total == total_quantity else []


func _expected_grant_signature(grants: Array, materialized_fallback: Array[Dictionary] = []) -> Dictionary:
	var signature: Dictionary = {}
	for grant_value: Variant in grants:
		if not grant_value is Dictionary:
			return {}
		var grant := grant_value as Dictionary
		var definition_id := str(grant.get("id", ""))
		var scope := str(grant.get("scope", "per_character"))
		var quantity := int(grant.get("quantity", 0))
		var craftsmanship := str(grant.get("craftsmanship", _fallback_grant_craftsmanship(materialized_fallback, definition_id, scope)))
		if craftsmanship.is_empty():
			craftsmanship = "Common"
		if definition_id.is_empty() or scope not in ["per_character", "per_squad"] or quantity <= 0 or craftsmanship not in CharacterState.CRAFTSMANSHIP_VALUES:
			return {}
		var origin_splits := _starting_origin_splits(grant, quantity)
		if origin_splits.is_empty():
			return {}
		for split: Dictionary in origin_splits:
			var key := "%s|%s|%s|%s" % [definition_id, scope, craftsmanship, split.get("origin", "")]
			signature[key] = int(signature.get(key, 0)) + int(split.get("quantity", 0))
	return signature


func _materialized_grant_signature(grants: Array[Dictionary]) -> Dictionary:
	var signature: Dictionary = {}
	for grant: Dictionary in grants:
		var key := "%s|%s|%s|%s" % [grant.get("definition_id", ""), grant.get("scope", "per_character"), grant.get("craftsmanship", "Common"), grant.get("origin", "")]
		signature[key] = int(signature.get(key, 0)) + int(grant.get("quantity", 0))
	return signature


func _fallback_grant_craftsmanship(grants: Array[Dictionary], definition_id: String, scope: String) -> String:
	for grant: Dictionary in grants:
		if str(grant.get("definition_id", "")) == definition_id and str(grant.get("scope", "per_character")) == scope:
			return str(grant.get("craftsmanship", "Common"))
	return ""
