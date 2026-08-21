extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/interoperability_test.gd
##
## These tests protect OWCA's JSON boundary as a public API. They deliberately
## inspect the written envelopes as an external consumer would, then verify that
## previews cannot override authoritative state when a file is loaded again.

const REGIMENT_PATH := "user://owca_interop_regiment.owreg.json"
const REGIMENT_ROUNDTRIP_PATH := "user://owca_interop_regiment_roundtrip.owreg.json"
const CHARACTER_PATH := "user://owca_interop_character.owchar.json"
const CHARACTER_ROUNDTRIP_PATH := "user://owca_interop_character_roundtrip.owchar.json"
const MUTATED_PATH := "user://owca_interop_mutated.json"
const InventoryService = preload("res://OWCA/scripts/character_inventory_service.gd")

var _failures := 0


func _init() -> void:
	_cleanup_test_files()
	var regiment_repository := RegimentDataRepository.new()
	_assert_equal(regiment_repository.load_data(), OK, "regiment rules load")
	var character_repository := CharacterDataRepository.new()
	_assert_equal(character_repository.load_data(), OK, "character rules load")

	_test_regiment_contract(regiment_repository)
	_test_character_contract(regiment_repository, character_repository)
	_test_published_examples(regiment_repository)
	_test_schema_documents()
	_cleanup_test_files()

	if _failures > 0:
		printerr("OWCA interoperability tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA interoperability tests passed.")
	quit(0)


