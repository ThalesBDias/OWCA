extends Control

## Standalone maintenance workflow for saved `.owchar.json` records.

const LANDING_SCENE := "res://OWCA/ui/LandingPage.tscn"
const InventoryEditorScript = preload("res://OWCA/ui/character_inventory_editor.gd")

var repository := CharacterDataRepository.new()
var regiment_repository := RegimentDataRepository.new()
var persistence := CharacterPersistence.new()
var calculator := CharacterCalculator.new()
var state := CharacterState.new()
var calculation: Dictionary = {}
var current_path: String = ""
var content: VBoxContainer
var status: Label
var editor: VBoxContainer
var load_dialog: FileDialog
var save_dialog: FileDialog
var duplicate_dialog: FileDialog
var recovery_dialog: SaveRecoveryDialog


func _ready() -> void:
	get_window().min_size = Vector2i(960, 650)
	if repository.load_data() != OK or regiment_repository.load_data() != OK:
		return
	_build_interface()
	_render_empty()


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var title := Label.new()
	title.text = "MANAGE CHARACTER LOADOUT"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for pair in [["HOME", _return_home], ["LOAD", _request_load], ["SAVE", _save_current], ["SAVE AS", _request_save_as], ["DUPLICATE", _request_duplicate]]:
		var button := Button.new()
		button.text = str(pair[0])
		button.pressed.connect(pair[1])
		header.add_child(button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(status)
	load_dialog = FileDialog.new()
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.filters = PackedStringArray(["*.owchar.json ; OWCA Character"])
	load_dialog.file_selected.connect(_load_path)
	add_child(load_dialog)
	save_dialog = FileDialog.new()
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.owchar.json ; OWCA Character"])
	save_dialog.file_selected.connect(_save_path)
	add_child(save_dialog)
	duplicate_dialog = FileDialog.new()
	duplicate_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	duplicate_dialog.access = FileDialog.ACCESS_FILESYSTEM
	duplicate_dialog.filters = PackedStringArray(["*.owchar.json ; OWCA Character"])
	duplicate_dialog.file_selected.connect(_duplicate_path)
	add_child(duplicate_dialog)
	recovery_dialog = SaveRecoveryDialog.new()
	recovery_dialog.recovery_requested.connect(_on_recovery_requested)
	recovery_dialog.discard_temporary_requested.connect(_on_discard_temporary_requested)
	add_child(recovery_dialog)


func _render_empty() -> void:
	_clear_content()
	var explanation := Label.new()
	explanation.text = "Load a saved character to maintain owned equipment, custody, carried weight, armour, and audit history."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(explanation)
	var button := Button.new()
	button.text = "LOAD CHARACTER FILE"
	button.custom_minimum_size.y = 48
	button.pressed.connect(_request_load)
	content.add_child(button)


func _render_editor() -> void:
	calculation = calculator.calculate(state, regiment_repository, repository)
	_clear_content()
	var identity := Label.new()
	identity.text = "%s | %s | %s" % [state.character_name, state.workflow_state, state.document_id]
	identity.add_theme_font_size_override("font_size", 18)
	content.add_child(identity)
	editor = InventoryEditorScript.new()
	editor.inventory_changed.connect(_on_inventory_changed)
	content.add_child(editor)
	editor.call("configure", state, calculation, repository)


func _on_inventory_changed(message: String) -> void:
	status.text = message
	_render_editor()


func _request_load() -> void:
	load_dialog.popup_centered_ratio(0.75)


func _request_save_as() -> void:
	save_dialog.current_file = _safe_stem(state.character_name) + ".owchar.json"
	save_dialog.popup_centered_ratio(0.75)


func _request_duplicate() -> void:
	if current_path.is_empty():
		status.text = "Load a character before duplicating it."
		return
	duplicate_dialog.current_file = _safe_stem(state.character_name) + "_copy.owchar.json"
	duplicate_dialog.popup_centered_ratio(0.75)


func _load_path(path: String) -> void:
	var result := persistence.load_character(path, state)
	status.text = str(result.get("message", ""))
	if int(result.get("error", ERR_INVALID_DATA)) == OK:
		current_path = path
		_render_editor()
	_present_recovery_if_needed(path, result.get("recovery", {}) as Dictionary)


func _save_current() -> void:
	if current_path.is_empty():
		_request_save_as()
	else:
		_save_path(current_path)


func _save_path(path: String) -> void:
	var save_path := path if path.to_lower().ends_with(".json") else path + ".owchar.json"
	calculation = calculator.calculate(state, regiment_repository, repository)
	var result := persistence.save_character(save_path, state, calculation, repository)
	status.text = str(result.get("message", ""))
	if int(result.get("error", ERR_INVALID_DATA)) == OK:
		current_path = save_path
	_present_recovery_if_needed(save_path, result.get("recovery", {}) as Dictionary)


func _duplicate_path(path: String) -> void:
	var duplicate_state := CharacterState.new()
	if duplicate_state.from_dict(state.to_dict()) != OK:
		status.text = "Could not duplicate the loaded character."
		return
	duplicate_state.interoperability_extensions = state.interoperability_extensions.duplicate(true)
	duplicate_state.duplicate_identity()
	var duplicate_calculation := calculator.calculate(duplicate_state, regiment_repository, repository)
	var save_path := path if path.to_lower().ends_with(".json") else path + ".owchar.json"
	var result := persistence.save_character(save_path, duplicate_state, duplicate_calculation, repository)
	status.text = "%s New record ID: %s." % [result.get("message", ""), duplicate_state.document_id]
	_present_recovery_if_needed(save_path, result.get("recovery", {}) as Dictionary)


func _present_recovery_if_needed(path: String, recovery: Dictionary) -> void:
	if bool(recovery.get("recovery_available", false)):
		recovery_dialog.present(path, recovery)


func _on_recovery_requested(path: String, recovery_kind: String) -> void:
	var result := persistence.recover_temporary(path) if recovery_kind == "temporary" else persistence.restore_backup(path)
	status.text = str(result.get("message", "Recovery failed."))
	if int(result.get("error", ERR_INVALID_DATA)) == OK:
		_load_path(path)


func _on_discard_temporary_requested(path: String) -> void:
	var result := persistence.discard_temporary(path)
	status.text = str(result.get("message", "Could not discard temporary save."))


func _return_home() -> void:
	get_tree().change_scene_to_file(LANDING_SCENE)


func _clear_content() -> void:
	for child in content.get_children():
		child.queue_free()


func _safe_stem(value: String) -> String:
	var output := value.strip_edges().replace(" ", "_")
	return output if not output.is_empty() else "character"
