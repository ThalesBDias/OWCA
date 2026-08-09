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
	_assert_true(_find_button(content, "PREPARE STARTING LOADOUT") != null, "character creation has a loadout preparation action")
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
	prepared_state.loadout_state = CharacterState.LOADOUT_DRAFT
	prepared_state.comrade = { "id": DocumentIdentity.generate(), "name": "Trooper Hale of the Thirty-Seventh Varanox Reserve" }
	var issued_knife_id := DocumentIdentity.generate()
	prepared_state.owned_items = [{
		"instance_id": issued_knife_id, "definition_id": "knife", "quantity": 1,
		"craftsmanship": "Common", "origin": "standard_issue", "location": "carried",
		"custodian": { "type": "character", "id": "" }, "note": ""
	}, {
		"instance_id": DocumentIdentity.generate(), "definition_id": "charge_pack", "quantity": 4,
		"craftsmanship": "Common", "origin": "standard_issue", "location": "carried",
		"custodian": { "type": "comrade", "id": prepared_state.comrade.get("id", "") }, "note": "Reserve ammunition assigned to Comrade"
	}]
	prepared_state.starting_loadout = [{
		"grant_id": "knife|per_character|1", "definition_id": "knife", "quantity": 1,
		"scope": "per_character", "origin": "standard_issue", "issued_instance_ids": [issued_knife_id],
		"reconciliation": "present", "note": ""
	}]
	var editor_script := load("res://OWCA/ui/character_inventory_editor.gd") as GDScript
	var shared_editor := editor_script.new() as VBoxContainer
	root.add_child(shared_editor)
	shared_editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	shared_editor.call("configure", prepared_state, CharacterCalculator.new().calculate(prepared_state, regiment_repository, repository), repository)
	shared_editor.size.x = 960.0
	await process_frame
	_assert_true(_find_named(shared_editor, "CraftsmanshipSelector") != null, "owned rows expose craftsmanship editing")
	_assert_true(_find_named(shared_editor, "OriginSelector") != null, "owned rows expose origin editing")
	_assert_true(_find_named(shared_editor, "OwnedCustodianFilter") != null, "owned inventory can be filtered by custodian")
	_assert_true(_find_named(shared_editor, "StartingGrantReconciliation") != null, "starting grants expose explicit reconciliation controls")
	_assert_true(_find_button(shared_editor, "SPLIT ONE") != null, "stackable equipment exposes a safe split action")
	var catalogue_search := shared_editor.get("catalogue_search") as LineEdit
	var catalogue_details := shared_editor.get("catalogue_details") as RichTextLabel
	_assert_true(catalogue_search != null and catalogue_details != null, "catalogue exposes searchable item details")
	if catalogue_search != null and catalogue_details != null:
		catalogue_search.text = "m36 lasgun"
		catalogue_search.text_changed.emit(catalogue_search.text)
		await process_frame
		_assert_true("Reload Full" in catalogue_details.text, "weapon details include reload time")
		_assert_true("Qualities Reliable" in catalogue_details.text, "weapon details include qualities")
	_assert_interactive_controls_fit_width(shared_editor, 960.0)
	shared_editor.queue_free()

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


func _find_named(node: Node, node_name: String) -> Node:
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
