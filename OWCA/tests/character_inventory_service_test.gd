extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/character_inventory_service_test.gd
##
## Protects the authoritative owned-inventory boundary introduced in v0.7.

var _failures := 0
const InventoryService = preload("res://OWCA/scripts/character_inventory_service.gd")


func _init() -> void:
	var service_script := load("res://OWCA/scripts/character_inventory_service.gd")
	_assert_true(service_script != null, "inventory service script is available")
	_test_v5_state_defaults()
	_test_starting_loadout_materializes_once()
	_test_mixed_issue_origins_materialize_separately()
	_test_stackable_quantity_splits_safely()
	_test_identical_weapons_remain_separate()
	_test_craftsmanship_aware_starting_grants()
	_test_individual_weapon_craftsmanship()
	_test_comrade_transfer_preserves_history()
	_test_duplicate_regenerates_comrade_links()
	_test_finalization_requires_materialized_grants()
	_test_finalization_requires_explicit_reconciliation()
	_test_creation_grant_changes_require_rebuild()
	_test_rebuild_preserves_later_acquisitions()
	_test_starting_provenance_changes_require_rebuild()
	_test_weapon_quantity_must_remain_one()
	_test_no_op_edits_do_not_append_history()
	_test_post_completion_inventory_maintenance_keeps_lifecycle()

	if _failures > 0:
		printerr("OWCA character inventory service tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA character inventory service tests passed.")
	quit(0)


func _test_v5_state_defaults() -> void:
	var state := CharacterState.new()
	var saved := state.to_dict()
	_assert_equal(saved.get("version"), 5, "character state writes version 5")
	_assert_equal(saved.get("loadout_state"), "unprepared", "new characters begin with an unprepared loadout")
	_assert_equal(saved.get("comrade"), {}, "new characters have no Comrade identity")
	_assert_equal(saved.get("starting_loadout"), [], "new characters have no materialized grants")
	_assert_equal(saved.get("owned_items"), [], "new characters have no owned items")
	_assert_equal(saved.get("inventory_events"), [], "new characters have no inventory history")


func _test_starting_loadout_materializes_once() -> void:
	var repository := EquipmentDataRepository.new()
	_assert_equal(repository.load_data(), OK, "equipment catalogue loads for materialization")
	var state := CharacterState.new()
	var service: RefCounted = InventoryService.new()
	if not _require_method(service, "materialize_starting_loadout"):
		return
	var grants := [
		{ "id": "m36_lasgun", "quantity": 1, "scope": "per_character" },
		{ "id": "flak_vest", "quantity": 1, "scope": "per_character" },
		{ "id": "charge_pack", "quantity": 4, "scope": "per_character" },
		{ "id": "frag_grenade", "quantity": 2, "scope": "per_character" },
		{ "id": "medikit", "quantity": 1, "scope": "per_squad" }
	]
	var first: Dictionary = service.call("materialize_starting_loadout", state, grants, repository, "2026-08-09T12:00:00Z")
	_assert_equal(first.get("error"), OK, "starting loadout materializes")
	_assert_equal(state.loadout_state, CharacterState.LOADOUT_DRAFT, "materialization opens a draft loadout")
	_assert_equal(state.starting_loadout.size(), 5, "every calculated grant is recorded")
	_assert_equal(state.starting_loadout[0].get("reconciliation"), "present", "materialized grants begin reconciled as present")
	_assert_true(not (state.starting_loadout[0].get("issued_instance_ids", []) as Array).is_empty(), "grants retain their issued durable item IDs")
	_assert_equal(state.owned_items.size(), 5, "stackable grants become one owned row each")
	_assert_equal(state.inventory_events.size(), 5, "materialization records one issue event per row")
	for item: Dictionary in state.owned_items:
		_assert_equal(item.get("modification_ids"), [], "materialized items start without modifications")
	for event: Dictionary in state.inventory_events:
		_assert_equal((event.get("item_snapshot", {}) as Dictionary).get("modification_ids"), [], "issue snapshots start without modifications")
	_assert_equal(_item_quantity(state.owned_items, "charge_pack"), 4, "ammunition keeps catalogue-unit quantity")
	_assert_equal(_item_custodian(state.owned_items, "medikit"), "squad", "per-squad grants use squad custody")
	_assert_equal(_item_field(state.owned_items, "flak_vest", "location"), "equipped", "starting armour is equipped by default")
	var first_item_ids := _item_ids(state.owned_items)
	var second: Dictionary = service.call("materialize_starting_loadout", state, grants, repository, "2026-08-09T13:00:00Z")
	_assert_equal(second.get("error"), OK, "repeated materialization is a safe no-op")
	_assert_equal(_item_ids(state.owned_items), first_item_ids, "repeated materialization preserves instance IDs")
	_assert_equal(state.inventory_events.size(), 5, "repeated materialization adds no issue events")


