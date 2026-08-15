extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/printable_loadout_test.gd

var _failures := 0


func _init() -> void:
	var sheet := PrintableCharacterSheet.new()
	_assert_true(sheet.has_method("build_loadout_lines"), "printable sheet exposes its loadout projection")
	if sheet.has_method("build_loadout_lines"):
		var lines: Array = sheet.call("build_loadout_lines", {
			"equipment": [{ "quantity": 1, "name": "M36 lasgun", "location": "equipped", "custodian": { "type": "character", "id": "" } }],
			"inventory": {
				"encumbrance": { "known_weight_kg": 15.0, "carrying_limit_kg": 27.0, "status": "partial" },
				"armour_by_location": { "Head": { "ap": 4 }, "Arms": { "ap": 4 }, "Body": { "ap": 4 }, "Legs": { "ap": 4 } }
			}
		}, "Trooper Hale")
		_assert_true(_contains_fragment(lines, "M36 lasgun"), "owned item appears in printable loadout")
		_assert_true(_contains_fragment(lines, "15"), "known carried weight appears in printable loadout")
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
