class_name RegimentPersistence
extends RefCounted

## Versioned JSON persistence kept separate from the UI and rules engine.
##
## `version` remains the legacy OWCA envelope version. `schema_version` is the
## public interoperability contract shared with third-party tools. Missing
## `schema_version` means a legacy pre-v0.5.1 file and remains supported.

const FILE_FORMAT := "owca_regiment"
const FILE_VERSION := 2
const SUPPORTED_FILE_VERSIONS: Array[int] = [1, FILE_VERSION]
const SCHEMA_VERSION := InteroperabilityContract.SCHEMA_VERSION


func save_regiment(path: String, state: RegimentState, repository: RegimentDataRepository) -> Dictionary:
	if not InteroperabilityContract.extensions_are_valid(state.interoperability_extensions):
		return { "error": ERR_INVALID_DATA, "message": "Regiment extensions must be a namespaced JSON object." }
	var regiment_data := state.to_dict()
	_filter_character_resolutions(regiment_data, repository)
	var calculation := RegimentCalculator.new().calculate(state, repository)
	var envelope := {
		"format": FILE_FORMAT,
		"version": FILE_VERSION,
		"schema_version": SCHEMA_VERSION,
		"producer": InteroperabilityContract.build_producer(),
		"saved_at_utc": Time.get_datetime_string_from_system(true),
		"rules_content_version": str(repository.data.get("content_version", "unknown")),
		"equipment_rules_content_version": repository.equipment_repository.get_content_version(),
		"character_creation_choices": _collect_character_choices(state, repository),
		"regiment": regiment_data,
		"calculated_preview": _build_preview(calculation),
		"extensions": state.interoperability_extensions.duplicate(true)
	}
	return AtomicJsonStore.save_dictionary(path, envelope, Callable(self, "_validate_envelope").bind(repository))


func load_regiment(path: String, state: RegimentState, repository: RegimentDataRepository) -> Dictionary:
	var validator := Callable(self, "_validate_envelope").bind(repository)
	var read_result := AtomicJsonStore.read_dictionary(path, validator)
	if int(read_result.get("error", ERR_INVALID_DATA)) != OK:
		read_result["recovery"] = AtomicJsonStore.inspect_recovery(path, validator)
		return read_result
	var envelope := read_result.get("data", {}) as Dictionary
	var migration_report := _build_migration_report(envelope)
	var regiment_data := (envelope["regiment"] as Dictionary).duplicate(true)
	_filter_character_resolutions(regiment_data, repository)
	var state_error := state.from_dict(regiment_data)
	if state_error != OK:
		return { "error": state_error, "message": "Regiment state is invalid or from an unsupported version." }
	state.interoperability_extensions = (envelope.get("extensions", {}) as Dictionary).duplicate(true)
	var recovery := AtomicJsonStore.inspect_recovery(path, validator)
	var message := "Loaded regiment from %s." % path
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


func recover_temporary(path: String, repository: RegimentDataRepository) -> Dictionary:
	return AtomicJsonStore.recover_temporary(path, Callable(self, "_validate_envelope").bind(repository))


func restore_backup(path: String, repository: RegimentDataRepository) -> Dictionary:
	return AtomicJsonStore.restore_backup(path, Callable(self, "_validate_envelope").bind(repository))


func discard_temporary(path: String) -> Dictionary:
	return AtomicJsonStore.discard_temporary(path)


func _validate_envelope(envelope: Dictionary, repository: RegimentDataRepository) -> Dictionary:
	if str(envelope.get("format", "")) != FILE_FORMAT or int(envelope.get("version", 0)) not in SUPPORTED_FILE_VERSIONS:
		return { "error": ERR_INVALID_DATA, "message": "Unsupported regiment save format or version." }
	if not InteroperabilityContract.supports_schema_version(envelope.get("schema_version", null)):
		return { "error": ERR_INVALID_DATA, "message": "Unsupported regiment interoperability schema version." }
	if not InteroperabilityContract.extensions_are_valid(envelope.get("extensions", {})):
		return { "error": ERR_INVALID_DATA, "message": "Regiment extensions must be a namespaced JSON object." }
	if not envelope.get("regiment", {}) is Dictionary:
		return { "error": ERR_INVALID_DATA, "message": "Regiment save has no state object." }
	var candidate_data := (envelope["regiment"] as Dictionary).duplicate(true)
	_filter_character_resolutions(candidate_data, repository)
	if RegimentState.new().from_dict(candidate_data) != OK:
		return { "error": ERR_INVALID_DATA, "message": "Regiment state is invalid or from an unsupported version." }
	return { "error": OK }


