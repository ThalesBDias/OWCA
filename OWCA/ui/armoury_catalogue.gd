extends Control

## Read-only browser for immutable v0.6 equipment definitions.
##
## This scene intentionally has no Add, Equip, Buy, or ammunition controls.
## Those actions require owned item instances and belong to the v0.7 inventory.

const LANDING_SCENE := "res://OWCA/ui/LandingPage.tscn"
const CATEGORY_LABELS := {
	"all": "All categories",
	"ranged_weapon": "Ranged weapons",
	"melee_weapon": "Melee weapons",
	"grenade_missile": "Grenades & missiles",
	"ammunition": "Ammunition",
	"armour": "Armour",
	"wargear": "Wargear",
	"weapon_upgrade": "Weapon upgrades",
	"placeholder": "Regiment placeholders"
}
const COLOUR_BACKGROUND := Color("#101612")
const COLOUR_PANEL := Color("#202b23")
const COLOUR_BORDER := Color("#52614d")
const COLOUR_GOLD := Color("#d5b35b")
const COLOUR_TEXT := Color("#e7eadf")
const COLOUR_MUTED := Color("#a5ad9d")

var repository := EquipmentDataRepository.new()
var search_field: LineEdit
var category_filter: OptionButton
var availability_filter: OptionButton
var item_list: VBoxContainer
var details: RichTextLabel
var count_label: Label
var selected_id: String = ""


func _ready() -> void:
	_build_interface()
	var load_error := repository.load_data()
	if load_error != OK:
		details.text = "[color=#e07a65]The armoury catalogue could not be loaded.[/color]\n%s" % repository.last_error
		return
	_populate_availability_filter()
	_refresh_results()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(LANDING_SCENE)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = COLOUR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	page.add_child(header)
	var back := Button.new()
	back.text = "< LANDING PAGE"
	back.custom_minimum_size = Vector2(150, 42)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(LANDING_SCENE))
	header.add_child(back)
	var headings := VBoxContainer.new()
	headings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(headings)
	var title := Label.new()
	title.text = "DEPARTMENTO MUNITORUM ARMOURY"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", COLOUR_GOLD)
	headings.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Read-only Core equipment definitions  |  ownership and loadouts arrive in v0.7"
	subtitle.add_theme_color_override("font_color", COLOUR_MUTED)
	headings.add_child(subtitle)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	page.add_child(filters)
	search_field = LineEdit.new()
	search_field.name = "ArmourySearch"
	search_field.placeholder_text = "Search name, family, class, quality, or ID..."
	search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_field.custom_minimum_size.y = 42
	search_field.text_changed.connect(func(_value: String) -> void: _refresh_results())
	filters.add_child(search_field)
	category_filter = OptionButton.new()
	category_filter.name = "CategoryFilter"
	category_filter.custom_minimum_size = Vector2(200, 42)
	for category: String in CATEGORY_LABELS:
		category_filter.add_item(str(CATEGORY_LABELS[category]))
		category_filter.set_item_metadata(category_filter.item_count - 1, category)
	category_filter.item_selected.connect(func(_index: int) -> void: _refresh_results())
	filters.add_child(category_filter)
	availability_filter = OptionButton.new()
	availability_filter.name = "AvailabilityFilter"
	availability_filter.custom_minimum_size = Vector2(165, 42)
	availability_filter.item_selected.connect(func(_index: int) -> void: _refresh_results())
	filters.add_child(availability_filter)

	var columns := HSplitContainer.new()
	columns.name = "ArmouryColumns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 390
	page.add_child(columns)
	var list_panel := _make_panel()
	list_panel.custom_minimum_size.x = 300
	columns.add_child(list_panel)
	var list_column := VBoxContainer.new()
	list_column.add_theme_constant_override("separation", 8)
	list_panel.add_child(list_column)
	count_label = Label.new()
	count_label.add_theme_color_override("font_color", COLOUR_MUTED)
	list_column.add_child(count_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_column.add_child(scroll)
	item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 5)
	scroll.add_child(item_list)

	var detail_panel := _make_panel()
	detail_panel.custom_minimum_size.x = 420
	columns.add_child(detail_panel)
	details = RichTextLabel.new()
	details.name = "ArmouryDetails"
	details.bbcode_enabled = true
	details.fit_content = false
	details.scroll_active = true
	details.add_theme_font_size_override("normal_font_size", 16)
	details.add_theme_color_override("default_color", COLOUR_TEXT)
	detail_panel.add_child(details)

	var footer := Label.new()
	footer.text = "Profiles are reference data, not a combat tracker. Current ammunition is deliberately not stored here."
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", COLOUR_MUTED)
	footer.add_theme_font_size_override("font_size", 12)
	page.add_child(footer)


func _populate_availability_filter() -> void:
	availability_filter.clear()
	availability_filter.add_item("All availability")
	availability_filter.set_item_metadata(0, "")
	var values: Array[String] = []
	for item: Dictionary in repository.get_items():
		var value := str(item.get("availability", ""))
		if not value.is_empty() and value not in values:
			values.append(value)
	values.sort()
	for value: String in values:
		availability_filter.add_item(value)
		availability_filter.set_item_metadata(availability_filter.item_count - 1, value)


