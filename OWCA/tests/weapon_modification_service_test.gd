extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/weapon_modification_service_test.gd

const InventoryService = preload("res://OWCA/scripts/character_inventory_service.gd")

var _failures := 0


func _init() -> void:
	var repository := EquipmentDataRepository.new()
	_assert_equal(repository.load_data(), OK, "equipment catalogue loads")
	var service: RefCounted = InventoryService.new()
	if not _require_method(service, "install_modification") or not _require_method(service, "remove_modification"):
		_finish()
		return
	_test_atomic_commands(service, repository)
	_test_craftsmanship_validates_complete_weapon(service, repository)
	_test_rebuild_preserves_only_unchanged_instances(service, repository)
	_finish()


func _test_atomic_commands(service: RefCounted, repository: EquipmentDataRepository) -> void:
	var state := CharacterState.new()
	var first_add: Dictionary = service.call("add_item", state, repository, "m36_lasgun", 1, "Common", "acquisition", "carried", "character", "", "First", "2026-08-09T12:00:00Z")
	var second_add: Dictionary = service.call("add_item", state, repository, "m36_lasgun", 1, "Common", "acquisition", "carried", "character", "", "Second", "2026-08-09T12:01:00Z")
	var first_id := str((first_add.get("instance_ids", []) as Array)[0])
	var second_id := str((second_add.get("instance_ids", []) as Array)[0])
	var event_count := state.inventory_events.size()

	var compact: Dictionary = service.call("install_modification", state, repository, first_id, "compact_upgrade", "Field conversion", "2026-08-09T12:02:00Z")
	_assert_equal(compact.get("error"), OK, "Compact installs")
	_assert_equal(state.inventory_events.size(), event_count + 1, "Compact appends one event")
	_assert_equal(state.inventory_events[-1].get("type"), "modification", "install uses modification event")
	_assert_equal(_snapshot_modifications(state.inventory_events[-1]), ["compact_upgrade"], "Compact event snapshots complete installed set")

	event_count = state.inventory_events.size()
	var red_dot: Dictionary = service.call("install_modification", state, repository, first_id, "red_dot_laser_sight", "Fit sight", "2026-08-09T12:03:00Z")
	_assert_equal(red_dot.get("error"), OK, "red-dot installs")
	_assert_equal(state.inventory_events.size(), event_count + 1, "red-dot appends one event")
	_assert_equal(_snapshot_modifications(state.inventory_events[-1]), ["compact_upgrade", "red_dot_laser_sight"], "red-dot snapshot contains full installed set")
	_assert_equal(_item(state, second_id).get("modification_ids"), [], "second M36 remains independent")

	event_count = state.inventory_events.size()
	var removed: Dictionary = service.call("remove_modification", state, repository, first_id, "red_dot_laser_sight", "Remove sight", "2026-08-09T12:04:00Z")
	_assert_equal(removed.get("error"), OK, "red-dot removes")
	_assert_equal(state.inventory_events.size(), event_count + 1, "removal appends one event")
	_assert_equal(_snapshot_modifications(state.inventory_events[-1]), ["compact_upgrade"], "removal snapshot retains Compact")

	_assert_atomic_noop(service, state, repository, "install_modification", [first_id, "compact_upgrade", "Duplicate", "2026-08-09T12:05:00Z"], OK, "duplicate install is a safe no-op")
	_assert_equal((service.call("install_modification", state, repository, first_id, "red_dot_laser_sight", "Restore sight", "2026-08-09T12:06:00Z") as Dictionary).get("error"), OK, "red-dot reinstalls for conflict test")
	_assert_atomic_noop(service, state, repository, "install_modification", [first_id, "telescopic_sight", "Second sight", "2026-08-09T12:07:00Z"], ERR_INVALID_DATA, "exclusive sight install is atomic")

	var heavy_add: Dictionary = service.call("add_item", state, repository, "heavy_stubber", 1, "Common", "acquisition", "carried", "character", "", "Heavy", "2026-08-09T12:08:00Z")
	var heavy_id := str((heavy_add.get("instance_ids", []) as Array)[0])
	_assert_atomic_noop(service, state, repository, "install_modification", [heavy_id, "compact_upgrade", "Invalid compact", "2026-08-09T12:09:00Z"], ERR_INVALID_DATA, "Compact on Heavy is atomic")
	var grenade_add: Dictionary = service.call("add_item", state, repository, "frag_grenade", 1, "Common", "acquisition", "carried", "character", "", "Grenade", "2026-08-09T12:10:00Z")
	var grenade_id := str((grenade_add.get("instance_ids", []) as Array)[0])
	_assert_atomic_noop(service, state, repository, "install_modification", [grenade_id, "compact_upgrade", "Invalid grenade", "2026-08-09T12:11:00Z"], ERR_INVALID_DATA, "upgrade on grenade is atomic")
	_assert_atomic_noop(service, state, repository, "install_modification", ["missing-instance", "compact_upgrade", "Unknown item", "2026-08-09T12:12:00Z"], ERR_DOES_NOT_EXIST, "unknown instance is atomic")
	_assert_atomic_noop(service, state, repository, "install_modification", [first_id, "missing_upgrade", "Unknown upgrade", "2026-08-09T12:13:00Z"], ERR_INVALID_DATA, "unknown upgrade is atomic")
	_assert_atomic_noop(service, state, repository, "remove_modification", [first_id, "red_dot_laser_sight", "No timestamp", ""], ERR_INVALID_PARAMETER, "empty timestamp is atomic")


