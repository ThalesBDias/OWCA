extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/weapon_modification_calculator_test.gd

const WEIGHTLESS_FIXTURE_PATH := "user://weightless_weapon_catalog.json"

var _failures := 0


func _init() -> void:
	var repository := EquipmentDataRepository.new()
	var load_error := repository.load_data()
	_assert_equal(load_error, OK, "equipment catalogue loads: %s" % repository.last_error)
	if load_error != OK:
		_finish()
		return
	var calculator := WeaponModificationCalculator.new()

	var good_carbine := calculator.calculate(_owned("lascarbine", "Good", []), repository)
	_assert_true(bool(good_carbine.get("valid", false)), "Good las carbine is valid")
	_assert_true("Reliable" in (good_carbine["final_profile"]["qualities"] as Array), "Good las carbine gains Reliable")
	_assert_equal(_quality_count(good_carbine, "Reliable"), 1, "Good does not duplicate Reliable")

	var poor_laslock := calculator.calculate(_owned("laslock", "Poor", []), repository)
	_assert_equal(_quality_count(poor_laslock, "Unreliable"), 1, "Poor does not duplicate Unreliable")
	_assert_true(_has_effect(poor_laslock, "jam_on_failed_hit"), "Poor Unreliable weapon records the stronger jam rule")

	var best_chainsword := calculator.calculate(_owned("chainsword", "Best", []), repository)
	_assert_equal(best_chainsword["final_profile"]["damage"], "1d10+3 R", "Best melee adds one Damage")
	_assert_true(_has_effect(best_chainsword, "weapon_skill_modifier", 10), "Best melee records +10 WS")

	var grenade := calculator.calculate(_owned("frag_grenade", "Good", []), repository)
	_assert_true(not bool(grenade.get("valid", true)), "grenades reject craftsmanship modification calculation")
	_assert_equal(grenade.get("code"), "invalid_weapon_category", "grenade rejection is explicit")

	var compact := calculator.calculate(_owned("m36_lasgun", "Common", ["compact_upgrade"]), repository)
	_assert_true(bool(compact.get("valid", false)), "Compact M36 lasgun is valid")
	_assert_equal(compact.get("final_weight_kg"), 2.0, "Compact halves M36 weight")
	_assert_equal(compact["final_profile"]["range_m"], 50, "Compact halves M36 range")
	_assert_equal(compact["final_profile"]["magazine"], 30, "Compact halves M36 magazine")
	_assert_equal(compact["final_profile"]["damage"], "1d10+2 E", "Compact reduces M36 damage")

	var reversed_order := calculator.calculate(_owned("m36_lasgun", "Common", ["red_dot_laser_sight", "compact_upgrade"]), repository)
	_assert_equal(reversed_order.get("final_weight_kg"), 2.5, "Compact and red-dot use canonical order")
	_assert_equal(_modification_step_ids(reversed_order), ["compact_upgrade", "compact_upgrade", "compact_upgrade", "compact_upgrade", "compact_upgrade", "red_dot_laser_sight", "red_dot_laser_sight"], "operation steps follow order then ID")

	var mono_spear := calculator.calculate(_owned("spear", "Common", ["mono_melee_upgrade"]), repository)
	_assert_equal(mono_spear["final_profile"]["penetration"], 2, "Mono adds two spear penetration")
	_assert_equal(_quality_count(mono_spear, "Primitive"), 0, "Mono removes Primitive quality variants")

	var mono_power_sword := calculator.calculate(_owned("power_sword", "Common", ["mono_melee_upgrade"]), repository)
	_assert_equal(mono_power_sword["final_profile"]["penetration"], 5, "Mono does not alter active power field penetration")
	_assert_true(_has_effect(mono_power_sword, "inactive_power_field"), "Mono power weapon records its conditional note")

	var red_dot_owned := _owned("m36_lasgun", "Common", ["red_dot_laser_sight"])
	var second_sight := calculator.evaluate_install(red_dot_owned, "telescopic_sight", repository)
	_assert_true(not bool(second_sight.get("compatible", true)), "red-dot and telescopic sights cannot coexist")
	_assert_equal(second_sight.get("code"), "exclusive_group_conflict", "sight conflict has a stable code")

	var telescope_pistol := calculator.evaluate_install(_owned("laspistol", "Common", []), "telescopic_sight", repository)
	_assert_true(not bool(telescope_pistol.get("compatible", true)), "telescopic sight rejects pistols")
	var telescope_basic := calculator.evaluate_install(_owned("m36_lasgun", "Common", []), "telescopic_sight", repository)
	_assert_true(bool(telescope_basic.get("compatible", false)), "telescopic sight accepts supported Basic weapons")

	for definition_id: String in ["m36_lasgun", "heavy_stubber"]:
		var tripod := calculator.evaluate_install(_owned(definition_id, "Common", []), "tripod_bipod", repository)
		_assert_true(bool(tripod.get("compatible", false)), "tripod accepts %s" % definition_id)
		_assert_equal(tripod["weapon"].get("final_weight_kg"), float(repository.get_item(definition_id).get("weight_kg", 0.0)) + 2.0, "tripod adds two kg to %s" % definition_id)
	var tripod_pistol := calculator.evaluate_install(_owned("laspistol", "Common", []), "tripod_bipod", repository)
	_assert_true(not bool(tripod_pistol.get("compatible", true)), "tripod rejects pistols")

	var missing_modification := calculator.calculate(_owned("m36_lasgun", "Common", ["missing_upgrade"]), repository)
	_assert_true(not bool(missing_modification.get("valid", true)), "missing modification invalidates calculation")
	_assert_equal(missing_modification.get("code"), "missing_modification", "missing modification has a stable code")
	var duplicate_modification := calculator.calculate(_owned("m36_lasgun", "Common", ["compact_upgrade", "compact_upgrade"]), repository)
	_assert_equal(duplicate_modification.get("code"), "duplicate_modification", "duplicate modification IDs are rejected")

	var immutable_base := repository.get_item("m36_lasgun")
	var immutable_copy := immutable_base.duplicate(true)
	calculator.calculate(_owned("m36_lasgun", "Common", ["compact_upgrade"]), repository)
	_assert_equal(immutable_base, immutable_copy, "calculation does not mutate the source base profile")

	var weightless_catalog := repository.data.duplicate(true)
	var weightless_definition := _find_item(weightless_catalog.get("items", []) as Array, "m36_lasgun")
	weightless_definition.erase("weight_kg")
	var fixture := FileAccess.open(WEIGHTLESS_FIXTURE_PATH, FileAccess.WRITE)
	_assert_true(fixture != null, "weightless fixture opens")
	if fixture != null:
		fixture.store_string(JSON.stringify(weightless_catalog))
		fixture.close()
		var weightless_repository := EquipmentDataRepository.new()
		_assert_equal(weightless_repository.load_data(WEIGHTLESS_FIXTURE_PATH), OK, "weightless valid catalogue loads")
		var weightless := calculator.calculate(_owned("m36_lasgun", "Common", []), weightless_repository)
		_assert_equal(weightless.get("base_weight_kg"), 0.0, "omitted valid weight starts at zero")
		_assert_equal(weightless.get("final_weight_kg"), 0.0, "omitted valid weight remains zero")

	_finish()