func _test_identical_weapons_remain_separate() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var state := CharacterState.new()
	var service: RefCounted = InventoryService.new()
	if not _require_method(service, "materialize_starting_loadout"):
		return
	var result: Dictionary = service.call("materialize_starting_loadout",
		state,
		[{ "id": "laspistol", "quantity": 2, "scope": "per_character" }],
		repository,
		"2026-08-09T12:00:00Z"
	)
	_assert_equal(result.get("error"), OK, "duplicate weapon grant materializes")
	_assert_equal(state.owned_items.size(), 2, "two weapons become two instances")
	_assert_true(str(state.owned_items[0].get("instance_id")) != str(state.owned_items[1].get("instance_id")), "identical weapons have independent durable IDs")
	_assert_equal(int(state.owned_items[0].get("quantity")), 1, "weapon instance quantity is one")


func _test_craftsmanship_aware_starting_grants() -> void:
	var repository := EquipmentDataRepository.new()
	_assert_equal(repository.load_data(), OK, "equipment catalogue loads for craftsmanship grants")
	var service: RefCounted = InventoryService.new()
	var state := CharacterState.new()
	var good_grants := [{"id": "m36_lasgun", "quantity": 1, "scope": "per_character", "craftsmanship": "Good"}]
	_assert_equal((service.call("materialize_starting_loadout", state, good_grants, repository, "2026-08-09T12:00:00Z") as Dictionary).get("error"), OK, "Good base lasgun grant materializes")
	_assert_equal(state.owned_items[0].get("definition_id"), "m36_lasgun", "Good grant keeps the base weapon definition")
	_assert_equal(state.owned_items[0].get("craftsmanship"), "Good", "Good grant becomes owned-instance craftsmanship")
	_assert_equal(state.owned_items[0].get("modification_ids"), [], "Good grant starts without upgrades")
	_assert_equal(state.starting_loadout[0].get("craftsmanship"), "Good", "materialized grant records craftsmanship")
	_assert_true(not bool(service.call("starting_loadout_matches", state, [{"id": "m36_lasgun", "quantity": 1, "scope": "per_character", "craftsmanship": "Common"}])), "changing expected craftsmanship invalidates materialized grants")

	var legacy_state := CharacterState.new()
	_assert_equal((service.call("materialize_starting_loadout", legacy_state, [{"id": "lasgun_good", "quantity": 1, "scope": "per_character"}], repository, "2026-08-09T12:05:00Z") as Dictionary).get("error"), OK, "legacy Good-lasgun grant remains loadable")
	_assert_equal(legacy_state.owned_items[0].get("definition_id"), "lasgun_good", "legacy grant retains its stable alias ID")
	_assert_equal(legacy_state.owned_items[0].get("craftsmanship"), "Good", "legacy alias supplies Good default craftsmanship")


