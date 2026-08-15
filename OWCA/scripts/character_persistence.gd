class_name CharacterPersistence
extends RefCounted

## Versioned JSON persistence for individual OWCA characters.
##
## The calculated preview is convenient for humans inspecting a save, but load
## intentionally ignores it and recalculates from the authoritative state.
## `schema_version` is the public contract; numeric `version` remains the
## internal/legacy envelope version for backwards compatibility.

const FILE_FORMAT := "owca_character"
const FILE_VERSION := 4
const SUPPORTED_FILE_VERSIONS: Array[int] = [1, 2, 3, FILE_VERSION]
const SCHEMA_VERSION := InteroperabilityContract.SCHEMA_VERSION


## Writes a versioned envelope containing rules versions, authoritative state,
## and a non-authoritative calculated preview.
func save_character(path: String, state: CharacterState, calculation: Dictionary, character_repository: CharacterDataRepository) -> Dictionary:
	if not InteroperabilityContract.extensions_are_valid(state.interoperability_extensions):
		return { "error": ERR_INVALID_DATA, "message": "Character extensions must be a namespaced JSON object." }
	var inventory_validation := _validate_inventory_catalogue(state, character_repository.equipment_repository)
	if int(inventory_validation.get("error", ERR_INVALID_DATA)) != OK:
		return inventory_validation
	var envelope := {
		"format": FILE_FORMAT,
		"version": FILE_VERSION,
		"schema_version": SCHEMA_VERSION,
		"producer": InteroperabilityContract.build_producer(),
		"saved_at_utc": Time.get_datetime_string_from_system(true),
		"character_rules_content_version": str(character_repository.data.get("content_version", "unknown")),
		"advancement_rules_content_version": str(character_repository.advancement_data.get("content_version", "unknown")),
		"equipment_rules_content_version": character_repository.equipment_repository.get_content_version(),
		"inventory_rules_content_version": str(character_repository.inventory_rules_repository.call("get_content_version")),
		"character": state.to_dict(),
		"calculated_preview": _build_preview(state, calculation),
		"extensions": state.interoperability_extensions.duplicate(true)
	}
	return AtomicJsonStore.save_dictionary(path, envelope, Callable(self, "_validate_envelope"))


## Loads only supported envelope/state versions into the supplied state object.
## The caller recalculates against its currently loaded rules repositories.
func load_character(path: String, state: CharacterState) -> Dictionary:
	var validator := Callable(self, "_validate_envelope")
	var read_result := AtomicJsonStore.read_dictionary(path, validator)
	if int(read_result.get("error", ERR_INVALID_DATA)) != OK:
		read_result["recovery"] = AtomicJsonStore.inspect_recovery(path, validator)
		return read_result
	var envelope := read_result.get("data", {}) as Dictionary
	var migration_report := _build_migration_report(envelope)
	var state_error := state.from_dict(envelope["character"] as Dictionary)
	if state_error != OK:
		return { "error": state_error, "message": "Character state is invalid or from an unsupported version." }
	var equipment_repository := EquipmentDataRepository.new()
	if equipment_repository.load_data() == OK:
		var missing_definitions := _missing_inventory_definition_ids(state, equipment_repository)
		if not missing_definitions.is_empty() and state.loadout_state == CharacterState.LOADOUT_FINALIZED:
			state.loadout_state = CharacterState.LOADOUT_DRAFT
			if state.workflow_state in [CharacterState.WORKFLOW_COMPLETE, CharacterState.WORKFLOW_CAMPAIGN]:
				state.workflow_state = CharacterState.WORKFLOW_DRAFT
			migration_report.append("Returned the loadout to draft because catalogue definitions are missing: %s." % ", ".join(missing_definitions))
	state.interoperability_extensions = (envelope.get("extensions", {}) as Dictionary).duplicate(true)
	var recovery := AtomicJsonStore.inspect_recovery(path, validator)
	var message := "Loaded character from %s." % path
	if not migration_report.is_empty():
		message += " Migration report: %s" % " ".join(migration_report)
	if bool(recovery.get("temporary_valid", false)):
		message += " A validated interrupted-save candidate is also available."
	return {
		"error": OK,
		"message": message,
		"schema_version": str(envelope.get("schema_version", "legacy")),
		"migration_report": migration_report,
		"recovery": recovery
	}