func _test_regiment_contract(repository: RegimentDataRepository) -> void:
	var state := RegimentState.new()
	state.load_example()
	state.mark_creation_complete()
	state.interoperability_extensions = {
		"com.example.combat/regiment": {
			"external_id": "regiment-13",
			"initiative_note": "consumer-owned example"
		}
	}
	var persistence := RegimentPersistence.new()
	var save_result := persistence.save_regiment(REGIMENT_PATH, state, repository)
	_assert_equal(save_result.get("error"), OK, "regiment save succeeds")

	var envelope := _read_json(REGIMENT_PATH)
	_assert_equal(envelope.get("format"), RegimentPersistence.FILE_FORMAT, "regiment format discriminator")
	_assert_equal(envelope.get("schema_version"), RegimentPersistence.SCHEMA_VERSION, "regiment public schema version")
	_assert_equal(envelope.get("equipment_rules_content_version"), "0.8.0-core-weapon-modifications", "regiment records equipment rules version")
	_assert_equal(envelope.get("version"), RegimentPersistence.FILE_VERSION, "current regiment envelope version")
	_assert_true(DocumentIdentity.is_valid(str(_nested(envelope, ["regiment", "document_id"]))), "regiment has a durable document ID")
	_assert_equal(_nested(envelope, ["regiment", "workflow_state"]), RegimentState.WORKFLOW_COMPLETE, "regiment completion state is explicit")
	_assert_equal((envelope.get("producer", {}) as Dictionary).get("version"), str(ProjectSettings.get_setting("application/config/version", "unknown")), "producer version is recorded")
	_assert_equal(_nested(envelope, ["regiment", "selections", "home_world", 0]), "hive_world", "regiment selection uses a stable ID")
	_assert_equal(_nested(envelope, ["calculated_preview", "points_spent"]), 12, "regiment preview includes point totals")
	_assert_equal(_nested(envelope, ["calculated_preview", "optional_doctrines_used"]), 2, "regiment preview separates optional doctrines")
	_assert_true((envelope.get("calculated_preview", {}) as Dictionary).has("equipment"), "regiment preview includes calculated equipment")

	var loaded := RegimentState.new()
	var load_result := persistence.load_regiment(REGIMENT_PATH, loaded, repository)
	_assert_equal(load_result.get("error"), OK, "regiment contract loads")
	_assert_equal(loaded.interoperability_extensions, state.interoperability_extensions, "regiment extensions load intact")
	_assert_equal(loaded.document_id, state.document_id, "regiment document identity loads intact")
	_assert_equal(persistence.save_regiment(REGIMENT_ROUNDTRIP_PATH, loaded, repository).get("error"), OK, "loaded regiment saves again")
	var roundtrip := _read_json(REGIMENT_ROUNDTRIP_PATH)
	_assert_equal(roundtrip.get("extensions"), state.interoperability_extensions, "regiment extensions round-trip intact")
	_assert_equal(_nested(roundtrip, ["regiment", "document_id"]), state.document_id, "Save As preserves regiment identity")

	var duplicate_state := RegimentState.new()
	_assert_equal(duplicate_state.from_dict(state.to_dict()), OK, "clone regiment for Duplicate")
	duplicate_state.duplicate_identity()
	_assert_true(duplicate_state.document_id != state.document_id, "Duplicate creates a new regiment identity")
	_assert_equal(duplicate_state.workflow_state, RegimentState.WORKFLOW_DRAFT, "Duplicate resets regiment lifecycle to draft")
	var edited_state := RegimentState.new()
	_assert_equal(edited_state.from_dict(state.to_dict()), OK, "clone completed regiment for edit")
	edited_state.set_option("training_doctrine", "close_order_drill", false, 2)
	_assert_equal(edited_state.workflow_state, RegimentState.WORKFLOW_DRAFT, "editing a completed regiment reopens draft")

	# Pre-v0.5.1 envelopes had no public schema field. They remain supported.
	var legacy := envelope.duplicate(true)
	legacy["version"] = 1
	legacy.erase("schema_version")
	legacy.erase("producer")
	legacy.erase("extensions")
	legacy.erase("calculated_preview")
	(legacy["regiment"] as Dictionary)["version"] = 1
	(legacy["regiment"] as Dictionary).erase("document_id")
	(legacy["regiment"] as Dictionary).erase("workflow_state")
	_write_json(MUTATED_PATH, legacy)
	var legacy_state := RegimentState.new()
	var legacy_result := persistence.load_regiment(MUTATED_PATH, legacy_state, repository)
	_assert_equal(legacy_result.get("error"), OK, "legacy regiment envelope loads")
	_assert_true(DocumentIdentity.is_valid(legacy_state.document_id), "legacy regiment receives a document ID")
	_assert_equal(legacy_state.workflow_state, RegimentState.WORKFLOW_DRAFT, "legacy regiment safely defaults to draft")
	_assert_true(_array_contains_fragment(legacy_result.get("migration_report", []) as Array, "document ID"), "regiment migration report explains generated identity")

	var invalid_identity := envelope.duplicate(true)
	(invalid_identity["regiment"] as Dictionary)["document_id"] = "not-a-document-id"
	_write_json(MUTATED_PATH, invalid_identity)
	_assert_equal(persistence.load_regiment(MUTATED_PATH, RegimentState.new(), repository).get("error"), ERR_INVALID_DATA, "invalid current regiment document ID is rejected")

	var future := envelope.duplicate(true)
	future["schema_version"] = "2.0.0"
	_write_json(MUTATED_PATH, future)
	_assert_equal(persistence.load_regiment(MUTATED_PATH, RegimentState.new(), repository).get("error"), ERR_INVALID_DATA, "future regiment schema major is rejected")
	var malformed_version := envelope.duplicate(true)
	malformed_version["schema_version"] = "1.x"
	_write_json(MUTATED_PATH, malformed_version)
	_assert_equal(persistence.load_regiment(MUTATED_PATH, RegimentState.new(), repository).get("error"), ERR_INVALID_DATA, "malformed regiment schema version is rejected")
	malformed_version["schema_version"] = "1.-1.0"
	_write_json(MUTATED_PATH, malformed_version)
	_assert_equal(persistence.load_regiment(MUTATED_PATH, RegimentState.new(), repository).get("error"), ERR_INVALID_DATA, "negative schema version component is rejected")

	var invalid_extensions := envelope.duplicate(true)
	invalid_extensions["extensions"] = []
	_write_json(MUTATED_PATH, invalid_extensions)
	_assert_equal(persistence.load_regiment(MUTATED_PATH, RegimentState.new(), repository).get("error"), ERR_INVALID_DATA, "invalid regiment extensions container is rejected")
	invalid_extensions["extensions"] = { "unowned_key": {} }
	_write_json(MUTATED_PATH, invalid_extensions)
	_assert_equal(persistence.load_regiment(MUTATED_PATH, RegimentState.new(), repository).get("error"), ERR_INVALID_DATA, "non-namespaced regiment extension is rejected")
	var invalid_state := RegimentState.new()
	invalid_state.interoperability_extensions = { "unowned_key": {} }
	_assert_equal(persistence.save_regiment(REGIMENT_ROUNDTRIP_PATH, invalid_state, repository).get("error"), ERR_INVALID_DATA, "OWCA refuses to write invalid extension keys")


