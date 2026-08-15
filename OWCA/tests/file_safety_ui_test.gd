extends SceneTree

## Protects the player-facing v0.5.1 file-safety workflow from UI regressions.
## Run with: godot --headless --path . --script res://OWCA/tests/file_safety_ui_test.gd

const REGIMENT_PATH := "user://owca_file_safety_regiment.owreg.json"
const REGIMENT_DUPLICATE_PATH := "user://owca_file_safety_regiment_copy.owreg.json"
const CHARACTER_PATH := "user://owca_file_safety_character.owchar.json"
const CHARACTER_DUPLICATE_PATH := "user://owca_file_safety_character_copy.owchar.json"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_test_files()
	await process_frame
	await _test_regiment_controls()
	await _test_character_controls()
	await _test_recovery_prompt()
	_cleanup_test_files()
	print("OWCA file-safety UI tests passed.")
	quit(0)


func _test_regiment_controls() -> void:
	var packed_scene := load("res://OWCA/ui/RegimentCreator.tscn") as PackedScene
	_assert_true(packed_scene != null, "Regiment Creator scene loads")
	var creator := packed_scene.instantiate() as Control
	root.add_child(creator)
	await process_frame

	_assert_true(_find_button(creator, "SAVE AS") != null, "regiment header exposes Save As")
	_assert_true(_find_button(creator, "DUPLICATE") != null, "regiment status panel exposes Duplicate")
	var lifecycle_button := _find_button(creator, "MARK COMPLETE")
	_assert_true(lifecycle_button != null, "regiment status panel exposes lifecycle action")
	_assert_true(lifecycle_button.disabled, "incomplete regiment cannot be marked complete")

	var save_dialog := creator.get("save_dialog") as FileDialog
	var duplicate_dialog := creator.get("duplicate_dialog") as FileDialog
	_assert_true(save_dialog != null and save_dialog.title == "Save Regiment JSON As", "regiment Save As has an explicit destination dialog")
	_assert_true(duplicate_dialog != null and duplicate_dialog.title == "Duplicate Regiment as New Record", "regiment Duplicate explains that it creates a new record")
	_assert_true(creator.get("recovery_dialog") is SaveRecoveryDialog, "regiment controller owns the shared recovery prompt")

	creator.call("_load_example")
	await process_frame
	lifecycle_button = creator.get("lifecycle_button") as Button
	_assert_true(not lifecycle_button.disabled, "valid example regiment can be marked complete")
	creator.call("_toggle_completion")
	await process_frame
	_assert_true(lifecycle_button.text == "REOPEN DRAFT", "completed regiment can be explicitly reopened")

	var state := creator.get("state") as RegimentState
	var original_document_id := state.document_id
	creator.call("_save_to_path", REGIMENT_PATH)
	var saved_envelope := _read_json(REGIMENT_PATH)
	_assert_true(_nested(saved_envelope, ["regiment", "document_id"]) == original_document_id, "regiment Save As preserves record identity")
	_assert_true(_nested(saved_envelope, ["regiment", "workflow_state"]) == RegimentState.WORKFLOW_COMPLETE, "regiment Save As persists completion state")

	creator.call("_duplicate_to_path", REGIMENT_DUPLICATE_PATH)
	var duplicate_envelope := _read_json(REGIMENT_DUPLICATE_PATH)
	_assert_true(_nested(duplicate_envelope, ["regiment", "document_id"]) != original_document_id, "regiment Duplicate creates a new record identity")
	_assert_true(_nested(duplicate_envelope, ["regiment", "workflow_state"]) == RegimentState.WORKFLOW_DRAFT, "regiment Duplicate creates a draft")

	state.set_regiment_name("13th Varanox File Safety Test")
	creator.call("_save_to_path", REGIMENT_PATH)
	_assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(REGIMENT_PATH + AtomicJsonStore.BACKUP_SUFFIX)), "second regiment save rotates a backup")
	var backup_envelope := _read_json(REGIMENT_PATH + AtomicJsonStore.BACKUP_SUFFIX)
	_assert_true(_nested(backup_envelope, ["regiment", "name"]) == "13th Varanox Light Infantry", "regiment backup preserves the previous record")

	creator.queue_free()
	await process_frame