func _test_individual_weapon_craftsmanship() -> void:
	var repository := EquipmentDataRepository.new()
	_assert_equal(repository.load_data(), OK, "equipment catalogue loads for individual craftsmanship")
	var service: RefCounted = InventoryService.new()
	var state := CharacterState.new()
	var lasgun_add: Dictionary = service.call("add_item", state, repository, "m36_lasgun", 1, "Common", "acquisition", "carried", "character", "", "Issued lasgun", "2026-08-09T12:00:00Z")
	var carbine_add: Dictionary = service.call("add_item", state, repository, "lascarbine", 1, "Common", "acquisition", "carried", "character", "", "Issued carbine", "2026-08-09T12:01:00Z")
	_assert_equal(lasgun_add.get("error"), OK, "M36 lasgun is added")
	_assert_equal(carbine_add.get("error"), OK, "las carbine is added")
	var lasgun_id := str((lasgun_add.get("instance_ids", []) as Array)[0])
	var carbine_id := str((carbine_add.get("instance_ids", []) as Array)[0])
	_assert_equal((service.call("update_item", state, repository, lasgun_id, 1, "Good", "carried", "", "Good craftsmanship", "2026-08-09T12:02:00Z") as Dictionary).get("error"), OK, "M36 lasgun becomes Good")
	_assert_equal((service.call("update_item", state, repository, carbine_id, 1, "Good", "carried", "", "Good craftsmanship", "2026-08-09T12:03:00Z") as Dictionary).get("error"), OK, "las carbine becomes Good")
	_assert_equal(_item_field(state.owned_items, "m36_lasgun", "craftsmanship"), "Good", "M36 lasgun stores Good craftsmanship")
	_assert_equal(_item_field(state.owned_items, "lascarbine", "craftsmanship"), "Good", "las carbine stores Good craftsmanship")
	_assert_equal(_item_field(state.owned_items, "m36_lasgun", "definition_id"), "m36_lasgun", "M36 definition remains unchanged")
	_assert_equal(_item_field(state.owned_items, "lascarbine", "definition_id"), "lascarbine", "carbine definition remains unchanged")
	var grenade_add: Dictionary = service.call("add_item", state, repository, "frag_grenade", 1, "Good", "acquisition", "carried", "character", "", "Invalid quality", "2026-08-09T12:04:00Z")
	_assert_equal(grenade_add.get("error"), ERR_INVALID_PARAMETER, "grenades cannot receive non-Common craftsmanship")


func _test_mixed_issue_origins_materialize_separately() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var state := CharacterState.new()
	var service: RefCounted = InventoryService.new()
	var result: Dictionary = service.call("materialize_starting_loadout", state, [{
		"id": "frag_grenade", "quantity": 6, "scope": "per_character",
		"origins": ["standard_issue", "speciality_issue"],
		"origin_quantities": { "standard_issue": 2, "speciality_issue": 4 }
	}], repository, "2026-08-09T12:00:00Z")
	_assert_equal(result.get("error"), OK, "mixed-origin starting grant materializes")
	_assert_equal(state.starting_loadout.size(), 2, "mixed issue sources remain separate reconciliation grants")
	_assert_equal(state.owned_items.size(), 2, "mixed issue sources remain separate owned stacks")
	_assert_equal(_quantity_for_origin(state.owned_items, "standard_issue"), 2, "standard-issue quantity remains traceable")
	_assert_equal(_quantity_for_origin(state.owned_items, "speciality_issue"), 4, "Speciality-issue quantity remains traceable")


func _test_stackable_quantity_splits_safely() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var state := CharacterState.new()
	var service: RefCounted = InventoryService.new()
	if not _require_method(service, "split_stack"):
		return
	service.call("materialize_starting_loadout", state, [{ "id": "charge_pack", "quantity": 4, "scope": "per_character" }], repository, "2026-08-09T12:00:00Z")
	var original_id := str(state.owned_items[0].get("instance_id", ""))
	var split_result: Dictionary = service.call("split_stack", state, repository, original_id, 1, "Separated reserve pack", "2026-08-09T12:15:00Z")
	_assert_equal(split_result.get("error"), OK, "stackable equipment can split")
	_assert_equal(state.owned_items.size(), 2, "split creates a second durable stack")
	_assert_equal(int(state.owned_items[0].get("quantity", 0)), 3, "original stack retains the remainder")
	_assert_equal(int(state.owned_items[1].get("quantity", 0)), 1, "new stack receives the split quantity")
	_assert_true(str(state.owned_items[1].get("instance_id", "")) != original_id, "split stack receives a new durable ID")
	_assert_equal((state.starting_loadout[0].get("issued_instance_ids", []) as Array).size(), 2, "starting reconciliation follows both split stacks")
	_assert_equal((service.call("finalize_loadout", state, repository, [{ "id": "charge_pack", "quantity": 4, "scope": "per_character" }]) as Dictionary).get("error"), OK, "split starting stack remains finalizable")


