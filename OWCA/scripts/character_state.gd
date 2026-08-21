class_name CharacterState
extends RefCounted

## Serializable inputs for one character.
##
## This object is deliberately limited to facts the player selected, entered,
## or purchased. Final Characteristics, Skills, Talents, equipment, Wounds,
## Fate, and XP totals are reproducible calculator output and must not become
## authoritative saved state.

## Emitted after a public mutator changes state. Current UI controllers often
## refresh explicitly, but the signal keeps the state reusable by future UIs.
signal changed

## State schema version nested inside the versioned character-file envelope.
const SAVE_VERSION := 5
const SUPPORTED_SAVE_VERSIONS: Array[int] = [1, 2, 3, 4, SAVE_VERSION]
const WORKFLOW_DRAFT := "draft"
const WORKFLOW_COMPLETE := "creation_complete"
const WORKFLOW_CAMPAIGN := "campaign_active"
const WORKFLOW_STATES: Array[String] = [WORKFLOW_DRAFT, WORKFLOW_COMPLETE, WORKFLOW_CAMPAIGN]
const LOADOUT_UNPREPARED := "unprepared"
const LOADOUT_DRAFT := "draft"
const LOADOUT_FINALIZED := "finalized"
const LOADOUT_STATES: Array[String] = [LOADOUT_UNPREPARED, LOADOUT_DRAFT, LOADOUT_FINALIZED]
const ITEM_LOCATIONS: Array[String] = ["equipped", "carried", "stored"]
const ITEM_ORIGINS: Array[String] = ["standard_issue", "speciality_issue", "later_issue", "exchange", "acquisition", "transfer", "correction"]
const CRAFTSMANSHIP_VALUES: Array[String] = ["Poor", "Common", "Good", "Best"]
const CUSTODIAN_TYPES: Array[String] = ["character", "comrade", "squad"]
const INVENTORY_EVENT_TYPES: Array[String] = ["issue", "acquisition", "exchange", "transfer", "loss", "quantity", "correction", "modification"]
const STARTING_GRANT_RECONCILIATIONS: Array[String] = ["unresolved", "present", "exchange", "loss", "transfer", "correction"]
## Canonical order shared by entry forms, calculations, exports, and tests.
const CHARACTERISTIC_ORDER: Array[String] = [
	"Weapon Skill",
	"Ballistic Skill",
	"Strength",
	"Toughness",
	"Agility",
	"Intelligence",
	"Perception",
	"Willpower",
	"Fellowship"
]

var document_id: String = ""
var workflow_state: String = WORKFLOW_DRAFT
var character_name: String = "New Character"
var player_name: String = ""
var regiment: Dictionary = {}
var regiment_rules_content_version: String = ""
var speciality_id: String = ""
## Raw 2d10 + 20 inputs, whether rolled by OWCA, physical dice, or Discord.
var base_characteristics: Dictionary = {}
## Explicit GM/player adjustments applied after regiment and Speciality effects.
var manual_adjustments: Dictionary = {}
var regiment_resolutions: Dictionary = {}
var speciality_resolutions: Dictionary = {}
## Raw creation dice. Zero means not entered; valid values are 1-5 and 1-10.
var wounds_roll: int = 0
var fate_roll: int = 0
## Ordered stable advancement IDs. Order affects ranks, costs, and prerequisites.
var purchased_advances: Array[String] = []
## Minimal identity needed to assign equipment without inventing future
## Comrade Characteristics, status, or advancement rules.
var comrade: Dictionary = {}
var loadout_state: String = LOADOUT_UNPREPARED
## Materialized grant records prove that calculated starting equipment was
## acknowledged exactly once. Current ownership lives in `owned_items`.
var starting_loadout: Array[Dictionary] = []
var owned_items: Array[Dictionary] = []
var inventory_events: Array[Dictionary] = []
## Opaque, namespaced data owned by external tools. It is envelope metadata,
## not a character-building input, so calculators intentionally ignore it.
var interoperability_extensions: Dictionary = {}


func _init() -> void:
	document_id = DocumentIdentity.generate()