func _test_character_contract(regiment_repository: RegimentDataRepository, character_repository: CharacterDataRepository) -> void:
	var regiment := RegimentState.new()
	regiment.load_example()
	var state := CharacterState.new()
	state.set_character_name("Varanox Operator")
	state.set_player_name("Interoperability Test")
	state.set_regiment(regiment.to_dict(), str(regiment_repository.data.get("content_version", "")))
	for characteristic in CharacterState.CHARACTERISTIC_ORDER:
		state.set_base_characteristic(characteristic, 30)
	state.set_speciality("operator")
	state.set_wounds_roll(3)
	state.set_fate_roll(8)
	state.set_choice("regiment", "hive_characteristic_1", "agility")
	state.set_choice("regiment", "hive_characteristic_2", "fellowship")
	state.set_choice("regiment", "hive_urban_violence", "paranoia")
	state.set_choice("regiment", "close_order_talent", "combat_formation")
	state.set_choice("speciality", "operator_knowledge_skill", "common_lore_tech")
	state.set_choice("speciality", "operator_weapon_training", "las")
	state.purchase_advance("skill:tech_use")
	var starting_calculation := CharacterCalculator.new().calculate(state, regiment_repository, character_repository)
	var inventory_service: RefCounted = InventoryService.new()
	inventory_service.call("materialize_starting_loadout", state, starting_calculation.get("equipment", []) as Array, character_repository.equipment_repository, "2026-08-09T12:00:00Z")
	var added_weapon: Dictionary = inventory_service.call("add_item", state, character_repository.equipment_repository, "m36_lasgun", 1, "Common", "acquisition", "carried", "character", "", "Modification round-trip fixture", "2026-08-09T12:05:00Z")
	_assert_equal(added_weapon.get("error"), OK, "round-trip weapon fixture is added")
	var modified_instance_id := str((added_weapon.get("instance_ids", []) as Array)[0])
	for item: Dictionary in state.owned_items:
		if str(item.get("instance_id", "")) == modified_instance_id:
			item["modification_ids"] = ["red_dot_laser_sight"]
	for event: Dictionary in state.inventory_events:
		if str(event.get("instance_id", "")) == modified_instance_id:
			(event.get("item_snapshot", {}) as Dictionary)["modification_ids"] = ["red_dot_laser_sight"]
	inventory_service.call("finalize_loadout", state, character_repository.equipment_repository, starting_calculation.get("starting_equipment", []) as Array)
	state.mark_creation_complete()
	state.interoperability_extensions = {
		"com.example.combat/character": {
			"external_id": "character-operator-1"
		}
	}

	var calculation := CharacterCalculator.new().calculate(state, regiment_repository, character_repository)
	_assert_true(bool(calculation.get("valid", false)), "test character is valid")
	var persistence := CharacterPersistence.new()
	_assert_equal(persistence.save_character(CHARACTER_PATH, state, calculation, character_repository).get("error"), OK, "character save succeeds")

	var envelope := _read_json(CHARACTER_PATH)
	_assert_equal(envelope.get("format"), CharacterPersistence.FILE_FORMAT, "character format discriminator")
	_assert_equal(envelope.get("schema_version"), CharacterPersistence.SCHEMA_VERSION, "character public schema version")
	_assert_equal(envelope.get("equipment_rules_content_version"), "0.8.0-core-weapon-modifications", "character records equipment rules version")
	_assert_equal(envelope.get("inventory_rules_content_version"), "0.7.0-core-inventory", "character records inventory rules version")
	_assert_equal(envelope.get("version"), CharacterPersistence.FILE_VERSION, "current character envelope version")
	_assert_true(DocumentIdentity.is_valid(str(_nested(envelope, ["character", "document_id"]))), "character has a durable document ID")
	_assert_equal(_nested(envelope, ["character", "workflow_state"]), CharacterState.WORKFLOW_COMPLETE, "character completion state is explicit")
	_assert_equal(_nested(envelope, ["character", "loadout_state"]), CharacterState.LOADOUT_FINALIZED, "character loadout finalization is explicit")
	_assert_true((_nested(envelope, ["character", "owned_items"]) as Array).size() > 0, "owned inventory is authoritative")
	_assert_true((_nested(envelope, ["character", "inventory_events"]) as Array).size() > 0, "inventory audit history is authoritative")
	for owned_value: Variant in _nested(envelope, ["character", "owned_items"]) as Array:
		_assert_true((owned_value as Dictionary).get("modification_ids", null) is Array, "every owned item serializes modification IDs")
	for event_value: Variant in _nested(envelope, ["character", "inventory_events"]) as Array:
		_assert_true(((event_value as Dictionary).get("item_snapshot", {}) as Dictionary).get("modification_ids", null) is Array, "every event snapshot serializes modification IDs")
	_assert_equal(_nested(envelope, ["character", "speciality_id"]), "operator", "Speciality uses a stable ID")
	_assert_equal(_nested(envelope, ["character", "purchased_advances", 0]), "skill:tech_use", "advancement ledger uses a stable ID")
	_assert_true((_nested(envelope, ["calculated_preview", "skills"]) as Array).size() > 0, "character preview includes calculated Skills")
	_assert_true((_nested(envelope, ["calculated_preview", "talents"]) as Array).size() > 0, "character preview includes calculated Talents")
	_assert_true((_nested(envelope, ["calculated_preview", "equipment"]) as Array).size() > 0, "character preview includes calculated equipment")
	_assert_true((_nested(envelope, ["calculated_preview", "inventory", "items"]) as Array).size() > 0, "character preview includes calculated inventory")

	# Calculated previews are caches, not an alternate way to modify a character.
	var mutated := envelope.duplicate(true)
	(mutated["calculated_preview"] as Dictionary)["characteristics"] = { "Agility": 999 }
	_write_json(MUTATED_PATH, mutated)
	var loaded := CharacterState.new()
	_assert_equal(persistence.load_character(MUTATED_PATH, loaded).get("error"), OK, "character with modified preview loads")
	var recalculated := CharacterCalculator.new().calculate(loaded, regiment_repository, character_repository)
	_assert_equal(recalculated["characteristics"]["Agility"], calculation["characteristics"]["Agility"], "load ignores calculated preview")
	_assert_equal(loaded.interoperability_extensions, state.interoperability_extensions, "character extensions load intact")
	_assert_equal(loaded.document_id, state.document_id, "character document identity loads intact")
	_assert_equal(_modifications_for_instance(loaded.owned_items, modified_instance_id), ["red_dot_laser_sight"], "installed modification survives load")
	_assert_equal(persistence.save_character(CHARACTER_ROUNDTRIP_PATH, loaded, recalculated, character_repository).get("error"), OK, "loaded character saves again")
	_assert_equal(_read_json(CHARACTER_ROUNDTRIP_PATH).get("extensions"), state.interoperability_extensions, "character extensions round-trip intact")
	_assert_equal(_nested(_read_json(CHARACTER_ROUNDTRIP_PATH), ["character", "document_id"]), state.document_id, "Save As preserves character identity")
	var duplicate_state := CharacterState.new()
	_assert_equal(duplicate_state.from_dict(state.to_dict()), OK, "clone character for Duplicate")
	duplicate_state.duplicate_identity()
	_assert_true(duplicate_state.document_id != state.document_id, "Duplicate creates a new character identity")
	_assert_equal(duplicate_state.workflow_state, CharacterState.WORKFLOW_DRAFT, "Duplicate resets character lifecycle to draft")
	_assert_true(str(_nested(duplicate_state.to_dict(), ["owned_items", 0, "instance_id"])) != str(_nested(state.to_dict(), ["owned_items", 0, "instance_id"])), "Duplicate regenerates owned item identities")
	var edited_state := CharacterState.new()
	_assert_equal(edited_state.from_dict(state.to_dict()), OK, "clone completed character for edit")
	edited_state.set_base_characteristic("Agility", 31)
	_assert_equal(edited_state.workflow_state, CharacterState.WORKFLOW_DRAFT, "editing a completed character reopens draft")

	var version_four := envelope.duplicate(true)
	version_four["version"] = 4
	version_four["schema_version"] = "1.3.0"
	var version_four_state_data := version_four["character"] as Dictionary
	version_four_state_data["version"] = 4
	for owned_value: Variant in version_four_state_data.get("owned_items", []):
		(owned_value as Dictionary).erase("modification_ids")
	for grant_value: Variant in version_four_state_data.get("starting_loadout", []):
		(grant_value as Dictionary).erase("craftsmanship")
	for event_value: Variant in version_four_state_data.get("inventory_events", []):
		((event_value as Dictionary).get("item_snapshot", {}) as Dictionary).erase("modification_ids")
	_write_json(MUTATED_PATH, version_four)
	var migrated_version_four := CharacterState.new()
	var version_four_result := persistence.load_character(MUTATED_PATH, migrated_version_four)
	_assert_equal(version_four_result.get("error"), OK, "version 4 finalized character loads")
	_assert_equal(migrated_version_four.loadout_state, CharacterState.LOADOUT_FINALIZED, "version 4 keeps finalized loadout lifecycle")
	_assert_equal(migrated_version_four.workflow_state, CharacterState.WORKFLOW_COMPLETE, "version 4 keeps completed workflow lifecycle")
	for item: Dictionary in migrated_version_four.owned_items:
		_assert_equal(item.get("modification_ids"), [], "version 4 owned items gain empty modification arrays")
	for event: Dictionary in migrated_version_four.inventory_events:
		_assert_equal((event.get("item_snapshot", {}) as Dictionary).get("modification_ids"), [], "version 4 snapshots gain empty modification arrays")
	_assert_true(_array_contains_fragment(version_four_result.get("migration_report", []) as Array, "Initialized empty weapon modification state"), "version 4 migration reports modification initialization")
	_assert_true(not _array_contains_fragment(version_four_result.get("migration_report", []) as Array, "unprepared loadout"), "version 4 migration does not claim loadout reset")

	var lost_legacy_alias := version_four.duplicate(true)
	var lost_state_data := lost_legacy_alias["character"] as Dictionary
	var lost_grant := (lost_state_data.get("starting_loadout", []) as Array)[0] as Dictionary
	var lost_ids := lost_grant.get("issued_instance_ids", []) as Array
	lost_grant["definition_id"] = "lasgun_good"
	lost_grant["reconciliation"] = "loss"
	lost_grant["note"] = "Lost before v5 migration"
	var legacy_owned := lost_state_data.get("owned_items", []) as Array
	for index in range(legacy_owned.size() - 1, -1, -1):
		if str((legacy_owned[index] as Dictionary).get("instance_id", "")) in lost_ids:
			legacy_owned.remove_at(index)
	_write_json(MUTATED_PATH, lost_legacy_alias)
	var lost_legacy_state := CharacterState.new()
	_assert_equal(persistence.load_character(MUTATED_PATH, lost_legacy_state).get("error"), OK, "lost v4 legacy-alias grant loads")
	_assert_equal(lost_legacy_state.starting_loadout[0].get("craftsmanship"), "Good", "lost v4 legacy alias migrates from its definition default")

	var legacy := envelope.duplicate(true)
	legacy["version"] = 2
	legacy.erase("schema_version")
	legacy.erase("producer")
	legacy.erase("extensions")
	legacy.erase("calculated_preview")
	(legacy["character"] as Dictionary)["version"] = 2
	(legacy["character"] as Dictionary).erase("document_id")
	(legacy["character"] as Dictionary).erase("workflow_state")
	var legacy_regiment := (legacy["character"] as Dictionary)["regiment"] as Dictionary
	legacy_regiment["version"] = 1
	legacy_regiment.erase("document_id")
	legacy_regiment.erase("workflow_state")
	_write_json(MUTATED_PATH, legacy)
	var version_two_state := CharacterState.new()
	var version_two_result := persistence.load_character(MUTATED_PATH, version_two_state)
	_assert_equal(version_two_result.get("error"), OK, "version 2 character envelope loads")
	_assert_true(DocumentIdentity.is_valid(version_two_state.document_id), "version 2 character receives a document ID")
	_assert_equal(version_two_state.workflow_state, CharacterState.WORKFLOW_DRAFT, "version 2 character safely defaults to draft")
	_assert_true(_array_contains_fragment(version_two_result.get("migration_report", []) as Array, "document ID"), "character migration report explains generated identity")
	_assert_equal(version_two_state.loadout_state, CharacterState.LOADOUT_UNPREPARED, "legacy character receives an unprepared loadout")
	_assert_true(_array_contains_fragment(version_two_result.get("migration_report", []) as Array, "loadout"), "character migration report explains inventory preparation")
	_assert_equal(version_two_state.regiment.get("version"), RegimentState.SAVE_VERSION, "legacy embedded regiment migrates to the current state version")
	_assert_true(DocumentIdentity.is_valid(str(version_two_state.regiment.get("document_id", ""))), "legacy embedded regiment receives a document ID")
	_assert_equal(version_two_state.regiment.get("workflow_state"), RegimentState.WORKFLOW_DRAFT, "legacy embedded regiment safely defaults to draft")
	_assert_true(_array_contains_fragment(version_two_result.get("migration_report", []) as Array, "embedded regiment"), "character migration report explains embedded regiment migration")
	var migrated_calculation := CharacterCalculator.new().calculate(version_two_state, regiment_repository, character_repository)
	_assert_equal(persistence.save_character(CHARACTER_ROUNDTRIP_PATH, version_two_state, migrated_calculation, character_repository).get("error"), OK, "migrated legacy character writes a current envelope")
	var migrated_envelope := _read_json(CHARACTER_ROUNDTRIP_PATH)
	_assert_equal(_nested(migrated_envelope, ["character", "regiment", "version"]), RegimentState.SAVE_VERSION, "migrated character writes a current embedded regiment")
	_assert_true(DocumentIdentity.is_valid(str(_nested(migrated_envelope, ["character", "regiment", "document_id"]))), "migrated character writes the embedded regiment identity")

	var version_one := legacy.duplicate(true)
	version_one["version"] = 1
	(version_one["character"] as Dictionary)["version"] = 1
	(version_one["character"] as Dictionary).erase("purchased_advances")
	_write_json(MUTATED_PATH, version_one)
	var version_one_state := CharacterState.new()
	_assert_equal(persistence.load_character(MUTATED_PATH, version_one_state).get("error"), OK, "character envelope/state version 1 loads")
	_assert_true(version_one_state.purchased_advances.is_empty(), "version 1 character defaults to no purchases")

	var version_three_campaign := envelope.duplicate(true)
	version_three_campaign["version"] = 3
	var version_three_state_data := version_three_campaign["character"] as Dictionary
	version_three_state_data["version"] = 3
	version_three_state_data["workflow_state"] = CharacterState.WORKFLOW_CAMPAIGN
	for inventory_field in ["comrade", "loadout_state", "starting_loadout", "owned_items", "inventory_events"]:
		version_three_state_data.erase(inventory_field)
	_write_json(MUTATED_PATH, version_three_campaign)
	var migrated_campaign := CharacterState.new()
	var campaign_result := persistence.load_character(MUTATED_PATH, migrated_campaign)
	_assert_equal(campaign_result.get("error"), OK, "version 3 campaign character loads")
	_assert_equal(migrated_campaign.workflow_state, CharacterState.WORKFLOW_DRAFT, "legacy campaign lifecycle returns to draft")
	_assert_equal(migrated_campaign.loadout_state, CharacterState.LOADOUT_UNPREPARED, "legacy campaign receives an unprepared loadout")
	_assert_true(_array_contains_fragment(campaign_result.get("migration_report", []) as Array, "Returned the legacy character to draft"), "campaign migration report explains lifecycle reset")

	var invalid_identity := envelope.duplicate(true)
	(invalid_identity["character"] as Dictionary)["document_id"] = "not-a-document-id"
	_write_json(MUTATED_PATH, invalid_identity)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "invalid current character document ID is rejected")

	var duplicate_item_id := envelope.duplicate(true)
	var duplicate_items := _nested(duplicate_item_id, ["character", "owned_items"]) as Array
	duplicate_items.append((duplicate_items[0] as Dictionary).duplicate(true))
	_write_json(MUTATED_PATH, duplicate_item_id)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "duplicate owned-item durable IDs are rejected")

	var duplicate_modifications := envelope.duplicate(true)
	var duplicate_weapon := _find_owned_definition(_nested(duplicate_modifications, ["character", "owned_items"]) as Array, "m36_lasgun")
	duplicate_weapon["modification_ids"] = ["compact_upgrade", "compact_upgrade"]
	_write_json(MUTATED_PATH, duplicate_modifications)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "duplicate weapon modification IDs are rejected")

	var grenade_modification := envelope.duplicate(true)
	var grenade_item := _find_owned_definition(_nested(grenade_modification, ["character", "owned_items"]) as Array, "frag_grenade")
	grenade_item["modification_ids"] = ["compact_upgrade"]
	_write_json(MUTATED_PATH, grenade_modification)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "grenades reject installed modifications")

	var missing_modification := envelope.duplicate(true)
	var missing_mod_weapon := _find_owned_definition(_nested(missing_modification, ["character", "owned_items"]) as Array, "m36_lasgun")
	missing_mod_weapon["modification_ids"] = ["retired_upgrade"]
	_write_json(MUTATED_PATH, missing_modification)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "missing weapon modifications are rejected")

	var incompatible_sights := envelope.duplicate(true)
	var sight_weapon := _find_owned_definition(_nested(incompatible_sights, ["character", "owned_items"]) as Array, "m36_lasgun")
	sight_weapon["modification_ids"] = ["red_dot_laser_sight", "telescopic_sight"]
	_write_json(MUTATED_PATH, incompatible_sights)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "incompatible sight combinations are rejected")

	var malformed_modifications := envelope.duplicate(true)
	var malformed_mod_weapon := _find_owned_definition(_nested(malformed_modifications, ["character", "owned_items"]) as Array, "m36_lasgun")
	malformed_mod_weapon["modification_ids"] = "compact_upgrade"
	_write_json(MUTATED_PATH, malformed_modifications)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "malformed weapon modification arrays are rejected")

	var duplicate_issued_link := envelope.duplicate(true)
	var duplicate_grants := _nested(duplicate_issued_link, ["character", "starting_loadout"]) as Array
	(duplicate_grants[1] as Dictionary)["issued_instance_ids"] = ((duplicate_grants[0] as Dictionary).get("issued_instance_ids", []) as Array).duplicate()
	_write_json(MUTATED_PATH, duplicate_issued_link)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "one issued durable item cannot satisfy two starting grants")

	var missing_present_item := envelope.duplicate(true)
	var missing_grant := _nested(missing_present_item, ["character", "starting_loadout", 0]) as Dictionary
	var missing_ids := missing_grant.get("issued_instance_ids", []) as Array
	var missing_items := _nested(missing_present_item, ["character", "owned_items"]) as Array
	for index in range(missing_items.size() - 1, -1, -1):
		if str((missing_items[index] as Dictionary).get("instance_id", "")) in missing_ids:
			missing_items.remove_at(index)
	_write_json(MUTATED_PATH, missing_present_item)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "finalized present grants require their issued owned records")

	var insufficient_present_quantity := envelope.duplicate(true)
	var quantity_grants := _nested(insufficient_present_quantity, ["character", "starting_loadout"]) as Array
	var quantity_items := _nested(insufficient_present_quantity, ["character", "owned_items"]) as Array
	for quantity_grant_value: Variant in quantity_grants:
		var quantity_grant := quantity_grant_value as Dictionary
		if int(quantity_grant.get("quantity", 0)) <= 1:
			continue
		var quantity_ids := quantity_grant.get("issued_instance_ids", []) as Array
		for quantity_item_value: Variant in quantity_items:
			var quantity_item := quantity_item_value as Dictionary
			if str(quantity_item.get("instance_id", "")) in quantity_ids:
				quantity_item["quantity"] = int(quantity_grant.get("quantity", 0)) - 1
				break
		break
	_write_json(MUTATED_PATH, insufficient_present_quantity)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "finalized present grants require their exact issued quantity")

	var unexplained_reconciliation := envelope.duplicate(true)
	var unexplained_grant := _nested(unexplained_reconciliation, ["character", "starting_loadout", 0]) as Dictionary
	unexplained_grant["reconciliation"] = "loss"
	unexplained_grant["note"] = ""
	_write_json(MUTATED_PATH, unexplained_reconciliation)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "finalized non-present reconciliations require an explanation")

	for mutation in [
		["definition_id", "Invalid Definition!", "malformed definition IDs"],
		["quantity", 0, "nonpositive owned quantities"],
		["quantity", 1.5, "fractional owned quantities"],
		["location", "pocket", "invalid owned locations"],
		["origin", "loot", "invalid owned origins"],
		["craftsmanship", "Legendary", "invalid craftsmanship"],
		["note", 7, "malformed item notes"]
	]:
		var invalid_item := envelope.duplicate(true)
		var item := _nested(invalid_item, ["character", "owned_items", 0]) as Dictionary
		item[str(mutation[0])] = mutation[1]
		_write_json(MUTATED_PATH, invalid_item)
		_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "%s are rejected" % mutation[2])

	var invalid_owner := envelope.duplicate(true)
	(_nested(invalid_owner, ["character", "owned_items", 0, "custodian"]) as Dictionary)["type"] = "quartermaster"
	_write_json(MUTATED_PATH, invalid_owner)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "invalid item custodians are rejected")

	var malformed_comrade := envelope.duplicate(true)
	(malformed_comrade["character"] as Dictionary)["comrade"] = { "id": "not-a-uuid", "name": "" }
	_write_json(MUTATED_PATH, malformed_comrade)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "malformed Comrade records are rejected")

	var malformed_timestamp := envelope.duplicate(true)
	(_nested(malformed_timestamp, ["character", "inventory_events", 0]) as Dictionary)["timestamp_utc"] = "yesterday"
	_write_json(MUTATED_PATH, malformed_timestamp)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "malformed inventory timestamps are rejected")

	var unrelated_snapshot := envelope.duplicate(true)
	var event := _nested(unrelated_snapshot, ["character", "inventory_events", 0]) as Dictionary
	(event.get("item_snapshot", {}) as Dictionary)["definition_id"] = "medikit" if str(event.get("definition_id", "")) != "medikit" else "knife"
	_write_json(MUTATED_PATH, unrelated_snapshot)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "inventory event snapshots must describe their event")

	var invalid_lifecycle := envelope.duplicate(true)
	(invalid_lifecycle["character"] as Dictionary)["loadout_state"] = CharacterState.LOADOUT_UNPREPARED
	_write_json(MUTATED_PATH, invalid_lifecycle)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "completed characters cannot carry an unprepared inventory state")

	var stacked_weapon := envelope.duplicate(true)
	var stacked_items := _nested(stacked_weapon, ["character", "owned_items"]) as Array
	for stacked_value: Variant in stacked_items:
		var candidate := stacked_value as Dictionary
		var definition := character_repository.equipment_repository.get_item(str(candidate.get("definition_id", "")))
		if str(definition.get("category", "")) in ["ranged_weapon", "melee_weapon", "armour"]:
			candidate["quantity"] = 2
			break
	_write_json(MUTATED_PATH, stacked_weapon)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "stacked weapons and armour are rejected at load")

	var retired_definition := envelope.duplicate(true)
	var retired_item := _nested(retired_definition, ["character", "owned_items", 0]) as Dictionary
	var retired_instance_id := str(retired_item.get("instance_id", ""))
	retired_item["definition_id"] = "retired_catalogue_item"
	for retired_grant_value: Variant in _nested(retired_definition, ["character", "starting_loadout"]) as Array:
		var retired_grant := retired_grant_value as Dictionary
		if retired_instance_id in (retired_grant.get("issued_instance_ids", []) as Array):
			retired_grant["definition_id"] = "retired_catalogue_item"
	for retired_event_value: Variant in _nested(retired_definition, ["character", "inventory_events"]) as Array:
		var retired_event := retired_event_value as Dictionary
		if str(retired_event.get("instance_id", "")) == retired_instance_id:
			retired_event["definition_id"] = "retired_catalogue_item"
			(retired_event.get("item_snapshot", {}) as Dictionary)["definition_id"] = "retired_catalogue_item"
	_write_json(MUTATED_PATH, retired_definition)
	var retired_state := CharacterState.new()
	var retired_result := persistence.load_character(MUTATED_PATH, retired_state)
	_assert_equal(retired_result.get("error"), OK, "well-formed IDs missing from a newer catalogue remain recoverable")
	_assert_equal(retired_state.loadout_state, CharacterState.LOADOUT_DRAFT, "missing catalogue definitions invalidate prior loadout finalization")
	_assert_equal(retired_state.workflow_state, CharacterState.WORKFLOW_DRAFT, "a newly unresolved finalized loadout returns to draft")
	_assert_true(_array_contains_fragment(retired_result.get("migration_report", []) as Array, "catalogue definitions are missing"), "missing definition recovery is explained to the player")

	var future := envelope.duplicate(true)
	future["schema_version"] = "2.0.0"
	_write_json(MUTATED_PATH, future)
	_assert_equal(persistence.load_character(MUTATED_PATH, CharacterState.new()).get("error"), ERR_INVALID_DATA, "future character schema major is rejected")


