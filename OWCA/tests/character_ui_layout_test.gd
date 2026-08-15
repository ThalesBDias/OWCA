extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/character_ui_layout_test.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://OWCA/ui/CharacterCreator.tscn") as PackedScene
	_assert_true(packed_scene != null, "Character Creator scene loads")
	var creator := packed_scene.instantiate() as Control
	root.add_child(creator)
	await process_frame
	creator.call("_select_stage", "xp")
	await process_frame

	for test_size in [Vector2i(960, 650), Vector2i(1090, 700), Vector2i(1280, 800)]:
		root.size = test_size
		await process_frame
		creator.call("_apply_responsive_layout")
		creator.call("_render_active_stage")
		await process_frame
		_assert_advancement_buttons_fit(creator, test_size)
		_assert_loadout_stage_navigation_fits(creator, test_size)

	creator.call("_select_stage", "characteristics")
	await process_frame
	for test_size in [Vector2i(960, 650), Vector2i(1090, 700), Vector2i(1280, 800)]:
		root.size = test_size
		await process_frame
		creator.call("_apply_responsive_layout")
		creator.call("_render_active_stage")
		await process_frame
		_assert_roll_buttons_fit(creator, test_size)

	root.size = Vector2i(960, 650)
	var character_repository := creator.get("character_repository") as CharacterDataRepository
	var regiment_repository := creator.get("regiment_repository") as RegimentDataRepository
	var finalization_state := CharacterState.new()
	var grants: Array = [{ "id": "knife", "quantity": 1, "scope": "per_character" }]
	CharacterInventoryService.new().materialize_starting_loadout(finalization_state, grants, character_repository.equipment_repository, "2026-08-15T13:00:00Z")
	var finalization_calculation := CharacterCalculator.new().calculate(finalization_state, regiment_repository, character_repository)
	finalization_calculation["valid"] = true
	finalization_calculation["errors"] = []
	finalization_calculation["unresolved_choices"] = []
	finalization_calculation["starting_equipment"] = grants
	creator.set("state", finalization_state)
	creator.set("calculation", finalization_calculation)
	creator.call("_select_stage", "loadout")
	await process_frame
	_assert_creation_finalize_fits(creator)

	creator.set("state", CharacterState.new())
	creator.call("_refresh")
	await process_frame
	creator.call("_select_stage", "review")
	await process_frame
	var export_button := _find_button(creator.get("stage_content") as Node, "EXPORT A4 PDF + PNG")
	_assert_true(export_button != null, "Review stage exposes printable dossier export")
	_assert_true(export_button.disabled, "export remains disabled for an incomplete character")

	print("OWCA character UI layout tests passed.")
	quit(0)


func _assert_advancement_buttons_fit(creator: Control, test_size: Vector2i) -> void:
	var content_panel := creator.get("content_panel") as Control
	var stage_content := creator.get("stage_content") as Control
	_assert_true(content_panel != null and stage_content != null, "responsive controls exist at %s" % test_size)
	var stage_scroll := stage_content.get_parent() as ScrollContainer
	_assert_true(stage_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "horizontal stage scrolling disabled at %s" % test_size)
	var content_rect := content_panel.get_global_rect()
	var buy_buttons: Array[Button] = []
	_collect_buy_buttons(stage_content, buy_buttons)
	_assert_true(not buy_buttons.is_empty(), "XP cards render Buy buttons at %s" % test_size)
	for button in buy_buttons:
		var button_rect := button.get_global_rect()
		_assert_true(button_rect.position.x >= content_rect.position.x - 1.0, "Buy button begins inside content panel at %s" % test_size)
		_assert_true(button_rect.end.x <= content_rect.end.x + 1.0, "Buy button ends inside content panel at %s" % test_size)


func _collect_buy_buttons(node: Node, output: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button and str((child as Button).text).begins_with("BUY FOR"):
			output.append(child as Button)
		_collect_buy_buttons(child, output)


func _assert_roll_buttons_fit(creator: Control, test_size: Vector2i) -> void:
	var content_panel := creator.get("content_panel") as Control
	var stage_content := creator.get("stage_content") as Control
	var content_rect := content_panel.get_global_rect()
	var roll_buttons: Array[Button] = []
	_collect_roll_buttons(stage_content, roll_buttons)
	_assert_true(roll_buttons.size() == 10, "roll-all and nine individual roll actions render at %s" % test_size)
	for button in roll_buttons:
		var button_rect := button.get_global_rect()
		_assert_true(button_rect.position.x >= content_rect.position.x - 1.0, "roll button begins inside content panel at %s" % test_size)
		_assert_true(button_rect.end.x <= content_rect.end.x + 1.0, "roll button ends inside content panel at %s" % test_size)


func _assert_loadout_stage_navigation_fits(creator: Control, test_size: Vector2i) -> void:
	var stage_buttons := creator.get("stage_buttons") as Dictionary
	var loadout_button := stage_buttons.get("loadout") as Button
	var status_label := creator.get("status_label") as Label
	_assert_true(loadout_button != null, "Loadout stage navigation exists at %s" % test_size)
	_assert_true(status_label != null and loadout_button.get_global_rect().end.y < status_label.get_global_rect().position.y, "Loadout stage remains above the bottom status panel at %s" % test_size)


func _assert_creation_finalize_fits(creator: Control) -> void:
	var content_panel := creator.get("content_panel") as Control
	var finalize := _find_named(creator.get("stage_content") as Node, "FinalizeAndContinueButton") as Button
	_assert_true(finalize != null and not finalize.disabled, "creation Loadout stage exposes an enabled finalization action at 960x650")
	if finalize != null and content_panel != null:
		var content_rect := content_panel.get_global_rect()
		var finalize_rect := finalize.get_global_rect()
		_assert_true(finalize_rect.position.x >= content_rect.position.x - 1.0, "creation finalization action begins inside the content panel at 960x650")
		_assert_true(finalize_rect.end.x <= content_rect.end.x + 1.0, "creation finalization action ends inside the content panel at 960x650")


func _collect_roll_buttons(node: Node, output: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button and str((child as Button).text).begins_with("ROLL"):
			output.append(child as Button)
		_collect_roll_buttons(child, output)


func _find_button(node: Node, exact_text: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == exact_text:
			return child as Button
		var nested := _find_button(child, exact_text)
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


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAILED: %s" % label)
		quit(1)
