extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/inventory_ui_test.gd

var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 650)
	var landing_scene := load("res://OWCA/ui/LandingPage.tscn") as PackedScene
	var landing := landing_scene.instantiate() as Control
	root.add_child(landing)
	await process_frame
	var manage_button := _find_button(landing, "OPEN LOADOUT MANAGER")
	_assert_true(manage_button != null, "landing page exposes Manage Loadout")
	if manage_button != null:
		_assert_true(manage_button.get_global_rect().end.y <= 650.0, "Manage Loadout remains visible at the 960x650 minimum")
	landing.queue_free()
	await process_frame

	var creator_scene := load("res://OWCA/ui/CharacterCreator.tscn") as PackedScene
	var creator := creator_scene.instantiate() as Control
	root.add_child(creator)
	await process_frame
	creator.call("_select_stage", "loadout")
	await process_frame
	var content := creator.get("stage_content") as Node
	_assert_true(_find_button(content, "PREPARE STARTING EQUIPMENT") != null, "character creation has a loadout preparation action")
	creator.queue_free()
	await process_frame

	var manager_scene := load("res://OWCA/ui/LoadoutManager.tscn") as PackedScene
	_assert_true(manager_scene != null, "standalone Loadout Manager scene loads")
	if manager_scene != null:
		var manager := manager_scene.instantiate() as Control
		root.add_child(manager)
		await process_frame
		_assert_true(_find_button(manager, "LOAD CHARACTER FILE") != null, "standalone manager starts with a load action")
		_assert_true(_find_button(manager, "DUPLICATE") != null, "standalone manager reuses Duplicate identity workflow")
		manager.queue_free()

	var repository := CharacterDataRepository.new()
	repository.load_data()
	var regiment_repository := RegimentDataRepository.new()
	regiment_repository.load_data()
	var prepared_state := CharacterState.new()
	prepared_state.comrade = { "id": DocumentIdentity.generate(), "name": "Trooper Hale of the Thirty-Seventh Varanox Reserve" }
	var starting_grants: Array = [
		{ "id": "laspistol", "quantity": 1, "scope": "per_character" },
		{ "id": "flak_vest", "quantity": 1, "scope": "per_character" },
		{ "id": "charge_pack", "quantity": 4, "scope": "per_character" },
		{ "id": "uniform", "quantity": 1, "scope": "per_character" }
	]
	var inventory_service := CharacterInventoryService.new()
	inventory_service.materialize_starting_loadout(prepared_state, starting_grants, repository.equipment_repository, "2026-08-15T12:00:00Z")
	inventory_service.add_item(prepared_state, repository.equipment_repository, "charge_pack", 4, "Common", "later_issue", "carried", "comrade", str(prepared_state.comrade.get("id", "")), "Reserve ammunition assigned to Comrade", "2026-08-15T12:05:00Z")
	var prepared_calculation := CharacterCalculator.new().calculate(prepared_state, regiment_repository, repository)
	prepared_calculation["starting_equipment"] = starting_grants.duplicate(true)
	var editor_script := load("res://OWCA/ui/character_inventory_editor.gd") as GDScript
	var maintenance_editor := editor_script.new() as VBoxContainer
	root.add_child(maintenance_editor)
	maintenance_editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	maintenance_editor.call("configure", prepared_state, prepared_calculation, repository, &"maintenance")
	maintenance_editor.size.x = 960.0
	await process_frame
	_assert_true(_find_named(maintenance_editor, "CraftsmanshipSelector") != null, "owned rows expose craftsmanship editing")
	_assert_true(_find_named(maintenance_editor, "OriginSelector") != null, "owned rows expose origin editing")
	_assert_true(_find_named(maintenance_editor, "OwnedCustodianFilter") != null, "owned inventory can be filtered by custodian")
	_assert_true(_find_named(maintenance_editor, "StartingGrantReconciliation") != null, "starting grants expose explicit reconciliation controls")
	_assert_true(_find_button(maintenance_editor, "SPLIT ONE") != null, "stackable equipment exposes a safe split action")
	var catalogue_search := maintenance_editor.get("catalogue_search") as LineEdit
	var catalogue_details := maintenance_editor.get("catalogue_details") as RichTextLabel
	_assert_true(catalogue_search != null and catalogue_details != null, "catalogue exposes searchable item details")
	if catalogue_search != null and catalogue_details != null:
		catalogue_search.text = "m36 lasgun"
		catalogue_search.text_changed.emit(catalogue_search.text)
		await process_frame
		_assert_true("Reload Full" in catalogue_details.text, "weapon details include reload time")
		_assert_true("Qualities Reliable" in catalogue_details.text, "weapon details include qualities")
	_assert_interactive_controls_fit_width(maintenance_editor, 960.0)
	maintenance_editor.queue_free()
	await process_frame

	var unprepared_state := CharacterState.new()
	var unprepared_editor := editor_script.new() as VBoxContainer
	root.add_child(unprepared_editor)
	unprepared_editor.call("configure", unprepared_state, prepared_calculation, repository, &"creation")
	await process_frame
	var prepare_starting_equipment := _find_named(unprepared_editor, "PrepareStartingEquipmentButton") as Button
	_assert_true(prepare_starting_equipment != null, "unprepared creation exposes a prepare starting equipment action")
	if prepare_starting_equipment != null:
		_assert_true(prepare_starting_equipment.text == "PREPARE STARTING EQUIPMENT", "creation preparation action uses player-facing text")
	_assert_true(_find_named(unprepared_editor, "StartingGrantReconciliation") == null, "unprepared creation hides reconciliation controls")
	unprepared_editor.queue_free()
	await process_frame

	# This fixture deliberately supplies a valid character result while retaining
	# the calculator's real inventory projection and matching starting grants.
	var finalization_state := CharacterState.new()
	finalization_state.comrade = { "id": DocumentIdentity.generate(), "name": "Trooper Hale of the Thirty-Seventh Varanox Reserve" }
	inventory_service.materialize_starting_loadout(finalization_state, starting_grants, repository.equipment_repository, "2026-08-15T12:10:00Z")
	var finalization_calculation := CharacterCalculator.new().calculate(finalization_state, regiment_repository, repository)
	finalization_calculation["valid"] = true
	finalization_calculation["errors"] = []
	finalization_calculation["unresolved_choices"] = []
	finalization_calculation["starting_equipment"] = starting_grants.duplicate(true)
	var finalization_editor := editor_script.new() as VBoxContainer
	root.add_child(finalization_editor)
	finalization_editor.call("configure", finalization_state, finalization_calculation, repository, &"creation")
	await process_frame
	var finalize := _find_named(finalization_editor, "FinalizeAndContinueButton") as Button
	_assert_true(finalize != null, "creation mode exposes one finalization action")
	if finalize != null:
		_assert_equal(finalize.text, "FINALIZE LOADOUT AND CONTINUE TO REVIEW", "primary action states its outcome")
	_assert_true(_find_text_contains(finalization_editor, "Carried weight") != null, "creation review shows carried weight")
	_assert_true(_find_text_contains(finalization_editor, "Head AP") != null, "creation review shows armour by location")
	_assert_true(_find_text_contains(finalization_editor, "unprepared") == null, "creation mode hides raw unprepared state")
	_assert_true(_find_text_contains(finalization_editor, "reconciliation") == null, "creation mode hides reconciliation terminology")
	var completion_messages: Array[String] = []
	finalization_editor.connect("creation_finished", func(message: String) -> void: completion_messages.append(message))
	if finalize != null:
		finalize.pressed.emit()
		await process_frame
	_assert_true(not completion_messages.is_empty(), "creation finalization emits its completion signal")
	_assert_equal(finalization_state.loadout_state, CharacterState.LOADOUT_FINALIZED, "creation finalization updates the loadout state")
	finalization_editor.queue_free()
	await process_frame

	var transition_creator := creator_scene.instantiate() as Control
	root.add_child(transition_creator)
	await process_frame
	transition_creator.call("_on_creation_loadout_finished", "Loadout finalized.")
	await process_frame
	_assert_equal(transition_creator.get("active_stage"), "review", "creation completion moves directly to Review")
	var transition_stage_buttons := transition_creator.get("stage_buttons") as Dictionary
	var review_stage := transition_stage_buttons.get("review") as Button
	_assert_true(review_stage != null and review_stage.button_pressed, "creation completion presses the Review stage")
	transition_creator.queue_free()
	await process_frame

	var creation_editor := editor_script.new() as VBoxContainer
	root.add_child(creation_editor)
	creation_editor.call("configure", prepared_state, prepared_calculation, repository, &"creation")
	await process_frame
	_assert_true(_find_named(creation_editor, "CreationStartingEquipment") != null, "creation mode exposes Starting Equipment")
	_assert_true(_find_named(creation_editor, "CreationOptionalEquipment") != null, "creation mode exposes Add Optional Equipment")
	_assert_true(_find_named(creation_editor, "CreationReviewFinalize") != null, "creation mode exposes Review and Finalize")
	_assert_true(_find_named(creation_editor, "CraftsmanshipSelector") == null, "creation mode hides craftsmanship administration")
	_assert_true(_find_named(creation_editor, "OriginSelector") == null, "creation mode hides provenance administration")
	_assert_true(_find_named(creation_editor, "OwnedCustodianFilter") == null, "creation mode hides custody administration")
	_assert_true(_find_named(creation_editor, "StartingGrantReconciliation") == null, "creation mode hides reconciliation values")
	_assert_true(_find_text(creation_editor, "RECENT INVENTORY HISTORY") == null, "creation mode hides audit history")
	var creation_catalogue_search := creation_editor.get("catalogue_search") as LineEdit
	var creation_catalogue_details := creation_editor.get("catalogue_details") as RichTextLabel
	_assert_true(creation_catalogue_search != null and creation_catalogue_details != null, "creation mode exposes searchable optional equipment")
	if creation_catalogue_search != null and creation_catalogue_details != null:
		creation_catalogue_search.text = "m36 lasgun"
		creation_catalogue_search.text_changed.emit(creation_catalogue_search.text)
		await process_frame
		for field_name in ["Damage", "Pen", "Range", "RoF", "Magazine", "Reload", "Qualities"]:
			_assert_true(field_name in creation_catalogue_details.text, "creation weapon details include %s" % field_name)
	var owned_item_count := prepared_state.owned_items.size()
	creation_editor.call("_add_selected_item")
	_assert_equal(prepared_state.owned_items.size(), owned_item_count + 1, "creation adds one selected optional item")
	if prepared_state.owned_items.size() == owned_item_count + 1:
		var optional_item := prepared_state.owned_items[prepared_state.owned_items.size() - 1] as Dictionary
		_assert_equal((optional_item.get("custodian", {}) as Dictionary).get("type", ""), "character", "creation optional item defaults to character custody")
		_assert_equal(optional_item.get("craftsmanship", ""), "Common", "creation optional item defaults to Common craftsmanship")
		_assert_equal(optional_item.get("location", ""), "carried", "creation optional item defaults to carried location")
		_assert_equal(optional_item.get("origin", ""), "later_issue", "creation optional item defaults to later issue origin")
	creation_editor.queue_free()
	await process_frame
	var optional_calculation := CharacterCalculator.new().calculate(prepared_state, regiment_repository, repository)
	optional_calculation["starting_equipment"] = starting_grants.duplicate(true)
	var optional_editor := editor_script.new() as VBoxContainer
	root.add_child(optional_editor)
	optional_editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	optional_editor.call("configure", prepared_state, optional_calculation, repository, &"creation")
	optional_editor.size.x = 960.0
	await process_frame
	var optional_section := _find_named(optional_editor, "CreationOptionalEquipment")
	var starting_section := _find_named(optional_editor, "CreationStartingEquipment")
	_assert_true(_find_button(optional_editor, "ADD EQUIPMENT") != null, "creation add action uses concise player-facing text")
	var optional_remove := _find_named(optional_section, "CreationOptionalRemoveButton") as Button
	_assert_true(optional_remove != null, "creation optional additions expose a remove action")
	_assert_true(_find_text_contains(optional_section, "Basic | Damage 1d10+3 E | Pen") != null, "creation optional M36 card preserves the concise weapon profile")
	if optional_remove != null:
		var optional_count_before_removal := prepared_state.owned_items.size()
		optional_remove.pressed.emit()
		_assert_equal(prepared_state.owned_items.size(), optional_count_before_removal - 1, "creation optional remove action removes an owned item")
	_assert_true(_find_named(starting_section, "CreationOptionalRemoveButton") == null, "starting equipment remains protected from optional removal")
	for group_name in ["WEAPONS", "ARMOUR", "AMMUNITION", "GEAR"]:
		_assert_true(_find_text(optional_editor, group_name) != null, "prepared starting equipment groups %s for players" % group_name)
	_assert_true(_find_text(optional_editor, "Wargear | Standard issue") != null, "Uniform has a concise player-facing starting-equipment profile")
	_assert_true(_find_button(starting_section, "REMOVE") == null, "starting equipment entries cannot be removed during creation")
	_assert_interactive_controls_fit_width(optional_editor, 960.0)
	optional_editor.queue_free()
	await process_frame

	var mismatched_calculation := prepared_calculation.duplicate(true)
	mismatched_calculation["starting_equipment"] = [{ "id": "knife", "quantity": 1, "scope": "per_character" }]
	var mismatched_editor := editor_script.new() as VBoxContainer
	root.add_child(mismatched_editor)
	mismatched_editor.call("configure", prepared_state, mismatched_calculation, repository, &"creation")
	await process_frame
	_assert_true(_find_named(mismatched_editor, "RestoreStartingEquipmentButton") != null, "changed creation inputs offer a restore action")
	_assert_true(_find_text_contains(mismatched_editor, "Starting equipment changed") != null, "restore guidance uses player-facing language")
	mismatched_editor.queue_free()

	if _failures > 0:
		printerr("OWCA inventory UI tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA inventory UI tests passed.")
	quit(0)