func _refresh_results() -> void:
	for child: Node in item_list.get_children():
		child.queue_free()
	var query := search_field.text.strip_edges().to_lower()
	var category := str(category_filter.get_item_metadata(category_filter.selected))
	var availability := str(availability_filter.get_item_metadata(availability_filter.selected)) if availability_filter.item_count > 0 else ""
	var matches: Array[Dictionary] = []
	for item: Dictionary in repository.get_items():
		if category != "all" and str(item.get("category", "")) != category:
			continue
		if not availability.is_empty() and str(item.get("availability", "")) != availability:
			continue
		if not query.is_empty() and query not in _search_text(item):
			continue
		matches.append(item)
	count_label.text = "%d definitions" % matches.size()
	for item: Dictionary in matches:
		var button := Button.new()
		button.name = "Item_%s" % item.get("id", "")
		button.text = "%s\n%s" % [item.get("name", "Item"), _compact_line(item)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 56
		button.pressed.connect(_select_item.bind(str(item.get("id", ""))))
		item_list.add_child(button)
	if matches.is_empty():
		details.text = "[color=#a5ad9d]No definitions match these filters.[/color]"
	elif selected_id.is_empty() or not _contains_id(matches, selected_id):
		_select_item(str(matches[0].get("id", "")))


func _select_item(item_id: String) -> void:
	selected_id = item_id
	var item := repository.get_item(item_id)
	if item.is_empty():
		return
	var lines: Array[String] = []
	lines.append("[font_size=27][color=#d5b35b]%s[/color][/font_size]" % item.get("name", "Item"))
	lines.append("[color=#a5ad9d]%s  |  %s[/color]" % [_category_label(str(item.get("category", ""))), item.get("availability", "Availability not listed")])
	lines.append("")
	var profile := item.get("profile", {}) as Dictionary
	if not profile.is_empty():
		lines.append("[b]WEAPON PROFILE[/b]")
		lines.append("Class: %s" % profile.get("class", "-"))
		lines.append("Damage: %s    Pen: %s" % [profile.get("damage", "-"), profile.get("penetration", "-")])
		if profile.has("range_m") or profile.has("range_text"):
			var range_text := str(profile.get("range_text", "%sm" % profile.get("range_m", "-")))
			lines.append("Range: %s    RoF: %s" % [range_text, profile.get("rate_of_fire", "-")])
		if profile.has("magazine"):
			lines.append("Magazine: %s    Reload: %s" % [profile.get("magazine", "-"), profile.get("reload", "-")])
		var qualities := profile.get("qualities", []) as Array
		lines.append("Qualities: %s" % (", ".join(qualities) if not qualities.is_empty() else "None"))
	var armour := item.get("armour", {}) as Dictionary
	if not armour.is_empty():
		lines.append("[b]ARMOUR PROFILE[/b]")
		lines.append("AP %s  |  %s" % [armour.get("ap", 0), ", ".join(armour.get("locations", []))])
	if item.has("weight_kg"):
		lines.append("Weight: %s kg" % item.get("weight_kg", 0))
	if item.has("ammunition_id"):
		lines.append("Ammunition: %s" % repository.get_item_name(str(item.get("ammunition_id", ""))))
	var summary := str(item.get("summary", ""))
	if not summary.is_empty():
		lines.append("")
		lines.append(summary)
	lines.append("")
	lines.append("[color=#a5ad9d]Stable ID: %s[/color]" % item.get("id", ""))
	lines.append("[color=#a5ad9d]Source: %s[/color]" % repository.get_source_label(item.get("source", {}) as Dictionary))
	details.text = "\n".join(lines)


func _search_text(item: Dictionary) -> String:
	var profile := item.get("profile", {}) as Dictionary
	return " ".join([
		str(item.get("id", "")), str(item.get("name", "")), str(item.get("family", "")),
		str(item.get("category", "")), str(item.get("availability", "")),
		str(profile.get("class", "")), " ".join(profile.get("qualities", [])), str(item.get("summary", ""))
	]).to_lower()


func _compact_line(item: Dictionary) -> String:
	var profile := item.get("profile", {}) as Dictionary
	if not profile.is_empty():
		return "%s  |  %s  |  Pen %s" % [profile.get("class", "Weapon"), profile.get("damage", "-"), profile.get("penetration", "-")]
	var armour := item.get("armour", {}) as Dictionary
	if not armour.is_empty():
		return "Armour  |  AP %s  |  %s" % [armour.get("ap", 0), ", ".join(armour.get("locations", []))]
	return "%s  |  %s" % [_category_label(str(item.get("category", ""))), item.get("availability", "-")]


func _contains_id(items: Array[Dictionary], item_id: String) -> bool:
	for item: Dictionary in items:
		if str(item.get("id", "")) == item_id:
			return true
	return false


func _category_label(category: String) -> String:
	return str(CATEGORY_LABELS.get(category, category.replace("_", " ").capitalize()))


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOUR_PANEL
	style.border_color = COLOUR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16
	style.content_margin_top = 16
	style.content_margin_right = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	return panel
