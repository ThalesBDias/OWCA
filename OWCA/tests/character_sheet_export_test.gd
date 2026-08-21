extends SceneTree

## Run with:
## godot --rendering-method gl_compatibility --path . --script res://OWCA/tests/character_sheet_export_test.gd
## This visual test needs a real renderer; Godot's Windows headless driver is a dummy.

const EXAMPLE_CHARACTER := "res://OWCA/examples/varanox_weapon_specialist.owchar.json"


func _init() -> void:
	root.mode = Window.MODE_MINIMIZED
	_run.call_deferred()


func _run() -> void:
	var regiment_repository := RegimentDataRepository.new()
	_assert_equal(regiment_repository.load_data(), OK, "regiment catalog loads")
	var character_repository := CharacterDataRepository.new()
	_assert_equal(character_repository.load_data(), OK, "character catalog loads")

	var state := CharacterState.new()
	var load_result := CharacterPersistence.new().load_character(EXAMPLE_CHARACTER, state)
	_assert_equal(int(load_result.get("error", ERR_INVALID_DATA)), OK, "example character loads")
	state.character_name = "Varanox Weapon Specialist"
	state.player_name = "Example Player"
	for advance_id in ["characteristic:ballistic_skill", "characteristic:agility", "talent:deadeye_shot", "skill:athletics"]:
		state.purchase_advance(advance_id)
	var calculation := CharacterCalculator.new().calculate(state, regiment_repository, character_repository)
	_assert_true(bool(calculation.get("valid", false)), "example character is export-ready")
	var example_weapon := _find_equipment(calculation.get("equipment", []) as Array, "lasgun_good")
	_assert_true(not example_weapon.is_empty(), "example keeps the legacy Good M36 definition")
	_assert_true("red_dot_laser_sight" in ((example_weapon.get("modification_ids", []) as Array)), "example contains an installed Red-dot sight")
	_assert_equal((example_weapon.get("weapon", {}) as Dictionary).get("final_weight_kg", -1.0), 4.5, "example final weapon weight uses the installed sight")
	var expected_pages := PrintableCharacterSheet.new().get_required_page_count(calculation, str(state.comrade.get("name", "")))

	var output_path := OS.get_environment("OWCA_PDF_OUTPUT")
	if output_path.is_empty():
		output_path = ProjectSettings.globalize_path("user://owca_character_sheet_test.pdf")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	_assert_true(directory_error in [OK, ERR_ALREADY_EXISTS], "output directory is available")

	var export_result := await CharacterSheetExporter.new().export_pdf_and_png(output_path, state, calculation, root)
	_assert_equal(int(export_result.get("error", ERR_CANT_CREATE)), OK, "PDF and PNG export succeeds")
	_assert_true(FileAccess.file_exists(output_path), "PDF file exists")
	var pdf := FileAccess.get_file_as_bytes(output_path)
	_assert_true(pdf.size() > 100000, "PDF contains rendered page data")
	_assert_equal(pdf.slice(0, 5).get_string_from_ascii(), "%PDF-", "PDF signature is valid")
	_assert_true(pdf.get_string_from_ascii().contains("/Count %d" % expected_pages), "PDF declares the calculated page count")

	for page in range(1, expected_pages + 1):
		var png_path := "%s_page_%d.png" % [output_path.trim_suffix(".pdf"), page]
		_assert_true(FileAccess.file_exists(png_path), "PNG page %d exists" % page)
		var image := Image.load_from_file(png_path)
		_assert_equal(image.get_size(), PrintableCharacterSheet.PAGE_SIZE, "PNG page %d is A4 at 300 DPI" % page)

	print("Character-sheet export test passed: %s" % output_path)
	quit(0)


func _find_equipment(items: Array, definition_id: String) -> Dictionary:
	for item_value: Variant in items:
		var item := item_value as Dictionary
		if str(item.get("definition_id", "")) == definition_id:
			return item
	return {}


func _assert_true(value: bool, message: String) -> void:
	if not value:
		push_error("Assertion failed: %s" % message)
		quit(1)
		await process_frame


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		push_error("Assertion failed: %s (expected %s, got %s)" % [message, expected, actual])
		quit(1)
		await process_frame