func _build_migration_report(envelope: Dictionary) -> Array[String]:
	var report: Array[String] = []
	if not envelope.has("schema_version"):
		report.append("Added public schema metadata for the next save.")
	elif str(envelope.get("schema_version", "")) != SCHEMA_VERSION:
		report.append("Interoperability schema %s will become %s." % [envelope.get("schema_version", "legacy"), SCHEMA_VERSION])
	if not envelope.has("equipment_rules_content_version"):
		report.append("Added the shared equipment catalogue version for the next save.")
	var envelope_version := int(envelope.get("version", 0))
	if envelope_version < FILE_VERSION:
		report.append("Regiment envelope v%d will become v%d." % [envelope_version, FILE_VERSION])
	var state_data := envelope.get("regiment", {}) as Dictionary
	var state_version := int(state_data.get("version", 0))
	if state_version < RegimentState.SAVE_VERSION:
		report.append("Regiment state v%d will become v%d." % [state_version, RegimentState.SAVE_VERSION])
	if not state_data.has("document_id"):
		report.append("Generated a durable document ID.")
	if not state_data.has("workflow_state"):
		report.append("Defaulted lifecycle to draft; complete it again after validation.")
	return report


## A human- and machine-readable cache of calculated results. It may be stale
## under different rules data and is never used to reconstruct RegimentState.
func _build_preview(calculation: Dictionary) -> Dictionary:
	if calculation.is_empty():
		return {}
	return {
		"valid": bool(calculation.get("valid", false)),
		"points_budget": int(calculation.get("points_budget", 0)),
		"points_spent": int(calculation.get("points_spent", 0)),
		"points_remaining": int(calculation.get("points_remaining", 0)),
		"doctrine_slots_used": int(calculation.get("doctrine_slots_used", 0)),
		"doctrine_slots_maximum": int(calculation.get("doctrine_slots_maximum", 0)),
		"optional_doctrines_used": int(calculation.get("optional_doctrines_used", 0)),
		"optional_doctrines_maximum": int(calculation.get("optional_doctrines_maximum", 0)),
		"characteristics": InteroperabilityContract.copy_dictionary(calculation, "characteristics"),
		"skills": InteroperabilityContract.copy_array(calculation, "skills"),
		"talents": InteroperabilityContract.copy_array(calculation, "talents"),
		"aptitudes": InteroperabilityContract.copy_array(calculation, "aptitudes"),
		"special_rules": InteroperabilityContract.copy_array(calculation, "special_rules"),
		"wounds_modifier": int(calculation.get("wounds", 0)),
		"equipment": InteroperabilityContract.copy_array(calculation, "equipment"),
		"standard_kit_points": int(calculation.get("standard_kit_points", 0)),
		"bonus_xp": int(calculation.get("bonus_xp", 0)),
		"resolved_choices": InteroperabilityContract.copy_array(calculation, "resolved_choices"),
		"unresolved_choices": InteroperabilityContract.summarize_unresolved(calculation.get("unresolved_choices", []) as Array, "regiment"),
		"sources": InteroperabilityContract.copy_array(calculation, "sources"),
		"errors": InteroperabilityContract.copy_array(calculation, "errors"),
		"warnings": InteroperabilityContract.copy_array(calculation, "warnings")
	}


func _filter_character_resolutions(regiment_data: Dictionary, repository: RegimentDataRepository) -> void:
	var raw_resolutions: Variant = regiment_data.get("resolutions", {})
	if not raw_resolutions is Dictionary:
		return
	var resolutions := raw_resolutions as Dictionary
	for choice_id: Variant in resolutions.keys():
		var choice := repository.get_choice(str(choice_id))
		if str(choice.get("scope", "regiment")) == "per_character":
			resolutions.erase(choice_id)
	regiment_data["resolutions"] = resolutions


func _collect_character_choices(state: RegimentState, repository: RegimentDataRepository) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for option_id in state.get_all_selected_ids():
		var option := repository.get_option(option_id)
		for choice_value: Variant in option.get("choices", []):
			if choice_value is Dictionary:
				var choice := choice_value as Dictionary
				if str(choice.get("scope", "regiment")) == "per_character":
					choices.append(choice.duplicate(true))
	return choices
