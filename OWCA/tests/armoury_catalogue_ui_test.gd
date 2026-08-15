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
	_assert_true(search != null, "search control is exposed")
	_assert_true(not details.text.is_empty(), "first matching definition renders details")
	_assert_true(count_label.text.contains("115"), "all definitions render initially")

	search.text = "hot-shot lasgun"
	armoury.call("_refresh_results")
	await process_frame
	_assert_equal(count_label.text, "1 definitions", "search narrows the catalogue")
	_assert_true(details.text.contains("Hot-shot lasgun"), "search result displays its profile")
	_assert_true(details.text.contains("Magazine: 30"), "weapon capacity is visible")
	_assert_true(details.text.contains("Source: OW Core p. 174"), "printed reference is visible")

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