func _test_schema_documents() -> void:
	for path in [
		"res://OWCA/data/owca_regiment_save.schema.json",
		"res://OWCA/data/owca_character_save.schema.json"
	]:
		var schema := _read_json(path)
		_assert_equal(schema.get("$schema"), "https://json-schema.org/draft/2020-12/schema", "%s uses JSON Schema 2020-12" % path)
		_assert_true("schema_version" in (schema.get("required", []) as Array), "%s requires the public schema version" % path)
	var regiment_schema := _read_json("res://OWCA/data/owca_regiment_save.schema.json")
	var regiment_required := (((regiment_schema.get("$defs", {}) as Dictionary).get("regiment_state", {}) as Dictionary).get("required", []) as Array)
	_assert_true("document_id" in regiment_required and "workflow_state" in regiment_required, "regiment schema requires identity and lifecycle")
	var character_schema := _read_json("res://OWCA/data/owca_character_save.schema.json")
	var character_required := (((character_schema.get("$defs", {}) as Dictionary).get("character_state", {}) as Dictionary).get("required", []) as Array)
	_assert_true("document_id" in character_required and "workflow_state" in character_required, "character schema requires identity and lifecycle")
	for field_name in ["comrade", "loadout_state", "starting_loadout", "owned_items", "inventory_events"]:
		_assert_true(field_name in character_required, "character schema requires %s" % field_name)
	var starting_required := (((character_schema.get("$defs", {}) as Dictionary).get("starting_grant", {}) as Dictionary).get("required", []) as Array)
	_assert_true("origin" in starting_required and "craftsmanship" in starting_required, "character schema requires starting-grant provenance and craftsmanship")
	var owned_required := (((character_schema.get("$defs", {}) as Dictionary).get("owned_item", {}) as Dictionary).get("required", []) as Array)
	_assert_true("modification_ids" in owned_required, "character schema requires owned-item modifications")
	var snapshot_required := (((((character_schema.get("$defs", {}) as Dictionary).get("inventory_event", {}) as Dictionary).get("properties", {}) as Dictionary).get("item_snapshot", {}) as Dictionary).get("required", []) as Array)
	_assert_true("modification_ids" in snapshot_required, "character schema requires event-snapshot modifications")