func set_character_name(value: String) -> void:
	character_name = value.strip_edges()
	if character_name.is_empty():
		character_name = "Unnamed Character"
	changed.emit()


func set_player_name(value: String) -> void:
	player_name = value.strip_edges()
	changed.emit()


func set_regiment(regiment_data: Dictionary, content_version: String) -> void:
	regiment = regiment_data.duplicate(true)
	regiment_rules_content_version = content_version
	regiment_resolutions.clear()
	_mark_creation_draft()
	changed.emit()


func has_regiment() -> bool:
	return not regiment.is_empty()


func get_regiment_name() -> String:
	return str(regiment.get("name", "No regiment loaded"))


func set_speciality(value: String) -> void:
	if speciality_id == value:
		return
	speciality_id = value
	speciality_resolutions.clear()
	_mark_creation_draft()
	changed.emit()


func set_base_characteristic(characteristic: String, value: int) -> void:
	if value <= 0:
		base_characteristics.erase(characteristic)
	else:
		base_characteristics[characteristic] = value
	_mark_creation_draft()
	changed.emit()


func set_manual_adjustment(characteristic: String, value: int) -> void:
	if value == 0:
		manual_adjustments.erase(characteristic)
	else:
		manual_adjustments[characteristic] = value
	_mark_creation_draft()
	changed.emit()


func set_wounds_roll(value: int) -> void:
	wounds_roll = value
	_mark_creation_draft()
	changed.emit()


func set_fate_roll(value: int) -> void:
	fate_roll = value
	_mark_creation_draft()
	changed.emit()


func purchase_advance(advance_id: String) -> void:
	var clean_id := advance_id.strip_edges()
	if clean_id.is_empty():
		return
	purchased_advances.append(clean_id)
	_mark_creation_draft()
	changed.emit()


func remove_advance_at(index: int) -> void:
	if index < 0 or index >= purchased_advances.size():
		return
	purchased_advances.remove_at(index)
	_mark_creation_draft()
	changed.emit()


func clear_advances() -> void:
	if purchased_advances.is_empty():
		return
	purchased_advances.clear()
	_mark_creation_draft()
	changed.emit()


func set_choice(scope: String, choice_id: String, option_id: String, enabled: bool = true, maximum: int = 1) -> void:
	var collection := regiment_resolutions if scope == "regiment" else speciality_resolutions
	var current := get_choice(scope, choice_id)
	if enabled:
		if maximum == 1:
			current.assign([option_id])
		elif option_id not in current and (maximum <= 0 or current.size() < maximum):
			current.append(option_id)
	else:
		current.erase(option_id)
	if current.is_empty():
		collection.erase(choice_id)
	else:
		collection[choice_id] = current
	_mark_creation_draft()
	changed.emit()


func clear_choice(scope: String, choice_id: String) -> void:
	var collection := regiment_resolutions if scope == "regiment" else speciality_resolutions
	collection.erase(choice_id)
	_mark_creation_draft()
	changed.emit()


func get_choice(scope: String, choice_id: String) -> Array[String]:
	var collection := regiment_resolutions if scope == "regiment" else speciality_resolutions
	var output: Array[String] = []
	for value: Variant in collection.get(choice_id, []):
		output.append(str(value))
	return output


## Returns a deep-enough JSON-safe snapshot of user-authored inputs only.
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"document_id": document_id,
		"workflow_state": workflow_state,
		"name": character_name,
		"player_name": player_name,
		"regiment": regiment.duplicate(true),
		"regiment_rules_content_version": regiment_rules_content_version,
		"speciality_id": speciality_id,
		"base_characteristics": base_characteristics.duplicate(true),
		"manual_adjustments": manual_adjustments.duplicate(true),
		"regiment_resolutions": regiment_resolutions.duplicate(true),
		"speciality_resolutions": speciality_resolutions.duplicate(true),
		"wounds_roll": wounds_roll,
		"fate_roll": fate_roll,
		"purchased_advances": purchased_advances.duplicate(),
		"comrade": comrade.duplicate(true),
		"loadout_state": loadout_state,
		"starting_loadout": starting_loadout.duplicate(true),
		"owned_items": _serialized_owned_items(),
		"inventory_events": _serialized_inventory_events()
	}