func _test_comrade_transfer_preserves_history() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var state := CharacterState.new()
	var service: RefCounted = InventoryService.new()
	if not _require_method(service, "materialize_starting_loadout") or not _require_method(service, "set_comrade") or not _require_method(service, "transfer_item"):
		return
	service.call("materialize_starting_loadout", state, [{ "id": "laspistol", "quantity": 1, "scope": "per_character" }], repository, "2026-08-09T12:00:00Z")
	var comrade_result: Dictionary = service.call("set_comrade", state, "Trooper Hale")
	_assert_equal(comrade_result.get("error"), OK, "Comrade identity can be created")
	var item_id := str(state.owned_items[0].get("instance_id"))
	var transfer: Dictionary = service.call("transfer_item", state, item_id, "comrade", str(state.comrade.get("id")), "Assigned to Comrade", "2026-08-09T14:00:00Z")
	_assert_equal(transfer.get("error"), OK, "item transfers to the Comrade")
	_assert_equal(_nested(state.owned_items[0], ["custodian", "type"]), "comrade", "current custodian changes")
	_assert_equal(state.inventory_events.size(), 2, "transfer appends history instead of replacing issue")
	_assert_equal(state.inventory_events[1].get("type"), "transfer", "history names the transfer")


func _test_duplicate_regenerates_comrade_links() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var state := CharacterState.new()
	var service: RefCounted = InventoryService.new()
	service.call("materialize_starting_loadout", state, [{ "id": "knife", "quantity": 1, "scope": "per_character" }], repository, "2026-08-09T12:00:00Z")
	service.call("set_comrade", state, "Trooper Hale")
	service.call("transfer_item", state, str(state.owned_items[0].get("instance_id")), "comrade", str(state.comrade.get("id")), "Assigned", "2026-08-09T13:00:00Z")
	var previous_comrade_id := str(state.comrade.get("id"))
	state.duplicate_identity()
	_assert_true(str(state.comrade.get("id")) != previous_comrade_id, "Duplicate gives the Comrade a new durable ID")
	_assert_equal(_nested(state.owned_items[0], ["custodian", "id"]), state.comrade.get("id"), "duplicated Comrade-owned item points to the new Comrade ID")
	_assert_equal(str((state.starting_loadout[0].get("issued_instance_ids", []) as Array)[0]), state.owned_items[0].get("instance_id"), "duplicated starting grant points to the new owned-item ID")
	_assert_true(bool(service.call("starting_loadout_matches", state, [{ "id": "knife", "quantity": 1, "scope": "per_character" }])), "duplicated starting grant still matches the calculated package")
	_assert_equal((service.call("finalize_loadout", state, repository, [{ "id": "knife", "quantity": 1, "scope": "per_character" }]) as Dictionary).get("error"), OK, "duplicated present loadout can be finalized again")
	_assert_equal(CharacterState.new().from_dict(state.to_dict()), OK, "duplicated inventory remains valid serialized state")


func _test_finalization_requires_materialized_grants() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var service: RefCounted = InventoryService.new()
	if not _require_method(service, "finalize_loadout") or not _require_method(service, "materialize_starting_loadout"):
		return
	var empty_state := CharacterState.new()
	var empty_result: Dictionary = service.call("finalize_loadout", empty_state, repository, [])
	_assert_equal(empty_result.get("error"), ERR_INVALID_DATA, "unprepared loadout cannot finalize")
	var state := CharacterState.new()
	service.call("materialize_starting_loadout", state, [{ "id": "knife", "quantity": 1, "scope": "per_character" }], repository, "2026-08-09T12:00:00Z")
	var finalize_result: Dictionary = service.call("finalize_loadout", state, repository, [{ "id": "knife", "quantity": 1, "scope": "per_character" }])
	_assert_equal(finalize_result.get("error"), OK, "materialized valid loadout finalizes")
	_assert_equal(state.loadout_state, CharacterState.LOADOUT_FINALIZED, "finalization is explicit")


