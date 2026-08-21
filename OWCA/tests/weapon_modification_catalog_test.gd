extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/weapon_modification_catalog_test.gd

const FIXTURE_PATH := "user://invalid_weapon_modification_catalog.json"

var _failures := 0


func _init() -> void:
	var repository := EquipmentDataRepository.new()
	var load_error := repository.load_data()
	_assert_equal(load_error, OK, "v0.8 equipment catalogue loads: %s" % repository.last_error)
	if load_error != OK:
		_finish()
		return
	_assert_equal(repository.get_canonical_item("lasgun_good").get("id"), "m36_lasgun", "legacy Good lasgun resolves to its base")
	_assert_true(not _contains_id(repository.get_selectable_items(), "lasgun_good"), "legacy variants are hidden from normal selection")
	_assert_true(_contains_id(repository.get_selectable_items(), "lascarbine"), "base las carbine remains selectable")
	_assert_equal(repository.get_weapon_upgrades().size(), 5, "exactly five Core upgrades are supported")
	for tier: String in ["Poor", "Common", "Good", "Best"]:
		_assert_true(repository.get_craftsmanship_effects(tier, "ranged_weapon") is Array, "%s ranged rules load" % tier)
		_assert_true(repository.get_craftsmanship_effects(tier, "melee_weapon") is Array, "%s melee rules load" % tier)

	var source_catalog := repository.data.duplicate(true)

	var alias_chain := source_catalog.duplicate(true)
	var alias_items := alias_chain.get("items", []) as Array
	var lasgun_alias := _find_item(alias_items, "lasgun_good")
	lasgun_alias["base_definition_id"] = "laspistol_common"
	_assert_rejected(alias_chain, "alias chains are rejected")

	var unknown_operation := source_catalog.duplicate(true)
	var operation_rules := unknown_operation.get("craftsmanship_rules", {}) as Dictionary
	var poor_rules := (operation_rules.get("tiers", {}) as Dictionary).get("Poor", {}) as Dictionary
	var poor_ranged := poor_rules.get("ranged_weapon", []) as Array
	(poor_ranged[0] as Dictionary)["operation"] = "invented_operation"
	_assert_rejected(unknown_operation, "unknown effect operations are rejected")

	var missing_rounding := source_catalog.duplicate(true)
	var compact := _find_item(missing_rounding.get("items", []) as Array, "compact_upgrade")
	var compact_effects := (compact.get("modification", {}) as Dictionary).get("effects", []) as Array
	for effect_value: Variant in compact_effects:
		var effect := effect_value as Dictionary
		if str(effect.get("target", "")) == "profile.range_m":
			effect.erase("rounding")
	_assert_rejected(missing_rounding, "integer multipliers require explicit rounding")

	var unknown_family := source_catalog.duplicate(true)
	var sight := _find_item(unknown_family.get("items", []) as Array, "red_dot_laser_sight")
	var compatibility := (sight.get("modification", {}) as Dictionary).get("compatibility", {}) as Dictionary
	var selectors := compatibility.get("any_of", []) as Array
	(selectors[1] as Dictionary)["families"] = ["unknown_family"]
	_assert_rejected(unknown_family, "unknown compatibility families are rejected")

	var duplicate_id := source_catalog.duplicate(true)
	var duplicate_items := duplicate_id.get("items", []) as Array
	duplicate_items.append(_find_item(duplicate_items, "compact_upgrade").duplicate(true))
	_assert_rejected(duplicate_id, "duplicate upgrade IDs are rejected")

	_finish()


func _finish() -> void:
	if FileAccess.file_exists(FIXTURE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
	if _failures > 0:
		printerr("OWCA weapon modification catalogue tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA weapon modification catalogue tests passed.")
	quit(0)


func _assert_rejected(catalog: Dictionary, label: String) -> void:
	var fixture := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	_assert_true(fixture != null, "%s fixture opens" % label)
	if fixture == null:
		return
	fixture.store_string(JSON.stringify(catalog))
	fixture.close()
	var repository := EquipmentDataRepository.new()
	_assert_equal(repository.load_data(FIXTURE_PATH), ERR_INVALID_DATA, label)


func _find_item(items: Array, item_id: String) -> Dictionary:
	for value: Variant in items:
		var item := value as Dictionary
		if str(item.get("id", "")) == item_id:
			return item
	return {}


func _contains_id(items: Array[Dictionary], item_id: String) -> bool:
	for item: Dictionary in items:
		if str(item.get("id", "")) == item_id:
			return true
	return false


func _assert_true(value: bool, label: String) -> void:
	if not value:
		printerr("FAILED: %s." % label)
		_failures += 1


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		printerr("FAILED: %s. Expected %s, got %s." % [label, expected, actual])
		_failures += 1