## Loads supported state versions defensively. Unknown keys are ignored, while
## invalid container types or unsupported versions reject the entire state.
func from_dict(value: Dictionary) -> Error:
	var version := int(value.get("version", 0))
	if version not in SUPPORTED_SAVE_VERSIONS:
		return ERR_INVALID_DATA
	for field_name in ["regiment", "base_characteristics", "manual_adjustments", "regiment_resolutions", "speciality_resolutions"]:
		if not value.get(field_name, {}) is Dictionary:
			return ERR_INVALID_DATA

	if version >= 3:
		var loaded_document_id := str(value.get("document_id", ""))
		var loaded_workflow_state := str(value.get("workflow_state", ""))
		if not DocumentIdentity.is_valid(loaded_document_id) or loaded_workflow_state not in WORKFLOW_STATES:
			return ERR_INVALID_DATA
		document_id = loaded_document_id
		workflow_state = loaded_workflow_state
	else:
		document_id = DocumentIdentity.generate()
		workflow_state = WORKFLOW_DRAFT

	character_name = str(value.get("name", "Unnamed Character")).strip_edges()
	if character_name.is_empty():
		character_name = "Unnamed Character"
	player_name = str(value.get("player_name", "")).strip_edges()
	var loaded_regiment := (value.get("regiment", {}) as Dictionary).duplicate(true)
	if loaded_regiment.is_empty():
		regiment = {}
	else:
		# Character versions 1 and 2 embedded a version-1 regiment snapshot.
		# Normalize it through RegimentState so every newly written version-3
		# character satisfies the current public schema. A version-3 character
		# that claims to be current but embeds an old snapshot is malformed.
		if version >= 4 and int(loaded_regiment.get("version", 0)) != RegimentState.SAVE_VERSION:
			return ERR_INVALID_DATA
		var migrated_regiment := RegimentState.new()
		if migrated_regiment.from_dict(loaded_regiment) != OK:
			return ERR_INVALID_DATA
		regiment = migrated_regiment.to_dict()
	regiment_rules_content_version = str(value.get("regiment_rules_content_version", ""))
	speciality_id = str(value.get("speciality_id", ""))
	base_characteristics = _clean_numeric_dictionary(value.get("base_characteristics", {}) as Dictionary, false)
	manual_adjustments = _clean_numeric_dictionary(value.get("manual_adjustments", {}) as Dictionary, true)
	regiment_resolutions = _clean_resolution_dictionary(value.get("regiment_resolutions", {}) as Dictionary)
	speciality_resolutions = _clean_resolution_dictionary(value.get("speciality_resolutions", {}) as Dictionary)
	wounds_roll = int(value.get("wounds_roll", 0))
	fate_roll = int(value.get("fate_roll", 0))
	purchased_advances.clear()
	comrade.clear()
	loadout_state = LOADOUT_UNPREPARED
	starting_loadout.clear()
	owned_items.clear()
	inventory_events.clear()
	interoperability_extensions.clear()
	if version >= 2:
		if not value.get("purchased_advances", []) is Array:
			return ERR_INVALID_DATA
		for advance_id: Variant in value.get("purchased_advances", []):
			var clean_id := str(advance_id).strip_edges()
			if not clean_id.is_empty():
				purchased_advances.append(clean_id)
	if version >= 4:
		if not _load_inventory_data(value, version):
			return ERR_INVALID_DATA
	else:
		# A pre-inventory completion cannot satisfy v0.7's stronger lifecycle
		# guarantee. Every legacy lifecycle remains readable and explicitly
		# returns to draft until its starting gear is prepared again.
		workflow_state = WORKFLOW_DRAFT
	changed.emit()
	return OK


## The caller must verify the current calculator result before completion.
func mark_creation_complete() -> void:
	if loadout_state != LOADOUT_FINALIZED:
		return
	workflow_state = WORKFLOW_COMPLETE
	changed.emit()


func mark_draft() -> void:
	workflow_state = WORKFLOW_DRAFT
	changed.emit()