func _test_finalization_requires_explicit_reconciliation() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var service: RefCounted = InventoryService.new()
	var state := CharacterState.new()
	service.call("materialize_starting_loadout", state, [{ "id": "knife", "quantity": 1, "scope": "per_character" }], repository, "2026-08-09T12:00:00Z")
	var issued_id := str(state.owned_items[0].get("instance_id", ""))
	service.call("remove_item", state, issued_id, "Missing during kit inspection", "2026-08-09T12:30:00Z")
	_assert_equal(state.starting_loadout[0].get("reconciliation"), "unresolved", "removing issued gear reopens its reconciliation")
	_assert_equal((service.call("finalize_loadout", state, repository, [{ "id": "knife", "quantity": 1, "scope": "per_character" }]) as Dictionary).get("error"), ERR_INVALID_DATA, "unresolved starting grant blocks finalization")
	_assert_equal((service.call("reconcile_starting_grant", state, str(state.starting_loadout[0].get("grant_id", "")), "loss", "Confirmed lost before deployment", "2026-08-09T12:35:00Z") as Dictionary).get("error"), OK, "starting loss can be explicitly reconciled")
	_assert_equal((service.call("finalize_loadout", state, repository, [{ "id": "knife", "quantity": 1, "scope": "per_character" }]) as Dictionary).get("error"), OK, "explicitly reconciled grant can finalize")


func _test_creation_grant_changes_require_rebuild() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var service: RefCounted = InventoryService.new()
	for method_name in ["rebuild_starting_loadout", "starting_loadout_matches"]:
		if not _require_method(service, method_name):
			return
	var original_grants := [{ "id": "knife", "quantity": 1, "scope": "per_character" }]
	var changed_grants := [{ "id": "medikit", "quantity": 1, "scope": "per_character" }]
	var state := CharacterState.new()
	service.call("materialize_starting_loadout", state, original_grants, repository, "2026-08-09T12:00:00Z")
	_assert_equal((service.call("finalize_loadout", state, repository, original_grants) as Dictionary).get("error"), OK, "original calculated grants finalize")
	state.loadout_state = CharacterState.LOADOUT_DRAFT
	_assert_true(not bool(service.call("starting_loadout_matches", state, changed_grants)), "changed creation grants invalidate the old materialization")
	_assert_equal((service.call("finalize_loadout", state, repository, changed_grants) as Dictionary).get("error"), ERR_INVALID_DATA, "old starting package cannot finalize against changed creation inputs")
	_assert_equal((service.call("rebuild_starting_loadout", state, changed_grants, repository, "2026-08-09T13:00:00Z") as Dictionary).get("error"), OK, "changed starting package can be rebuilt explicitly")
	_assert_equal(_item_quantity(state.owned_items, "knife"), 0, "obsolete issued item leaves current inventory")
	_assert_equal(_item_quantity(state.owned_items, "medikit"), 1, "new calculated grant is materialized")
	_assert_equal((service.call("finalize_loadout", state, repository, changed_grants) as Dictionary).get("error"), OK, "rebuilt current grants finalize")


func _test_rebuild_preserves_later_acquisitions() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var service: RefCounted = InventoryService.new()
	var state := CharacterState.new()
	var original_grants := [{ "id": "charge_pack", "quantity": 4, "scope": "per_character" }]
	service.call("materialize_starting_loadout", state, original_grants, repository, "2026-08-09T12:00:00Z")
	var starting_id := str(state.owned_items[0].get("instance_id", ""))
	var origin_edit: Dictionary = service.call("update_item", state, repository, starting_id, 4, "Common", "carried", "", "Incorrect provenance edit", "2026-08-09T12:10:00Z", "later_issue")
	_assert_equal(origin_edit.get("error"), ERR_INVALID_PARAMETER, "starting-grant provenance cannot be rewritten as later issue")
	var quantity_edit: Dictionary = service.call("update_item", state, repository, starting_id, 6, "Common", "carried", "", "Incorrect issued quantity edit", "2026-08-09T12:11:00Z")
	_assert_equal(quantity_edit.get("error"), ERR_INVALID_PARAMETER, "starting-grant quantity cannot absorb later equipment")
	var add_result: Dictionary = service.call("add_item", state, repository, "charge_pack", 2, "Common", "standard_issue", "carried", "character", "", "Later matching issue", "2026-08-09T12:20:00Z")
	_assert_equal(add_result.get("error"), OK, "later matching stack can be added")
	_assert_equal(state.owned_items.size(), 2, "later equipment never merges into a starting-grant row")
	var later_id := str((add_result.get("instance_ids", []) as Array)[0])
	var changed_grants := [{ "id": "medikit", "quantity": 1, "scope": "per_character" }]
	_assert_equal((service.call("rebuild_starting_loadout", state, changed_grants, repository, "2026-08-09T13:00:00Z") as Dictionary).get("error"), OK, "starting issue rebuild succeeds")
	_assert_true(_has_instance(state.owned_items, later_id), "later equipment survives a starting-loadout rebuild")
	_assert_equal(_item_quantity(state.owned_items, "charge_pack"), 2, "only obsolete starting quantity is removed")