func _test_craftsmanship_validates_complete_weapon(service: RefCounted, repository: EquipmentDataRepository) -> void:
	var state := CharacterState.new()
	var added: Dictionary = service.call("add_item", state, repository, "lascarbine", 1, "Common", "acquisition", "carried", "character", "", "Carbine", "2026-08-09T13:00:00Z")
	var instance_id := str((added.get("instance_ids", []) as Array)[0])
	_assert_equal((service.call("install_modification", state, repository, instance_id, "compact_upgrade", "Compact", "2026-08-09T13:01:00Z") as Dictionary).get("error"), OK, "modified carbine fixture is valid")
	var changed: Dictionary = service.call("update_item", state, repository, instance_id, 1, "Good", "carried", "Good compact carbine", "Improve craftsmanship", "2026-08-09T13:02:00Z")
	_assert_equal(changed.get("error"), OK, "craftsmanship change validates installed set")
	_assert_equal(_item(state, instance_id).get("craftsmanship"), "Good", "craftsmanship commits after full calculation")
	var invalid_item := _item(state, instance_id)
	invalid_item["modification_ids"] = ["missing_upgrade"]
	var before_items := state.owned_items.duplicate(true)
	var before_events := state.inventory_events.duplicate(true)
	var rejected: Dictionary = service.call("update_item", state, repository, instance_id, 1, "Best", "carried", "Should not commit", "Invalid complete set", "2026-08-09T13:03:00Z")
	_assert_equal(rejected.get("error"), ERR_INVALID_DATA, "craftsmanship change rejects an invalid installed set")
	_assert_equal(state.owned_items, before_items, "rejected craftsmanship preserves items")
	_assert_equal(state.inventory_events, before_events, "rejected craftsmanship preserves events")


func _test_rebuild_preserves_only_unchanged_instances(service: RefCounted, repository: EquipmentDataRepository) -> void:
	var state := CharacterState.new()
	var original := [{"id": "m36_lasgun", "quantity": 1, "scope": "per_character", "craftsmanship": "Good"}]
	service.call("materialize_starting_loadout", state, original, repository, "2026-08-09T14:00:00Z")
	var original_id := str(state.owned_items[0].get("instance_id", ""))
	service.call("install_modification", state, repository, original_id, "red_dot_laser_sight", "Issue sight", "2026-08-09T14:01:00Z")
	service.call("update_item", state, repository, original_id, 1, "Good", "carried", "Zeroed for Trooper Hale", "Record zero", "2026-08-09T14:02:00Z")
	var expanded := [
		{"id": "m36_lasgun", "quantity": 1, "scope": "per_character", "craftsmanship": "Good"},
		{"id": "medikit", "quantity": 1, "scope": "per_squad", "craftsmanship": "Common"}
	]
	_assert_equal((service.call("rebuild_starting_loadout", state, expanded, repository, "2026-08-09T14:03:00Z") as Dictionary).get("error"), OK, "expanded starting grants rebuild")
	_assert_true(not _item(state, original_id).is_empty(), "unchanged starting weapon preserves durable ID")
	_assert_equal(_item(state, original_id).get("modification_ids"), ["red_dot_laser_sight"], "unchanged starting weapon preserves modifications")
	_assert_equal(_item(state, original_id).get("note"), "Zeroed for Trooper Hale", "unchanged starting weapon preserves note")

	var replacement := [
		{"id": "lascarbine", "quantity": 1, "scope": "per_character", "craftsmanship": "Good"},
		{"id": "medikit", "quantity": 1, "scope": "per_squad", "craftsmanship": "Common"}
	]
	_assert_equal((service.call("rebuild_starting_loadout", state, replacement, repository, "2026-08-09T14:04:00Z") as Dictionary).get("error"), OK, "replacement starting grants rebuild")
	_assert_true(_item(state, original_id).is_empty(), "obsolete weapon durable instance is removed")
	var carbine := _item_by_definition(state, "lascarbine")
	_assert_true(not carbine.is_empty(), "replacement carbine is materialized")
	_assert_equal(carbine.get("modification_ids"), [], "obsolete modifications do not transfer")
	_assert_equal(carbine.get("note"), "", "obsolete note does not transfer")


func _assert_atomic_noop(service: RefCounted, state: CharacterState, repository: EquipmentDataRepository, method_name: String, arguments: Array, expected_error: int, label: String) -> void:
	var before_items := state.owned_items.duplicate(true)
	var before_events := state.inventory_events.duplicate(true)
	var result: Dictionary = service.callv(method_name, [state, repository] + arguments)
	_assert_equal(result.get("error"), expected_error, "%s result" % label)
	_assert_equal(state.owned_items, before_items, "%s preserves items" % label)
	_assert_equal(state.inventory_events, before_events, "%s preserves events" % label)


func _item(state: CharacterState, instance_id: String) -> Dictionary:
	for item: Dictionary in state.owned_items:
		if str(item.get("instance_id", "")) == instance_id:
			return item
	return {}


func _item_by_definition(state: CharacterState, definition_id: String) -> Dictionary:
	for item: Dictionary in state.owned_items:
		if str(item.get("definition_id", "")) == definition_id:
			return item
	return {}


func _snapshot_modifications(event: Dictionary) -> Array:
	return (((event.get("item_snapshot", {}) as Dictionary).get("modification_ids", []) as Array).duplicate())


func _require_method(service: RefCounted, method_name: String) -> bool:
	var available := service.has_method(method_name)
	_assert_true(available, "%s implements %s" % [service.get_class(), method_name])
	return available


func _finish() -> void:
	if _failures > 0:
		printerr("OWCA weapon modification service tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA weapon modification service tests passed.")
	quit(0)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		printerr("FAILED: %s." % label)
		_failures += 1


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		printerr("FAILED: %s. Expected %s, got %s." % [label, expected, actual])
		_failures += 1