func duplicate_identity() -> void:
	document_id = DocumentIdentity.generate()
	workflow_state = WORKFLOW_DRAFT
	loadout_state = LOADOUT_DRAFT if loadout_state != LOADOUT_UNPREPARED else LOADOUT_UNPREPARED
	var previous_comrade_id := str(comrade.get("id", ""))
	if not comrade.is_empty():
		comrade["id"] = DocumentIdentity.generate()
	var item_id_map: Dictionary = {}
	for item: Dictionary in owned_items:
		var previous_id := str(item.get("instance_id", ""))
		var replacement_id := DocumentIdentity.generate()
		item["instance_id"] = replacement_id
		var custodian := item.get("custodian", {}) as Dictionary
		if str(custodian.get("type", "")) == "comrade" and str(custodian.get("id", "")) == previous_comrade_id:
			custodian["id"] = str(comrade.get("id", ""))
		item_id_map[previous_id] = replacement_id
	# Starting grants may also refer to issued items that have since been lost.
	# Give every historical issued ID a new identity before remapping events.
	for grant: Dictionary in starting_loadout:
		for issued_value: Variant in grant.get("issued_instance_ids", []):
			var issued_id := str(issued_value)
			if not item_id_map.has(issued_id):
				item_id_map[issued_id] = DocumentIdentity.generate()
	for event: Dictionary in inventory_events:
		event["event_id"] = DocumentIdentity.generate()
		var previous_instance := str(event.get("instance_id", ""))
		if not item_id_map.has(previous_instance):
			item_id_map[previous_instance] = DocumentIdentity.generate()
		event["instance_id"] = str(item_id_map[previous_instance])
		var snapshot := event.get("item_snapshot", {}) as Dictionary
		if not snapshot.is_empty():
			snapshot["instance_id"] = str(item_id_map[previous_instance])
			var snapshot_custodian := snapshot.get("custodian", {}) as Dictionary
			if str(snapshot_custodian.get("type", "")) == "comrade" and str(snapshot_custodian.get("id", "")) == previous_comrade_id:
				snapshot_custodian["id"] = str(comrade.get("id", ""))
	for grant: Dictionary in starting_loadout:
		var remapped_issued_ids: Array[String] = []
		for issued_value: Variant in grant.get("issued_instance_ids", []):
			remapped_issued_ids.append(str(item_id_map[str(issued_value)]))
		grant["issued_instance_ids"] = remapped_issued_ids
	changed.emit()


func _mark_creation_draft() -> void:
	if workflow_state == WORKFLOW_COMPLETE:
		workflow_state = WORKFLOW_DRAFT
	if loadout_state == LOADOUT_FINALIZED:
		loadout_state = LOADOUT_DRAFT