func _test_published_examples(regiment_repository: RegimentDataRepository) -> void:
	var regiment_state := RegimentState.new()
	var regiment_result := RegimentPersistence.new().load_regiment(
		"res://OWCA/examples/13th_varanox_light_infantry.owreg.json",
		regiment_state,
		regiment_repository
	)
	_assert_equal(regiment_result.get("error"), OK, "published regiment example loads")
	_assert_equal(regiment_result.get("schema_version"), InteroperabilityContract.SCHEMA_VERSION, "published regiment example declares current schema")
	_assert_equal(regiment_state.workflow_state, RegimentState.WORKFLOW_COMPLETE, "published regiment example is complete")
	var character_state := CharacterState.new()
	var character_result := CharacterPersistence.new().load_character(
		"res://OWCA/examples/varanox_weapon_specialist.owchar.json",
		character_state
	)
	_assert_equal(character_result.get("error"), OK, "published character example loads")
	_assert_equal(character_result.get("schema_version"), InteroperabilityContract.SCHEMA_VERSION, "published character example declares current schema")
	_assert_equal(character_state.workflow_state, CharacterState.WORKFLOW_COMPLETE, "published character example is complete")


func _array_contains_fragment(values: Array, fragment: String) -> bool:
	for value: Variant in values:
		if fragment in str(value):
			return true
	return false