func _test_starting_provenance_changes_require_rebuild() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var service: RefCounted = InventoryService.new()
	var state := CharacterState.new()
	var standard := [{ "id": "frag_grenade", "quantity": 2, "scope": "per_character", "origin_quantities": { "standard_issue": 2 } }]
	var speciality := [{ "id": "frag_grenade", "quantity": 2, "scope": "per_character", "origin_quantities": { "speciality_issue": 2 } }]
	service.call("materialize_starting_loadout", state, standard, repository, "2026-08-09T12:00:00Z")
	_assert_true(not bool(service.call("starting_loadout_matches", state, speciality)), "equal totals with different issue provenance do not match")
	_assert_equal((service.call("finalize_loadout", state, repository, speciality) as Dictionary).get("error"), ERR_INVALID_DATA, "stale issue provenance blocks finalization")


func _test_weapon_quantity_must_remain_one() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var service: RefCounted = InventoryService.new()
	var state := CharacterState.new()
	service.call("materialize_starting_loadout", state, [{ "id": "laspistol", "quantity": 1, "scope": "per_character" }], repository, "2026-08-09T12:00:00Z")
	state.owned_items[0]["quantity"] = 2
	var result: Dictionary = service.call("finalize_loadout", state, repository, [{ "id": "laspistol", "quantity": 1, "scope": "per_character" }])
	_assert_equal(result.get("error"), ERR_INVALID_DATA, "weapon stacks cannot finalize")
	var edit_result: Dictionary = service.call("update_item", state, repository, str(state.owned_items[0].get("instance_id", "")), 2, "Common", "carried", "", "Stacked accidentally", "2026-08-09T12:30:00Z")
	_assert_equal(edit_result.get("error"), ERR_INVALID_PARAMETER, "weapon quantity cannot be changed above one")


func _test_no_op_edits_do_not_append_history() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var service: RefCounted = InventoryService.new()
	var state := CharacterState.new()
	service.call("materialize_starting_loadout", state, [{ "id": "knife", "quantity": 1, "scope": "per_character" }], repository, "2026-08-09T12:00:00Z")
	var item := state.owned_items[0]
	var event_count := state.inventory_events.size()
	var update: Dictionary = service.call("update_item", state, repository, str(item.get("instance_id", "")), 1, str(item.get("craftsmanship", "")), str(item.get("location", "")), str(item.get("note", "")), "Apply unchanged form", "2026-08-09T12:10:00Z", str(item.get("origin", "")))
	_assert_equal(update.get("error"), OK, "unchanged item form is accepted")
	_assert_equal(state.inventory_events.size(), event_count, "unchanged item form adds no correction event")
	var transfer: Dictionary = service.call("transfer_item", state, str(item.get("instance_id", "")), "character", "", "Apply unchanged custody", "2026-08-09T12:11:00Z")
	_assert_equal(transfer.get("error"), OK, "unchanged custody is accepted")
	_assert_equal(state.inventory_events.size(), event_count, "unchanged custody adds no transfer event")
	var grant := state.starting_loadout[0]
	var reconcile: Dictionary = service.call("reconcile_starting_grant", state, str(grant.get("grant_id", "")), "present", "", "2026-08-09T12:12:00Z")
	_assert_equal(reconcile.get("error"), OK, "unchanged starting reconciliation is accepted")
	_assert_equal(state.inventory_events.size(), event_count, "unchanged starting reconciliation adds no correction event")