func recover_temporary(path: String) -> Dictionary:
	return AtomicJsonStore.recover_temporary(path, Callable(self, "_validate_envelope"))


func restore_backup(path: String) -> Dictionary:
	return AtomicJsonStore.restore_backup(path, Callable(self, "_validate_envelope"))


func discard_temporary(path: String) -> Dictionary:
	return AtomicJsonStore.discard_temporary(path)


func _validate_envelope(envelope: Dictionary) -> Dictionary:
	if str(envelope.get("format", "")) != FILE_FORMAT or int(envelope.get("version", 0)) not in SUPPORTED_FILE_VERSIONS:
		return { "error": ERR_INVALID_DATA, "message": "Unsupported character save format or version." }
	if not InteroperabilityContract.supports_schema_version(envelope.get("schema_version", null)):
		return { "error": ERR_INVALID_DATA, "message": "Unsupported character interoperability schema version." }
	if not InteroperabilityContract.extensions_are_valid(envelope.get("extensions", {})):
		return { "error": ERR_INVALID_DATA, "message": "Character extensions must be a namespaced JSON object." }
	if not envelope.get("character", {}) is Dictionary:
		return { "error": ERR_INVALID_DATA, "message": "Character save has no state object." }
	var state := CharacterState.new()
	if state.from_dict(envelope["character"] as Dictionary) != OK:
		return { "error": ERR_INVALID_DATA, "message": "Character state is invalid or from an unsupported version." }
	var equipment_repository := EquipmentDataRepository.new()
	if equipment_repository.load_data() != OK:
		return { "error": ERR_CANT_ACQUIRE_RESOURCE, "message": "Could not validate inventory against the equipment catalogue." }
	var inventory_validation := _validate_inventory_catalogue(state, equipment_repository)
	if int(inventory_validation.get("error", ERR_INVALID_DATA)) != OK:
		return inventory_validation
	return { "error": OK }


func _build_migration_report(envelope: Dictionary) -> Array[String]:
	var report: Array[String] = []
	if not envelope.has("schema_version"):
		report.append("Added public schema metadata for the next save.")
	elif str(envelope.get("schema_version", "")) != SCHEMA_VERSION:
		report.append("Interoperability schema %s will become %s." % [envelope.get("schema_version", "legacy"), SCHEMA_VERSION])
	if not envelope.has("equipment_rules_content_version"):
		report.append("Added the shared equipment catalogue version for the next save.")
	if not envelope.has("inventory_rules_content_version"):
		report.append("Added the inventory and encumbrance rules version for the next save.")
	var envelope_version := int(envelope.get("version", 0))
	if envelope_version < FILE_VERSION:
		report.append("Character envelope v%d will become v%d." % [envelope_version, FILE_VERSION])
	var state_data := envelope.get("character", {}) as Dictionary
	var state_version := int(state_data.get("version", 0))
	if state_version < CharacterState.SAVE_VERSION:
		report.append("Character state v%d will become v%d." % [state_version, CharacterState.SAVE_VERSION])
	if state_version < 2:
		report.append("Initialized an empty ordered advancement ledger.")
	if state_version < CharacterState.SAVE_VERSION:
		report.append("Initialized an unprepared loadout; prepare and finalize starting equipment before completing creation.")
		if str(state_data.get("workflow_state", CharacterState.WORKFLOW_DRAFT)) != CharacterState.WORKFLOW_DRAFT:
			report.append("Returned the legacy character to draft because its starting loadout was not yet finalized.")
	if not state_data.has("document_id"):
		report.append("Generated a durable document ID.")
	if not state_data.has("workflow_state"):
		report.append("Defaulted lifecycle to draft; complete it again after validation.")
	var regiment_snapshot := state_data.get("regiment", {}) as Dictionary
	if not regiment_snapshot.is_empty() and int(regiment_snapshot.get("version", 0)) < RegimentState.SAVE_VERSION:
		report.append("Migrated the embedded regiment snapshot to v%d with a durable ID and draft lifecycle." % RegimentState.SAVE_VERSION)
	return report