func _load_inventory_data(value: Dictionary, version: int) -> bool:
	for field_name in ["comrade", "starting_loadout", "owned_items", "inventory_events"]:
		var expected: Variant = {} if field_name == "comrade" else []
		if not value.has(field_name) or typeof(value[field_name]) != typeof(expected):
			return false
	var loaded_loadout_state := str(value.get("loadout_state", ""))
	if loaded_loadout_state not in LOADOUT_STATES:
		return false
	var loaded_comrade := (value.get("comrade", {}) as Dictionary).duplicate(true)
	if not loaded_comrade.is_empty():
		if not loaded_comrade.get("name", "") is String or not DocumentIdentity.is_valid(str(loaded_comrade.get("id", ""))) or str(loaded_comrade.get("name", "")).strip_edges().is_empty():
			return false
	var loaded_starting: Array[Dictionary] = []
	var grant_ids: Dictionary = {}
	var all_issued_ids: Dictionary = {}
	for entry_value: Variant in value.get("starting_loadout", []):
		if not entry_value is Dictionary:
			return false
		var entry := (entry_value as Dictionary).duplicate(true)
		var grant_id := str(entry.get("grant_id", ""))
		if grant_id.is_empty() or grant_ids.has(grant_id) or not _valid_stable_id(str(entry.get("definition_id", ""))) or not _is_positive_integer(entry.get("quantity", null)):
			return false
		if str(entry.get("scope", "")) not in ["per_character", "per_squad"] or str(entry.get("origin", "")) not in ["standard_issue", "speciality_issue"] or str(entry.get("reconciliation", "")) not in STARTING_GRANT_RECONCILIATIONS:
			return false
		if not entry.get("issued_instance_ids", []) is Array or not entry.get("note", "") is String:
			return false
		var issued_ids: Dictionary = {}
		for issued_value: Variant in entry.get("issued_instance_ids", []):
			var issued_id := str(issued_value)
			if not DocumentIdentity.is_valid(issued_id) or issued_ids.has(issued_id) or all_issued_ids.has(issued_id):
				return false
			issued_ids[issued_id] = true
			all_issued_ids[issued_id] = true
		if issued_ids.is_empty():
			return false
		grant_ids[grant_id] = true
		loaded_starting.append(entry)
	var instance_ids: Dictionary = {}
	var loaded_items: Array[Dictionary] = []
	for item_value: Variant in value.get("owned_items", []):
		if not item_value is Dictionary:
			return false
		var item := (item_value as Dictionary).duplicate(true)
		var instance_id := str(item.get("instance_id", ""))
		if not item.get("custodian", {}) is Dictionary:
			return false
		var custodian := item.get("custodian", {}) as Dictionary
		if not DocumentIdentity.is_valid(instance_id) or instance_ids.has(instance_id):
			return false
		if not _valid_stable_id(str(item.get("definition_id", ""))) or not _is_positive_integer(item.get("quantity", null)):
			return false
		if not item.get("craftsmanship", "") is String or str(item.get("craftsmanship", "")) not in CRAFTSMANSHIP_VALUES or not item.get("note", "") is String:
			return false
		if version >= SAVE_VERSION:
			if not _valid_modification_ids(item.get("modification_ids", null)):
				return false
		else:
			item["modification_ids"] = []
		if str(item.get("location", "")) not in ITEM_LOCATIONS or str(item.get("origin", "")) not in ITEM_ORIGINS:
			return false
		if not _custodian_is_valid(custodian, loaded_comrade):
			return false
		instance_ids[instance_id] = true
		loaded_items.append(item)
	var event_ids: Dictionary = {}
	var loaded_events: Array[Dictionary] = []
	for event_value: Variant in value.get("inventory_events", []):
		if not event_value is Dictionary:
			return false
		var event := (event_value as Dictionary).duplicate(true)
		var event_id := str(event.get("event_id", ""))
		if not DocumentIdentity.is_valid(event_id) or event_ids.has(event_id):
			return false
		if str(event.get("type", "")) not in INVENTORY_EVENT_TYPES or not _valid_timestamp_utc(event.get("timestamp_utc", null)):
			return false
		if not _valid_stable_id(str(event.get("definition_id", ""))) or not _is_positive_integer(event.get("quantity", null)):
			return false
		if not DocumentIdentity.is_valid(str(event.get("instance_id", ""))) or not event.get("reason", "") is String or not event.get("item_snapshot", {}) is Dictionary:
			return false
		var snapshot := event.get("item_snapshot", {}) as Dictionary
		if str(snapshot.get("instance_id", "")) != str(event.get("instance_id", "")) or str(snapshot.get("definition_id", "")) != str(event.get("definition_id", "")) or not _is_positive_integer(snapshot.get("quantity", null)) or int(snapshot.get("quantity", 0)) != int(event.get("quantity", 0)):
			return false
		if version >= SAVE_VERSION:
			if not _valid_modification_ids(snapshot.get("modification_ids", null)):
				return false
		else:
			snapshot["modification_ids"] = []
		event_ids[event_id] = true
		loaded_events.append(event)
	comrade = loaded_comrade
	loadout_state = loaded_loadout_state
	starting_loadout = loaded_starting
	owned_items = loaded_items
	inventory_events = loaded_events
	if loadout_state == LOADOUT_UNPREPARED and (not starting_loadout.is_empty() or not owned_items.is_empty() or not inventory_events.is_empty()):
		return false
	if loadout_state == LOADOUT_FINALIZED:
		if starting_loadout.is_empty():
			return false
		if not get_starting_grant_consistency_error().is_empty():
			return false
	if workflow_state in [WORKFLOW_COMPLETE, WORKFLOW_CAMPAIGN] and loadout_state != LOADOUT_FINALIZED:
		return false
	return true


