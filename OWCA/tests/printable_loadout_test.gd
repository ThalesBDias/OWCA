extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/printable_loadout_test.gd

var _failures := 0


func _init() -> void:
	var sheet := PrintableCharacterSheet.new()
	_assert_true(sheet.has_method("build_loadout_lines"), "printable sheet exposes its loadout projection")
	if sheet.has_method("build_loadout_lines"):
		var repository := EquipmentDataRepository.new()
		_assert_true(repository.load_data() == OK, "equipment catalogue loads for printable weapon fixture")
		var owned := {
			"instance_id": "printable-m36",
			"definition_id": "m36_lasgun",
			"quantity": 1,
			"craftsmanship": "Good",
			"modification_ids": ["compact_upgrade", "red_dot_laser_sight"],
			"location": "carried",
			"custodian": {"type": "character", "id": ""}
		}
		var weapon := WeaponModificationCalculator.new().calculate(owned, repository)
		_assert_true(bool(weapon.get("valid", false)), "printable modified weapon fixture calculates")
		var projected_weapon := owned.duplicate(true)
		projected_weapon["name"] = "M36 lasgun"
		projected_weapon["weapon"] = weapon
		projected_weapon["profile"] = (weapon.get("final_profile", {}) as Dictionary).duplicate(true)
		projected_weapon["weight_kg"] = weapon.get("final_weight_kg", 0.0)
		var lines: Array = sheet.call("build_loadout_lines", {
			"equipment": [projected_weapon],
			"inventory": {
				"encumbrance": { "known_weight_kg": 2.5, "carrying_limit_kg": 27.0, "status": "within_limit" },
				"armour_by_location": { "Head": { "ap": 4 }, "Arms": { "ap": 4 }, "Body": { "ap": 4 }, "Legs": { "ap": 4 } }
			}
		}, "Trooper Hale")
		_assert_true(_contains_fragment(lines, "Good M36 lasgun"), "printable weapon name includes its individual craftsmanship")
		_assert_true(_contains_fragment(lines, "Upgrades: Compact, Red-dot laser sight"), "installed upgrades appear in deterministic order")
		_assert_true(_contains_fragment(lines, "Range 50") and _contains_fragment(lines, "Magazine 30") and _contains_fragment(lines, "Damage 1d10+2 E"), "printable final profile uses the shared calculated result")
		_assert_true(_contains_fragment(lines, "Compact:") and _contains_fragment(lines, "Red-dot laser sight:"), "printable output explains profile and situational changes")
		_assert_true(_contains_fragment(lines, "2.50 kg"), "final carried weapon weight appears in printable loadout")
		_assert_true(_contains_fragment(lines, "Head 4"), "armour location AP appears in printable loadout")
		_assert_true(not _contains_fragment(lines, "Character /"), "character-owned rows use compact printable custody labels")
		_assert_true(_contains_fragment(lines, "Comrade: Trooper Hale"), "Comrade identity appears even without assigned gear")
		var crowded_lines: Array[String] = []
		for index in 80:
			crowded_lines.append("%dx Combat sustenance rations (two weeks) [Carried]" % (index + 1))
		crowded_lines.append("FINAL SENTINEL LOADOUT ITEM [Stored]")
		sheet.font = ThemeDB.fallback_font
		var pages := sheet.call("layout_wrapped_pages", crowded_lines, 716.0, 3, 26, 10, 12) as Array
		_assert_true(pages.size() > 1, "large loadouts receive continuation layouts")
		var flattened: Array[String] = []
		for page_value: Variant in pages:
			for column_value: Variant in page_value as Array:
				for line: Variant in column_value as Array:
					flattened.append(str(line))
		_assert_true(_contains_fragment(flattened, "FINAL SENTINEL LOADOUT ITEM"), "continuation layouts preserve the final owned item")
		_assert_true(not _contains_fragment(flattened, "..."), "loadout pagination never substitutes an ellipsis for owned gear")
		var long_weapon_lines: Array[String] = [
			"Upgrades: Compact field-concealment conversion, Red-dot laser sight with extended calibration housing, Telescopic sight with long-range ocular assembly",
			"Compact field-concealment conversion: Range 100 to 50; Magazine 60 to 30; weapon weight 4.00 to 2.00 kg; -20 to Tests made to find the concealed weapon.",
			"FINAL WEAPON EXPLANATION SENTINEL"
		]
		var long_pages := sheet.call("layout_wrapped_pages", long_weapon_lines, 716.0, 3, 26, 10, 12) as Array
		var long_flattened: Array[String] = []
		for page_value: Variant in long_pages:
			for column_value: Variant in page_value as Array:
				for line: Variant in column_value as Array:
					long_flattened.append(str(line))
		_assert_true(_contains_fragment(long_flattened, "FINAL WEAPON EXPLANATION SENTINEL"), "long modification explanations remain present after wrapping")
		_assert_true(not _contains_fragment(long_flattened, "..."), "long modification explanations are never replaced by ellipses")
		var columns := pages[0] as Array
		_assert_true(columns.size() == 3, "loadout layout keeps three balanced columns")
		for column_value: Variant in columns:
			var column := column_value as Array
			_assert_true(column.size() <= 10, "wrapped loadout text stays inside the panel height")
			for line: Variant in column:
				_assert_true(sheet.font.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x <= 692.0, "wrapped loadout lines stay inside their column width")
	sheet.free()
	if _failures > 0:
		printerr("OWCA printable loadout tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA printable loadout tests passed.")
	quit(0)


func _contains_fragment(lines: Array, fragment: String) -> bool:
	for line: Variant in lines:
		if fragment in str(line):
			return true
	return false


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAILED: %s" % label)