func _find_owned_definition(items: Array, definition_id: String) -> Dictionary:
	for value: Variant in items:
		var item := value as Dictionary
		if str(item.get("definition_id", "")) == definition_id:
			return item
	return {}


func _modifications_for_instance(items: Array[Dictionary], instance_id: String) -> Array:
	for item: Dictionary in items:
		if str(item.get("instance_id", "")) == instance_id:
			return (item.get("modification_ids", []) as Array).duplicate()
	return []


func _cleanup_test_files() -> void:
	for base_path in [REGIMENT_PATH, REGIMENT_ROUNDTRIP_PATH, CHARACTER_PATH, CHARACTER_ROUNDTRIP_PATH, MUTATED_PATH]:
		for suffix in ["", AtomicJsonStore.TEMP_SUFFIX, AtomicJsonStore.BACKUP_SUFFIX, AtomicJsonStore.FAILED_SUFFIX, AtomicJsonStore.FAILED_SUFFIX + AtomicJsonStore.TEMP_SUFFIX]:
			var path := ProjectSettings.globalize_path(base_path + suffix)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_assert_true(false, "open JSON for reading: %s" % path)
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary:
		_assert_true(false, "parse JSON object: %s" % path)
		return {}
	return value as Dictionary


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_assert_true(false, "open JSON for writing: %s" % path)
		return
	file.store_string(JSON.stringify(value, "  "))


func _nested(root: Variant, path: Array) -> Variant:
	var current: Variant = root
	for key: Variant in path:
		if key is int:
			if not current is Array or int(key) < 0 or int(key) >= (current as Array).size():
				return null
			current = (current as Array)[int(key)]
		else:
			if not current is Dictionary or not (current as Dictionary).has(key):
				return null
			current = (current as Dictionary)[key]
	return current


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("FAIL: %s" % label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures += 1
	printerr("FAIL: %s (expected %s, got %s)" % [label, expected, actual])