func _test_post_completion_inventory_maintenance_keeps_lifecycle() -> void:
	var repository := EquipmentDataRepository.new()
	repository.load_data()
	var service: RefCounted = InventoryService.new()
	for method_name in ["add_item", "update_item", "remove_item"]:
		if not _require_method(service, method_name):
			return
	var state := CharacterState.new()
	service.call("materialize_starting_loadout", state, [{ "id": "knife", "quantity": 1, "scope": "per_character" }], repository, "2026-08-09T12:00:00Z")
	service.call("finalize_loadout", state, repository, [{ "id": "knife", "quantity": 1, "scope": "per_character" }])
	state.mark_creation_complete()
	var add_result: Dictionary = service.call("add_item", state, repository, "charge_pack", 2, "Common", "later_issue", "carried", "character", "", "Resupply", "2026-08-09T15:00:00Z")
	_assert_equal(add_result.get("error"), OK, "later equipment can be added")
	_assert_equal(state.inventory_events[-1].get("type"), "issue", "later issue is distinguished from an acquisition")
	var charge_id := str((add_result.get("instance_ids", []) as Array)[0])
	var update_result: Dictionary = service.call("update_item", state, repository, charge_id, 3, "Good", "stored", "Reserve supply", "Moved to locker", "2026-08-09T16:00:00Z", "exchange")
	_assert_equal(update_result.get("error"), OK, "owned item fields can be updated")
	_assert_equal(_item_quantity(state.owned_items, "charge_pack"), 3, "quantity update is authoritative")
	_assert_equal(_item_field(state.owned_items, "charge_pack", "craftsmanship"), "Good", "craftsmanship remains editable per owned instance")
	_assert_equal(_item_field(state.owned_items, "charge_pack", "origin"), "exchange", "origin remains editable per owned instance")
	var remove_result: Dictionary = service.call("remove_item", state, charge_id, "Expended between missions", "2026-08-09T17:00:00Z")
	_assert_equal(remove_result.get("error"), OK, "owned item can be removed with history")
	_assert_equal(_item_quantity(state.owned_items, "charge_pack"), 0, "removed item leaves current inventory")
	_assert_equal(state.inventory_events[-1].get("type"), "loss", "removal appends a loss event")
	_assert_equal(state.workflow_state, CharacterState.WORKFLOW_COMPLETE, "post-completion equipment changes do not reopen creation")
	_assert_equal(state.loadout_state, CharacterState.LOADOUT_FINALIZED, "maintenance preserves loadout finalization")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		printerr("FAILED: %s" % message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAILED: %s (expected %s, got %s)" % [message, expected, actual])


func _require_method(service: RefCounted, method_name: String) -> bool:
	var available := service.has_method(method_name)
	_assert_true(available, "inventory service implements %s" % method_name)
	return available


func _item_quantity(items: Array[Dictionary], definition_id: String) -> int:
	for item: Dictionary in items:
		if str(item.get("definition_id", "")) == definition_id:
			return int(item.get("quantity", 0))
	return 0


func _item_custodian(items: Array[Dictionary], definition_id: String) -> String:
	for item: Dictionary in items:
		if str(item.get("definition_id", "")) == definition_id:
			return str((item.get("custodian", {}) as Dictionary).get("type", ""))
	return ""


func _item_field(items: Array[Dictionary], definition_id: String, field_name: String) -> Variant:
	for item: Dictionary in items:
		if str(item.get("definition_id", "")) == definition_id:
			return item.get(field_name)
	return null


func _item_ids(items: Array[Dictionary]) -> Array[String]:
	var output: Array[String] = []
	for item: Dictionary in items:
		output.append(str(item.get("instance_id", "")))
	return output


func _quantity_for_origin(items: Array[Dictionary], origin: String) -> int:
	for item: Dictionary in items:
		if str(item.get("origin", "")) == origin:
			return int(item.get("quantity", 0))
	return 0


func _has_instance(items: Array[Dictionary], instance_id: String) -> bool:
	for item: Dictionary in items:
		if str(item.get("instance_id", "")) == instance_id:
			return true
	return false


func _nested(value: Variant, path: Array) -> Variant:
	var current: Variant = value
	for key: Variant in path:
		if current is Dictionary:
			current = (current as Dictionary).get(key)
		else:
			return null
	return current