func _test_character_controls() -> void:
	var packed_scene := load("res://OWCA/ui/CharacterCreator.tscn") as PackedScene
	_assert_true(packed_scene != null, "Character Creator scene loads")
	var creator := packed_scene.instantiate() as Control
	root.add_child(creator)
	await process_frame

	_assert_true(_find_button(creator, "SAVE AS") != null, "character header exposes Save As")
	_assert_true(creator.get("recovery_dialog") is SaveRecoveryDialog, "character controller owns the shared recovery prompt")
	var save_dialog := creator.get("character_save_dialog") as FileDialog
	var duplicate_dialog := creator.get("character_duplicate_dialog") as FileDialog
	_assert_true(save_dialog != null and save_dialog.title == "Save Character JSON As", "character Save As has an explicit destination dialog")
	_assert_true(duplicate_dialog != null and duplicate_dialog.title == "Duplicate Character as New Record", "character Duplicate explains that it creates a new record")

	creator.call("_select_stage", "review")
	await process_frame
	var stage_content := creator.get("stage_content") as Node
	_assert_true(_find_button(stage_content, "SAVE CHARACTER JSON AS") != null, "character review exposes Save As")
	_assert_true(_find_button(stage_content, "DUPLICATE AS NEW CHARACTER RECORD") != null, "character review exposes Duplicate")
	var lifecycle_button := _find_button(stage_content, "MARK CHARACTER CREATION COMPLETE")
	_assert_true(lifecycle_button != null and lifecycle_button.disabled, "incomplete character cannot be marked complete")

	creator.call("_load_character_from_path", "res://OWCA/examples/varanox_weapon_specialist.owchar.json")
	await process_frame
	var state := creator.get("state") as CharacterState
	stage_content = creator.get("stage_content") as Node
	_assert_true(_find_button(stage_content, "RETURN TO CHARACTER CREATION") != null, "completed character can be explicitly reopened")
	var original_document_id := state.document_id
	creator.call("_save_character_to_path", CHARACTER_PATH)
	var saved_envelope := _read_json(CHARACTER_PATH)
	_assert_true(_nested(saved_envelope, ["character", "document_id"]) == original_document_id, "character Save As preserves record identity")
	_assert_true(_nested(saved_envelope, ["character", "workflow_state"]) == CharacterState.WORKFLOW_COMPLETE, "character Save As persists completion state")

	creator.call("_duplicate_character_to_path", CHARACTER_DUPLICATE_PATH)
	var duplicate_envelope := _read_json(CHARACTER_DUPLICATE_PATH)
	_assert_true(_nested(duplicate_envelope, ["character", "document_id"]) != original_document_id, "character Duplicate creates a new record identity")
	_assert_true(_nested(duplicate_envelope, ["character", "workflow_state"]) == CharacterState.WORKFLOW_DRAFT, "character Duplicate creates a draft")

	state.set_player_name("File Safety Test")
	creator.call("_save_character_to_path", CHARACTER_PATH)
	_assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(CHARACTER_PATH + AtomicJsonStore.BACKUP_SUFFIX)), "second character save rotates a backup")
	var backup_envelope := _read_json(CHARACTER_PATH + AtomicJsonStore.BACKUP_SUFFIX)
	_assert_true(_nested(backup_envelope, ["character", "player_name"]) == "", "character backup preserves the previous record")

	creator.call("_on_wounds_roll_changed", 1.0)
	_assert_true(state.workflow_state == CharacterState.WORKFLOW_DRAFT, "editing a creation input reopens a completed character")

	creator.queue_free()
	await process_frame


func _test_recovery_prompt() -> void:
	var dialog := SaveRecoveryDialog.new()
	root.add_child(dialog)
	await process_frame

	_assert_true(dialog.title == "OWCA Save Recovery", "recovery prompt has an explicit title")
	_assert_true(dialog.get_ok_button().text == "RECOVER", "recovery action is explicit")
	_assert_true(dialog.get_cancel_button().text == "KEEP CURRENT FILE", "cancel action preserves the current file")
	var discard_button := dialog.get("_discard_button") as Button
	_assert_true(discard_button != null and discard_button.text == "DISCARD TEMPORARY", "temporary discard action is explicit")
	# Do not call present() here. Opening a modal Window currently crashes the
	# Godot 4.7 Windows headless display path; recovery behavior is instead
	# exercised end-to-end by atomic_json_store_test.gd.

	dialog.queue_free()
	await process_frame


func _find_button(node: Node, exact_text: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == exact_text:
			return child as Button
		var nested := _find_button(child as Node, exact_text)
		if nested != null:
			return nested
	return null


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_assert_true(file != null, "open smoke-test JSON: %s" % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_assert_true(parsed is Dictionary, "parse smoke-test JSON: %s" % path)
	return parsed as Dictionary if parsed is Dictionary else {}


func _nested(root_value: Variant, path: Array) -> Variant:
	var current: Variant = root_value
	for key: Variant in path:
		if not current is Dictionary or not (current as Dictionary).has(key):
			return null
		current = (current as Dictionary)[key]
	return current


func _cleanup_test_files() -> void:
	for base_path in [REGIMENT_PATH, REGIMENT_DUPLICATE_PATH, CHARACTER_PATH, CHARACTER_DUPLICATE_PATH]:
		for suffix in ["", AtomicJsonStore.TEMP_SUFFIX, AtomicJsonStore.BACKUP_SUFFIX, AtomicJsonStore.FAILED_SUFFIX, AtomicJsonStore.FAILED_SUFFIX + AtomicJsonStore.TEMP_SUFFIX]:
			var absolute_path := ProjectSettings.globalize_path(base_path + suffix)
			if FileAccess.file_exists(absolute_path):
				DirAccess.remove_absolute(absolute_path)


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAILED: %s" % label)
		quit(1)