func _build_preview(state: CharacterState, calculation: Dictionary) -> Dictionary:
	if calculation.is_empty():
		return {}
	return {
		"valid": bool(calculation.get("valid", false)),
		"regiment_name": str(calculation.get("regiment_name", state.get_regiment_name())),
		"speciality_id": state.speciality_id,
		"speciality": str(calculation.get("speciality_name", "")),
		"characteristics": InteroperabilityContract.copy_dictionary(calculation, "characteristics"),
		"characteristic_bonuses": InteroperabilityContract.copy_dictionary(calculation, "characteristic_bonuses"),
		"skills": InteroperabilityContract.copy_array(calculation, "skills"),
		"talents": InteroperabilityContract.copy_array(calculation, "talents"),
		"aptitudes": InteroperabilityContract.copy_array(calculation, "aptitudes"),
		"special_rules": InteroperabilityContract.copy_array(calculation, "special_rules"),
		"equipment": InteroperabilityContract.copy_array(calculation, "equipment"),
		"starting_equipment": InteroperabilityContract.copy_array(calculation, "starting_equipment"),
		"inventory": InteroperabilityContract.copy_dictionary(calculation, "inventory"),
		"wounds_modifier": int(calculation.get("wounds_modifier", 0)),
		"wounds": int(calculation.get("wounds", 0)),
		"fate_points": int(calculation.get("fate_points", 0)),
		"movement": InteroperabilityContract.copy_dictionary(calculation, "movement"),
		"xp_budget": int(calculation.get("xp_budget", 0)),
		"bonus_xp": int(calculation.get("bonus_xp", 0)),
		"xp_spent": int(calculation.get("xp_spent", 0)),
		"xp_remaining": int(calculation.get("xp_remaining", 0)),
		"resolved_choices": InteroperabilityContract.copy_array(calculation, "resolved_choices"),
		"unresolved_choices": InteroperabilityContract.summarize_unresolved(calculation.get("unresolved_choices", []) as Array, ""),
		"sources": InteroperabilityContract.copy_array(calculation, "sources"),
		"errors": InteroperabilityContract.copy_array(calculation, "errors"),
		"warnings": InteroperabilityContract.copy_array(calculation, "warnings")
	}


func _validate_inventory_catalogue(state: CharacterState, repository: EquipmentDataRepository) -> Dictionary:
	for item: Dictionary in state.owned_items:
		var definition := repository.get_item(str(item.get("definition_id", "")))
		# Removed catalogue definitions remain visible and recoverable. They are
		# deliberately blocked only when the player attempts finalization.
		if definition.is_empty():
			continue
		if str(definition.get("category", "")) in ["ranged_weapon", "melee_weapon", "armour"] and int(item.get("quantity", 0)) != 1:
			return { "error": ERR_INVALID_DATA, "message": "Weapons and armour must be stored as quantity-one owned instances." }
	return { "error": OK }


func _missing_inventory_definition_ids(state: CharacterState, repository: EquipmentDataRepository) -> Array[String]:
	var output: Array[String] = []
	for grant: Dictionary in state.starting_loadout:
		var grant_definition_id := str(grant.get("definition_id", ""))
		if not repository.has_item(grant_definition_id) and grant_definition_id not in output:
			output.append(grant_definition_id)
	for item: Dictionary in state.owned_items:
		var definition_id := str(item.get("definition_id", ""))
		if not repository.has_item(definition_id) and definition_id not in output:
			output.append(definition_id)
	output.sort()
	return output