## Pure starting-grant consistency check shared by import validation and the
## inventory service's finalization command. It uses current ownership as the
## authority and does not require catalogue access.
func get_starting_grant_consistency_error() -> String:
	for grant: Dictionary in starting_loadout:
		var reconciliation := str(grant.get("reconciliation", "unresolved"))
		if reconciliation == "unresolved" or reconciliation not in STARTING_GRANT_RECONCILIATIONS:
			return "Every starting grant must be present or explicitly accounted for."
		if reconciliation != "present":
			if str(grant.get("note", "")).strip_edges().is_empty():
				return "Explicit grant reconciliation requires a short explanation."
			continue
		var issued_ids := grant.get("issued_instance_ids", []) as Array
		var present_quantity := 0
		for item: Dictionary in owned_items:
			if str(item.get("instance_id", "")) not in issued_ids:
				continue
			if str(item.get("definition_id", "")) != str(grant.get("definition_id", "")) or str(item.get("origin", "")) != str(grant.get("origin", "")):
				return "A present starting grant has inconsistent item identity or provenance."
			present_quantity += int(item.get("quantity", 0))
		if present_quantity != int(grant.get("quantity", 0)):
			return "A starting grant marked present no longer has its exact issued quantity."
	return ""


func _custodian_is_valid(value: Dictionary, loaded_comrade: Dictionary) -> bool:
	var custodian_type := str(value.get("type", ""))
	if custodian_type not in CUSTODIAN_TYPES:
		return false
	var custodian_id := str(value.get("id", ""))
	if custodian_type == "comrade":
		return not loaded_comrade.is_empty() and custodian_id == str(loaded_comrade.get("id", ""))
	return custodian_id.is_empty()


func _valid_stable_id(value: String) -> bool:
	var pattern := RegEx.new()
	return pattern.compile("^[a-z][a-z0-9_]*$") == OK and pattern.search(value) != null


func _valid_modification_ids(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for id_value: Variant in value:
		if not id_value is String:
			return false
		var modification_id := str(id_value)
		if not _valid_stable_id(modification_id) or seen.has(modification_id):
			return false
		seen[modification_id] = true
	return true


func _serialized_owned_items() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for item: Dictionary in owned_items:
		var serialized := item.duplicate(true)
		if not serialized.get("modification_ids", null) is Array:
			serialized["modification_ids"] = []
		output.append(serialized)
	return output


func _serialized_inventory_events() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for event: Dictionary in inventory_events:
		var serialized := event.duplicate(true)
		var snapshot := serialized.get("item_snapshot", {}) as Dictionary
		if not snapshot.get("modification_ids", null) is Array:
			snapshot["modification_ids"] = []
		output.append(serialized)
	return output


func _is_positive_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) > 0
	if typeof(value) == TYPE_FLOAT:
		var numeric := float(value)
		return numeric > 0.0 and numeric == floorf(numeric)
	return false


func _valid_timestamp_utc(value: Variant) -> bool:
	if not value is String:
		return false
	var pattern := RegEx.new()
	if pattern.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?Z$") != OK:
		return false
	return pattern.search(str(value)) != null


func _clean_numeric_dictionary(value: Dictionary, allow_zero: bool) -> Dictionary:
	var output: Dictionary = {}
	for key: Variant in value:
		var name := str(key)
		if name not in CHARACTERISTIC_ORDER:
			continue
		var number := int(value[key])
		if allow_zero or number > 0:
			output[name] = number
	return output


func _clean_resolution_dictionary(value: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for choice_id: Variant in value:
		if not value[choice_id] is Array:
			continue
		var entries: Array[String] = []
		for answer_id: Variant in value[choice_id]:
			var clean_id := str(answer_id)
			if not clean_id.is_empty() and clean_id not in entries:
				entries.append(clean_id)
		if not entries.is_empty():
			output[str(choice_id)] = entries
	return output
