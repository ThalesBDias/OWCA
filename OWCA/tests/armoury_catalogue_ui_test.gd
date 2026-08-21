extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/armoury_catalogue_ui_test.gd

var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://OWCA/ui/ArmouryCatalogue.tscn") as PackedScene
	_assert_true(packed_scene != null, "Armoury scene loads")
	var armoury := packed_scene.instantiate() as Control
	root.add_child(armoury)
	await process_frame
	var search := armoury.get("search_field") as LineEdit
	var details := armoury.get("details") as RichTextLabel
	var count_label := armoury.get("count_label") as Label
	var repository := armoury.get("repository") as EquipmentDataRepository
	_assert_true(search != null, "search control is exposed")
	_assert_true(not details.text.is_empty(), "first matching definition renders details")
	_assert_equal(count_label.text, "%d definitions" % repository.get_selectable_items().size(), "normal Armoury browsing hides legacy aliases")
	_assert_equal(repository.get_item("lasgun_good").get("base_definition_id", ""), "m36_lasgun", "legacy craftsmanship IDs remain available for exact lookup")
	_assert_true(_find_named(armoury, "Item_lasgun_good") == null, "legacy Good M36 alias is absent from normal Armoury results")

	search.text = "hot-shot lasgun"
	armoury.call("_refresh_results")
	await process_frame
	_assert_equal(count_label.text, "1 definitions", "search narrows the catalogue")
	_assert_true(details.text.contains("Hot-shot lasgun"), "search result displays its profile")
	_assert_true(details.text.contains("Magazine: 30"), "weapon capacity is visible")
	_assert_true(details.text.contains("Source: OW Core p. 174"), "printed reference is visible")

	armoury.call("_select_item", "compact_upgrade")
	_assert_true(details.text.contains("Eligible: Pistol or Basic"), "Compact explains its eligible weapon targets")
	_assert_true(details.text.contains("Half weapon weight"), "Compact explains its half-weight effect")
	_assert_true(details.text.contains("Half Range") and details.text.contains("round up"), "Compact explains its rounded half-range effect")
	_assert_true(details.text.contains("Half Magazine") and details.text.contains("-1 Damage"), "Compact explains its capacity and Damage effects")
	_assert_true(details.text.contains("Source: OW Core p. 188"), "Compact retains its printed reference")
	armoury.call("_select_item", "red_dot_laser_sight")
	_assert_true(details.text.contains("One sight per weapon"), "Red-dot explains the sight installation limit")
	_assert_true(details.text.contains("+10 to Ballistic Skill Tests when firing a single shot"), "Red-dot explains its situational result")
	armoury.call("_select_item", "telescopic_sight")
	_assert_true(details.text.contains("One sight per weapon"), "Telescopic explains the sight installation limit")
	_assert_true(details.text.contains("Ignores long and extreme range penalties after taking a Full Aim"), "Telescopic explains its situational result")
	_assert_true(not details.text.contains("numeric_") and not details.text.contains("quality_"), "Armoury details do not expose raw operation names")

	if _failures > 0:
		printerr("OWCA Armoury UI tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA Armoury UI tests passed.")
	quit(0)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		printerr("FAILED: %s. Expected %s, got %s." % [label, expected, actual])
		_failures += 1


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAILED: %s" % label)
		_failures += 1


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