func _owned(definition_id: String, craftsmanship: String, modification_ids: Array) -> Dictionary:
	return {
		"instance_id": "test-instance",
		"definition_id": definition_id,
		"quantity": 1,
		"craftsmanship": craftsmanship,
		"modification_ids": modification_ids.duplicate(),
		"origin": {"type": "manual"},
		"location": "carried",
		"custodian": {"type": "character", "id": "character"},
		"note": ""
	}


func _find_item(items: Array, item_id: String) -> Dictionary:
	for value: Variant in items:
		var item := value as Dictionary
		if str(item.get("id", "")) == item_id:
			return item
	return {}


func _quality_count(result: Dictionary, prefix: String) -> int:
	var count := 0
	var profile := result.get("final_profile", {}) as Dictionary
	for quality_value: Variant in profile.get("qualities", []):
		var quality := str(quality_value)
		if quality == prefix or quality.begins_with(prefix + " ("):
			count += 1
	return count


func _has_effect(result: Dictionary, code: String, value: Variant = null) -> bool:
	for effect_value: Variant in result.get("situational_effects", []):
		var effect := effect_value as Dictionary
		if str(effect.get("code", "")) != code:
			continue
		if value == null or effect.get("value") == value:
			return true
	return false


func _modification_step_ids(result: Dictionary) -> Array:
	var ids: Array = []
	for step_value: Variant in result.get("steps", []):
		var step := step_value as Dictionary
		if str(step.get("source_type", "")) == "modification":
			ids.append(str(step.get("source_id", "")))
	return ids


func _finish() -> void:
	if FileAccess.file_exists(WEIGHTLESS_FIXTURE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WEIGHTLESS_FIXTURE_PATH))
	if _failures > 0:
		printerr("OWCA weapon modification calculator tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA weapon modification calculator tests passed.")
	quit(0)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		printerr("FAILED: %s." % label)
		_failures += 1


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		printerr("FAILED: %s. Expected %s, got %s." % [label, expected, actual])
		_failures += 1