func _find_button(node: Node, exact_text: String) -> Button:
	if node == null:
		return null
	for child in node.get_children():
		if child is Button and (child as Button).text == exact_text:
			return child as Button
		var nested := _find_button(child, exact_text)
		if nested != null:
			return nested
	return null


func _find_text(node: Node, exact_text: String) -> Label:
	if node == null:
		return null
	for child in node.get_children():
		if child is Label and (child as Label).text == exact_text:
			return child as Label
		var nested := _find_text(child, exact_text)
		if nested != null:
			return nested
	return null


func _find_text_contains(node: Node, fragment: String) -> Label:
	if node == null:
		return null
	for child in node.get_children():
		if child is Label and fragment in (child as Label).text:
			return child as Label
		var nested := _find_text_contains(child, fragment)
		if nested != null:
			return nested
	return null


func _find_named(node: Node, node_name: String) -> Node:
	if node == null:
		return null
	if node.name == node_name:
		return node
	for child in node.get_children():
		var nested := _find_named(child, node_name)
		if nested != null:
			return nested
	return null


func _assert_interactive_controls_fit_width(node: Node, viewport_width: float) -> void:
	for child in node.get_children():
		if child is Control and (child is Button or child is LineEdit or child is OptionButton or child is SpinBox):
			var control := child as Control
			if control.is_visible_in_tree() and control.get_global_rect().size.x > 0.0:
				_assert_true(control.get_global_rect().position.x >= 0.0 and control.get_global_rect().end.x <= viewport_width + 0.5, "%s remains horizontally visible at 960px" % control.name)
		_assert_interactive_controls_fit_width(child, viewport_width)


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAILED: %s" % label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAILED: %s (expected %s, got %s)" % [label, expected, actual])
