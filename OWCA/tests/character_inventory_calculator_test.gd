extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/character_inventory_calculator_test.gd

var _failures := 0
const RulesRepository = preload("res://OWCA/scripts/inventory_rules_repository.gd")
const InventoryCalculator = preload("res://OWCA/scripts/character_inventory_calculator.gd")


func _init() -> void:
	_assert_true(load("res://OWCA/scripts/inventory_rules_repository.gd") != null, "inventory rules repository is available")
	_assert_true(load("res://OWCA/scripts/character_inventory_calculator.gd") != null, "inventory calculator is available")
	_test_capacity_boundaries()
	_test_capacity_data_rejects_duplicate_rows()
	_test_location_weight_and_partial_totals()
	_test_armour_uses_highest_equipped_ap()
	_test_missing_definitions_remain_visible()

	if _failures > 0:
		printerr("OWCA character inventory calculator tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA character inventory calculator tests passed.")
	quit(0)


func _test_capacity_boundaries() -> void:
	var rules: RefCounted = RulesRepository.new()
	if not _require_method(rules, "load_data") or not _require_method(rules, "get_capacity"):
		return
	_assert_equal(rules.call("load_data"), OK, "inventory rules load")
	_assert_equal((rules.call("get_capacity", 0) as Dictionary).get("carrying_kg"), 0.9, "SB+TB 0 carrying boundary")
	_assert_equal((rules.call("get_capacity", 4) as Dictionary).get("carrying_kg"), 18.0, "SB+TB 4 carrying boundary")
	_assert_equal((rules.call("get_capacity", 12) as Dictionary).get("lifting_kg"), 224.0, "SB+TB 12 lifting boundary")
	_assert_equal((rules.call("get_capacity", 20) as Dictionary).get("carrying_kg"), 2250.0, "SB+TB 20 carrying boundary")


func _test_capacity_data_rejects_duplicate_rows() -> void:
	var malformed := JSON.parse_string(FileAccess.get_file_as_string("res://OWCA/data/inventory_rules.json")) as Dictionary
	var rows := malformed.get("carrying_capacity", []) as Array
	(rows[rows.size() - 1] as Dictionary)["bonus_sum"] = int((rows[0] as Dictionary).get("bonus_sum", 0))
	var fixture_path := "user://invalid_inventory_rules.json"
	var fixture := FileAccess.open(fixture_path, FileAccess.WRITE)
	_assert_true(fixture != null, "invalid inventory-rules fixture can be written")
	if fixture == null:
		return
	fixture.store_string(JSON.stringify(malformed))
	fixture.close()
	var rules: RefCounted = RulesRepository.new()
	_assert_equal(rules.call("load_data", fixture_path), ERR_INVALID_DATA, "duplicate carrying-capacity rows are rejected")


func _test_location_weight_and_partial_totals() -> void:
	var equipment := EquipmentDataRepository.new()
	equipment.load_data()
	var rules: RefCounted = RulesRepository.new()
	rules.call("load_data")
	var calculator: RefCounted = InventoryCalculator.new()
	if not _require_method(calculator, "calculate"):
		return
	var state := CharacterState.new()
	state.owned_items = [
		_item("knife", 2, "carried", "character"),
		_item("guard_flak_armour", 1, "equipped", "character"),
		_item("grav_chute", 1, "stored", "character"),
		_item("charge_pack", 4, "carried", "character"),
		_item("medikit", 1, "carried", "squad")
	]
	var result: Dictionary = calculator.call("calculate", state, { "characteristic_bonuses": { "Strength": 3, "Toughness": 3 } }, equipment, rules)
	_assert_equal(_nested(result, ["encumbrance", "known_weight_kg"]), 13.0, "equipped and carried character gear contributes known weight")
	_assert_equal(_nested(result, ["encumbrance", "carrying_limit_kg"]), 36.0, "SB+TB selects the carrying table row")
	_assert_equal(_nested(result, ["encumbrance", "status"]), "partial", "unweighted carried ammunition prevents a certainty claim")
	_assert_equal((result.get("unknown_weight_items", []) as Array).size(), 1, "unknown-weight carried entries are reported")


func _test_armour_uses_highest_equipped_ap() -> void:
	var equipment := EquipmentDataRepository.new()
	equipment.load_data()
	var rules: RefCounted = RulesRepository.new()
	rules.call("load_data")
	var calculator: RefCounted = InventoryCalculator.new()
	var state := CharacterState.new()
	state.owned_items = [
		_item("flak_helmet", 1, "equipped", "character"),
		_item("guard_flak_armour", 1, "equipped", "character"),
		_item("storm_trooper_carapace", 1, "stored", "character")
	]
	var result: Dictionary = calculator.call("calculate", state, { "characteristic_bonuses": { "Strength": 4, "Toughness": 4 } }, equipment, rules)
	_assert_equal(_nested(result, ["armour_by_location", "Head", "ap"]), 4, "overlapping head armour uses highest equipped AP")
	_assert_equal(_nested(result, ["armour_by_location", "Body", "ap"]), 4, "equipped full armour covers Body")
	_assert_equal(_nested(result, ["armour_by_location", "Arms", "ap"]), 4, "stored carapace does not affect protection")


func _test_missing_definitions_remain_visible() -> void:
	var equipment := EquipmentDataRepository.new()
	equipment.load_data()
	var rules: RefCounted = RulesRepository.new()
	rules.call("load_data")
	var calculator: RefCounted = InventoryCalculator.new()
	var state := CharacterState.new()
	state.owned_items = [_item("missing_catalogue_item", 1, "carried", "character")]
	var result: Dictionary = calculator.call("calculate", state, { "characteristic_bonuses": { "Strength": 3, "Toughness": 3 } }, equipment, rules)
	_assert_equal((result.get("unresolved_items", []) as Array).size(), 1, "missing definition remains unresolved")
	_assert_true(not bool(result.get("valid", true)), "missing definition blocks loadout validity")
	_assert_true(str(_nested(result, ["items", 0, "name"])).contains("missing_catalogue_item"), "missing definition remains visible by stable ID")
	var stored_state := CharacterState.new()
	stored_state.owned_items = [_item("missing_stored_item", 1, "stored", "character")]
	var stored_result: Dictionary = calculator.call("calculate", stored_state, { "characteristic_bonuses": { "Strength": 3, "Toughness": 3 } }, equipment, rules)
	_assert_true(bool(_nested(stored_result, ["encumbrance", "complete"])), "an unresolved stored item does not make carried weight partial")
	_assert_equal(_nested(stored_result, ["encumbrance", "status"]), "within_limit", "stored unresolved gear does not affect the carried-weight limit")
	_assert_true(not bool(stored_result.get("valid", true)), "stored unresolved gear still blocks loadout finalization")


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
	_assert_true(available, "%s implements %s" % [service.get_class(), method_name])
	return available


func _item(definition_id: String, quantity: int, location: String, custodian_type: String) -> Dictionary:
	return {
		"instance_id": DocumentIdentity.generate(),
		"definition_id": definition_id,
		"quantity": quantity,
		"craftsmanship": "Common",
		"origin": "acquisition",
		"location": location,
		"custodian": { "type": custodian_type, "id": "" },
		"note": ""
	}


func _nested(value: Variant, path: Array) -> Variant:
	var current: Variant = value
	for key: Variant in path:
		if current is Dictionary:
			current = (current as Dictionary).get(key)
		elif current is Array and key is int and key >= 0 and key < (current as Array).size():
			current = (current as Array)[key]
		else:
			return null
	return current
