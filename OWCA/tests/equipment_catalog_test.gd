extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/equipment_catalog_test.gd

var _failures := 0


func _init() -> void:
	var repository := EquipmentDataRepository.new()
	_assert_equal(repository.load_data(), OK, "equipment catalogue loads")
	_assert_equal(repository.get_content_version(), "0.6.0-core-equipment", "content version")
	_assert_equal(repository.get_items().size(), 115, "supported definition count")
	_assert_equal(_count_category(repository, "ranged_weapon"), 37, "ranged definition count")
	_assert_equal(_count_category(repository, "melee_weapon"), 12, "melee definition count")

	var lasgun := repository.get_item("m36_lasgun")
	_assert_equal(_nested(lasgun, ["profile", "damage"]), "1d10+3 E", "lasgun damage")
	_assert_equal(_nested(lasgun, ["profile", "magazine"]), 60, "lasgun magazine capacity")
	_assert_equal(_nested(lasgun, ["profile", "rate_of_fire"]), "S/3/-", "lasgun rate of fire")
	_assert_equal(lasgun.get("ammunition_id"), "charge_pack", "lasgun ammunition relationship")

	var armour := repository.get_item("guard_flak_armour")
	_assert_equal(_nested(armour, ["armour", "ap"]), 4, "Guard flak AP")
	_assert_equal((_nested(armour, ["armour", "locations"]) as Array).size(), 4, "Guard flak coverage")
	_assert_equal(repository.get_source_label(armour.get("source", {}) as Dictionary), "OW Core p. 195", "printed source label")

	lasgun["name"] = "Mutated"
	_assert_equal(repository.get_item_name("m36_lasgun"), "M36 lasgun", "returned definitions are immutable copies")

	var regiment_repository := RegimentDataRepository.new()
	_assert_equal(regiment_repository.load_data(), OK, "regiment references resolve through shared catalogue")
	var character_repository := CharacterDataRepository.new()
	_assert_equal(character_repository.load_data(), OK, "character references resolve through shared catalogue")
	_assert_equal(character_repository.get_catalog_name("equipment", "chainsword_common"), "Common Craftsmanship chainsword", "character lookup delegates to shared catalogue")

	if _failures > 0:
		printerr("OWCA equipment catalogue tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA equipment catalogue tests passed.")
	quit(0)


func _count_category(repository: EquipmentDataRepository, category: String) -> int:
	var count := 0
	for item: Dictionary in repository.get_items():
		if str(item.get("category", "")) == category:
			count += 1
	return count


func _nested(root_value: Variant, path: Array) -> Variant:
	var current: Variant = root_value
	for key: Variant in path:
		if not current is Dictionary or not (current as Dictionary).has(key):
			return null
		current = (current as Dictionary)[key]
	return current


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		printerr("FAILED: %s. Expected %s, got %s." % [label, expected, actual])
		_failures += 1
