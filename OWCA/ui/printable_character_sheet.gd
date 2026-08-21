class_name PrintableCharacterSheet
extends Control

## Original OWCA A4 field-dossier sheet. It is rendered off-screen at 300 DPI.

const PAGE_SIZE := Vector2i(2480, 3508)
const INK := Color("#241d17")
const INK_MUTED := Color("#57493a")
const PARCHMENT := Color("#eee1bd")
const PARCHMENT_DARK := Color("#d2bc88")
const STEEL := Color("#282d2d")
const STEEL_LIGHT := Color("#676b66")
const OXBLOOD := Color("#76291f")
const OXBLOOD_DARK := Color("#461711")
const BRASS := Color("#b58a38")
const HAZARD := Color("#d29a1e")
const WHITE_INK := Color("#f3ead4")
const PANEL_HEADER_HEIGHT := 74.0
const IDENTITY_PANEL := Rect2(130, 352, 2220, 210)
const IDENTITY_NAME_POSITION := Vector2(175, 493)
const IDENTITY_NAME_FONT_SIZE := 60
const IDENTITY_PLAYER_LABEL_POSITION := Vector2(1510, 455)
const IDENTITY_PLAYER_LABEL_FONT_SIZE := 25

var character_state: CharacterState
var calculation: Dictionary = {}
var page_number: int = 1
var total_pages: int = 2
var font: Font


func configure(state: CharacterState, result: Dictionary, page: int, pages: int = 2) -> void:
	character_state = state
	calculation = result.duplicate(true)
	page_number = page
	total_pages = pages
	custom_minimum_size = PAGE_SIZE
	size = PAGE_SIZE
	font = ThemeDB.fallback_font
	queue_redraw()


func _draw() -> void:
	if font == null:
		font = ThemeDB.fallback_font
	_draw_background()
	_draw_outer_frame()
	if page_number == 1:
		_draw_page_one()
	elif page_number == 2:
		_draw_page_two()
	else:
		_draw_loadout_continuation(page_number - 3)
	_draw_footer()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, PAGE_SIZE), PARCHMENT)
	for index in 420:
		var x := float(70 + ((index * 193) % 2340))
		var y := float(65 + ((index * 347) % 3365))
		var radius := float(1 + (index % 5))
		var alpha := 0.018 + float(index % 4) * 0.006
		draw_circle(Vector2(x, y), radius, Color(0.24, 0.17, 0.1, alpha))
	for index in 34:
		var y := float(120 + index * 97)
		draw_line(Vector2(110, y), Vector2(2370, y + float((index % 3) - 1) * 4.0), Color(0.25, 0.18, 0.1, 0.045), 2.0)


func _draw_outer_frame() -> void:
	draw_rect(Rect2(24, 24, 2432, 3460), STEEL, true)
	draw_rect(Rect2(48, 48, 2384, 3412), STEEL_LIGHT, false, 8.0)
	draw_rect(Rect2(72, 72, 2336, 3364), PARCHMENT, true)
	draw_rect(Rect2(72, 72, 2336, 3364), INK, false, 8.0)
	for corner in [Vector2(52, 52), Vector2(2428, 52), Vector2(52, 3456), Vector2(2428, 3456)]:
		draw_circle(corner, 15.0, BRASS)
		draw_circle(corner, 7.0, INK)
	_draw_corner_plate(Vector2(72, 72), false, false)
	_draw_corner_plate(Vector2(2408, 72), true, false)
	_draw_corner_plate(Vector2(72, 3436), false, true)
	_draw_corner_plate(Vector2(2408, 3436), true, true)


func _draw_corner_plate(origin: Vector2, flip_x: bool, flip_y: bool) -> void:
	var sx := -1.0 if flip_x else 1.0
	var sy := -1.0 if flip_y else 1.0
	var points := PackedVector2Array([
		origin,
		origin + Vector2(190.0 * sx, 0),
		origin + Vector2(150.0 * sx, 38.0 * sy),
		origin + Vector2(0, 38.0 * sy)
	])
	draw_colored_polygon(points, STEEL_LIGHT)
	draw_polyline(points, INK, 5.0)


func _draw_header(subtitle: String) -> void:
	var header := Rect2(122, 112, 2236, 220)
	draw_rect(header, PARCHMENT_DARK, true)
	draw_rect(header, INK, false, 7.0)
	draw_rect(Rect2(header.position, Vector2(64, header.size.y)), OXBLOOD, true)
	draw_rect(Rect2(header.end.x - 64, header.position.y, 64, header.size.y), OXBLOOD, true)
	_draw_text("OWCA", Vector2(160, 195), 45, WHITE_INK)
	_draw_text("GUARDSMAN FIELD RECORD", Vector2(340, 220), 76, INK, 1700, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(subtitle.to_upper(), Vector2(340, 288), 34, OXBLOOD_DARK, 1700, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text("%d / %d" % [page_number, total_pages], Vector2(2165, 210), 36, WHITE_INK, 140, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_page_one() -> void:
	_draw_header("Primary Character Sheet")
	_draw_panel(IDENTITY_PANEL, "IDENTIFICATION", "I")
	_draw_text(character_state.character_name if character_state != null else "Unnamed Character", IDENTITY_NAME_POSITION, IDENTITY_NAME_FONT_SIZE, OXBLOOD_DARK, 1300)
	_draw_text("PLAYER", IDENTITY_PLAYER_LABEL_POSITION, IDENTITY_PLAYER_LABEL_FONT_SIZE, INK_MUTED)
	_draw_text(_value(character_state.player_name if character_state != null else ""), Vector2(1510, 494), 36, INK, 760)
	_draw_text("REGIMENT", Vector2(175, 540), 24, INK_MUTED)
	_draw_text(str(calculation.get("regiment_name", "-")), Vector2(355, 540), 31, INK, 900)
	_draw_text("SPECIALITY", Vector2(1320, 540), 24, INK_MUTED)
	_draw_text(str(calculation.get("speciality_name", "-")), Vector2(1520, 540), 31, INK, 760)

	var characteristics_panel := Rect2(130, 585, 2220, 390)
	_draw_panel(characteristics_panel, "CHARACTERISTICS", "1")
	var characteristic_width := 238.0
	var characteristics := calculation.get("characteristics", {}) as Dictionary
	var bonuses := calculation.get("characteristic_bonuses", {}) as Dictionary
	for index in CharacterState.CHARACTERISTIC_ORDER.size():
		var characteristic := CharacterState.CHARACTERISTIC_ORDER[index]
		var box := Rect2(154 + index * characteristic_width, 690, characteristic_width - 12, 245)
		draw_rect(box, Color(PARCHMENT_DARK, 0.32), true)
		draw_rect(box, INK, false, 4.0)
		_draw_text(_abbreviation(characteristic), Vector2(box.position.x, box.position.y + 46), 33, OXBLOOD_DARK, box.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_wrapped(characteristic, Rect2(box.position.x + 8, box.position.y + 54, box.size.x - 16, 58), 19, INK_MUTED, HORIZONTAL_ALIGNMENT_CENTER, 2)
		_draw_text(str(characteristics.get(characteristic, "-")), Vector2(box.position.x, box.position.y + 166), 69, INK, box.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text("BONUS %s" % str(bonuses.get(characteristic, "-")), Vector2(box.position.x, box.position.y + 218), 24, INK_MUTED, box.size.x, HORIZONTAL_ALIGNMENT_CENTER)

	var derived_panel := Rect2(130, 996, 2220, 220)
	_draw_panel(derived_panel, "FIELD VALUES", "2")
	var movement := calculation.get("movement", {}) as Dictionary
	var derived_values := [
		["WOUNDS", str(calculation.get("wounds", "-"))],
		["FATE", str(calculation.get("fate_points", "-"))],
		["MOVEMENT", "%s / %s / %s / %s" % [movement.get("half", "-"), movement.get("full", "-"), movement.get("charge", "-"), movement.get("run", "-")]],
		["XP SPENT", str(calculation.get("xp_spent", 0))],
		["XP LEFT", str(calculation.get("xp_remaining", 0))]
	]
	var derived_width := 424.0
	for index in derived_values.size():
		var x := 165 + index * derived_width
		_draw_text(str(derived_values[index][0]), Vector2(x, 1096), 24, INK_MUTED, derived_width - 20, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_text(str(derived_values[index][1]), Vector2(x, 1166), 45 if index != 2 else 31, INK, derived_width - 20, HORIZONTAL_ALIGNMENT_CENTER)
		if index < derived_values.size() - 1:
			draw_line(Vector2(x + derived_width - 10, 1080), Vector2(x + derived_width - 10, 1188), INK_MUTED, 2.0)

	var skills_panel := Rect2(130, 1238, 1085, 985)
	_draw_panel(skills_panel, "SKILLS", "3")
	var skill_lines: Array[String] = []
	for skill: Dictionary in calculation.get("skills", []):
		skill_lines.append("%s [%s]" % [skill.get("name", "Skill"), skill.get("rank_label", "Known")])
	_draw_list(skill_lines, Rect2(165, 1330, 1015, 850), 29, 39)

	var talents_panel := Rect2(1235, 1238, 1115, 985)
	_draw_panel(talents_panel, "TALENTS", "4")
	var talent_lines: Array[String] = []
	for talent: Dictionary in calculation.get("talents", []):
		var suffix := " x%d" % int(talent.get("count", 1)) if int(talent.get("count", 1)) > 1 else ""
		talent_lines.append("%s%s" % [talent.get("name", "Talent"), suffix])
	_draw_list(talent_lines, Rect2(1270, 1330, 1045, 850), 29, 39)

	var equipment_panel := Rect2(130, 2245, 2220, 500)
	_draw_panel(equipment_panel, "OWNED LOADOUT, ARMOUR AND ENCUMBRANCE", "5")
	var equipment_lines := build_loadout_lines(calculation, _comrade_name())
	var loadout_pages := layout_wrapped_pages(equipment_lines, 2150.0 / 3.0, 3, 26, 10, 76)
	_draw_wrapped_column_layout(loadout_pages[0] as Array, Rect2(165, 2340, 2150, 360), 26, 34)

	var tracker_panel := Rect2(130, 2768, 1085, 430)
	_draw_panel(tracker_panel, "TABLETOP TRACKERS", "6")
	var maximum_wounds := int(calculation.get("wounds", 0))
	var maximum_fate := int(calculation.get("fate_points", 0))
	var maximum_fatigue := int(bonuses.get("Toughness", 0))
	_draw_tracker("WOUNDS", maximum_wounds, Vector2(170, 2890), mini(maximum_wounds, 12))
	_draw_tracker("FATE", maximum_fate, Vector2(170, 3000), maximum_fate)
	_draw_tracker("FATIGUE", maximum_fatigue, Vector2(170, 3110), maximum_fatigue)

	var notes_panel := Rect2(1235, 2768, 1115, 430)
	_draw_panel(notes_panel, "SESSION NOTES", "7")
	_draw_writing_lines(Rect2(1275, 2880, 1035, 270), 5)


func _draw_page_two() -> void:
	_draw_header("Rules, Advances and Campaign Record")
	var aptitudes_panel := Rect2(130, 352, 1085, 350)
	_draw_panel(aptitudes_panel, "APTITUDES", "8")
	var aptitude_lines: Array[String] = []
	for aptitude: Variant in calculation.get("aptitudes", []):
		aptitude_lines.append(str(aptitude))
	_draw_multicolumn_list(aptitude_lines, Rect2(165, 448, 1015, 210), 2, 29, 42)

	var advances_panel := Rect2(1235, 352, 1115, 350)
	_draw_panel(advances_panel, "PURCHASED ADVANCES", "9")
	var advance_lines: Array[String] = []
	for purchase: Dictionary in calculation.get("purchased_advances", []):
		advance_lines.append("%s - %s (%d XP)" % [purchase.get("name", "Advance"), purchase.get("rank_label", ""), int(purchase.get("cost", 0))])
	_draw_list(advance_lines, Rect2(1270, 448, 1045, 210), 25, 35)

	var rules_panel := Rect2(130, 724, 1320, 1120)
	_draw_panel(rules_panel, "SPECIAL RULES", "10")
	var rule_y := 828.0
	for rule: Dictionary in calculation.get("special_rules", []):
		if rule_y > rules_panel.end.y - 100:
			break
		_draw_text(str(rule.get("name", "Rule")), Vector2(175, rule_y), 30, OXBLOOD_DARK, 1225)
		var used := _draw_wrapped(str(rule.get("summary", "")), Rect2(195, rule_y + 16, 1195, 200), 25, INK, HORIZONTAL_ALIGNMENT_LEFT, 4)
		rule_y += 62.0 + used
		draw_line(Vector2(175, rule_y - 20), Vector2(1400, rule_y - 20), Color(INK_MUTED, 0.45), 2.0)

	var choices_panel := Rect2(1470, 724, 880, 560)
	_draw_panel(choices_panel, "RESOLVED CHOICES", "11")
	var choice_lines: Array[String] = []
	for choice: Dictionary in calculation.get("resolved_choices", []):
		choice_lines.append("%s: %s" % [choice.get("prompt", "Choice"), ", ".join(choice.get("answers", []) as Array)])
	_draw_list(choice_lines, Rect2(1505, 820, 810, 420), 23, 34)

	var sources_panel := Rect2(1470, 1304, 880, 540)
	_draw_panel(sources_panel, "SOURCE REFERENCES", "12")
	var source_lines: Array[String] = []
	for source: Dictionary in calculation.get("sources", []):
		source_lines.append(str(source.get("label", "Source")))
	_draw_multicolumn_list(source_lines, Rect2(1505, 1400, 810, 400), 2, 24, 35)

	var campaign_panel := Rect2(130, 1868, 2220, 1330)
	_draw_panel(campaign_panel, "CAMPAIGN RECORD AND NOTES", "13")
	_draw_text("INSANITY", Vector2(180, 1985), 25, INK_MUTED)
	_draw_empty_value_box(Rect2(355, 1938, 180, 74))
	_draw_text("CORRUPTION", Vector2(600, 1985), 25, INK_MUTED)
	_draw_empty_value_box(Rect2(830, 1938, 180, 74))
	_draw_text("CURRENT XP", Vector2(1080, 1985), 25, INK_MUTED)
	_draw_empty_value_box(Rect2(1300, 1938, 210, 74))
	_draw_text("TOTAL SPENT", Vector2(1580, 1985), 25, INK_MUTED)
	_draw_empty_value_box(Rect2(1815, 1938, 210, 74))
	_draw_text("MISSION / DATE", Vector2(180, 2085), 25, INK_MUTED)
	_draw_text("NOTES, INJURIES, REQUISITIONS AND ADVANCES", Vector2(810, 2085), 25, INK_MUTED)
	for row in 8:
		var y := 2110.0 + row * 126.0
		draw_rect(Rect2(175, y, 580, 102), INK_MUTED, false, 2.0)
		draw_rect(Rect2(780, y, 1515, 102), INK_MUTED, false, 2.0)


func _draw_loadout_continuation(continuation_index: int) -> void:
	_draw_header("Owned Loadout Continuation")
	var panel := Rect2(130, 352, 2220, 2846)
	_draw_panel(panel, "OWNED LOADOUT - CONTINUED", "L")
	var lines := build_loadout_lines(calculation, _comrade_name())
	var pages := layout_wrapped_pages(lines, 2150.0 / 3.0, 3, 26, 10, 76)
	var layout_index := continuation_index + 1
	if layout_index < pages.size():
		_draw_wrapped_column_layout(pages[layout_index] as Array, Rect2(165, 448, 2150, 2660), 26, 34)


func _draw_panel(rect: Rect2, title: String, number: String) -> void:
	draw_rect(rect, Color(PARCHMENT, 0.92), true)
	draw_rect(rect, INK, false, 7.0)
	draw_rect(Rect2(rect.position + Vector2(12, 12), rect.size - Vector2(24, 24)), INK_MUTED, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, PANEL_HEADER_HEIGHT)), Color(PARCHMENT_DARK, 0.7), true)
	draw_rect(Rect2(rect.position, Vector2(82, PANEL_HEADER_HEIGHT)), OXBLOOD, true)
	_draw_text(number, rect.position + Vector2(0, 53), 37, WHITE_INK, 82, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(title, rect.position + Vector2(105, 53), 36, OXBLOOD_DARK, rect.size.x - 130)
	draw_line(Vector2(rect.position.x + 100, rect.position.y + 68), Vector2(rect.end.x - 20, rect.position.y + 68), INK_MUTED, 2.0)


func get_identity_layout_metrics() -> Dictionary:
	var layout_font := font if font != null else ThemeDB.fallback_font
	return {
		"header_bottom": IDENTITY_PANEL.position.y + PANEL_HEADER_HEIGHT,
		"character_name_top": IDENTITY_NAME_POSITION.y - layout_font.get_ascent(IDENTITY_NAME_FONT_SIZE),
		"player_label_top": IDENTITY_PLAYER_LABEL_POSITION.y - layout_font.get_ascent(IDENTITY_PLAYER_LABEL_FONT_SIZE)
	}


func _draw_text(text: String, position: Vector2, font_size: int, colour: Color, width: float = -1.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, position, text, alignment, width, font_size, colour)


func _draw_wrapped(text: String, rect: Rect2, font_size: int, colour: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, max_lines: int = -1) -> float:
	var lines := _wrap_text(text, rect.size.x, font_size)
	if max_lines > 0 and lines.size() > max_lines:
		lines.resize(max_lines)
		lines[max_lines - 1] = str(lines[max_lines - 1]).trim_suffix(".") + "..."
	var line_height := font.get_height(font_size) * 1.18
	for index in lines.size():
		var y := rect.position.y + line_height * float(index + 1)
		if y > rect.end.y:
			break
		_draw_text(str(lines[index]), Vector2(rect.position.x, y), font_size, colour, rect.size.x, alignment)
	return line_height * float(lines.size())


func _wrap_text(text: String, width: float, font_size: int) -> Array[String]:
	var output: Array[String] = []
	for paragraph in text.replace("\r", "").split("\n"):
		var current := ""
		for word in str(paragraph).split(" ", false):
			var candidate := word if current.is_empty() else current + " " + word
			if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width or current.is_empty():
				current = candidate
			else:
				output.append(current)
				current = word
		if not current.is_empty():
			output.append(current)
		elif str(paragraph).is_empty():
			output.append("")
	return output


func _draw_list(items: Array[String], rect: Rect2, font_size: int, line_height: float) -> void:
	var y := rect.position.y
	for item in items:
		var wrapped := _wrap_text(item, rect.size.x - 48.0, font_size)
		if y + line_height * wrapped.size() > rect.end.y:
			_draw_text("- ...", Vector2(rect.position.x, rect.end.y - 12), font_size, INK_MUTED)
			break
		_draw_text("-", Vector2(rect.position.x, y + line_height * 0.78), font_size, OXBLOOD_DARK)
		for index in wrapped.size():
			_draw_text(wrapped[index], Vector2(rect.position.x + 34, y + line_height * float(index + 0.78)), font_size, INK, rect.size.x - 34)
		y += maxf(line_height, line_height * wrapped.size())


func _draw_multicolumn_list(items: Array[String], rect: Rect2, columns: int, font_size: int, line_height: float) -> void:
	if items.is_empty():
		_draw_text("-", rect.position + Vector2(0, line_height), font_size, INK_MUTED)
		return
	var rows := ceili(float(items.size()) / float(columns))
	var column_width := rect.size.x / float(columns)
	for index in items.size():
		var column := index / rows
		var row := index % rows
		var position := Vector2(rect.position.x + column * column_width, rect.position.y + (row + 0.8) * line_height)
		_draw_text("- %s" % items[index], position, font_size, INK, column_width - 24)


func _draw_wrapped_multicolumn_list(items: Array[String], rect: Rect2, columns: int, font_size: int, line_height: float) -> void:
	var column_width := rect.size.x / float(columns)
	var max_rows := floori(rect.size.y / line_height)
	var layout := layout_wrapped_columns(items, column_width, columns, font_size, max_rows)
	_draw_wrapped_column_layout(layout, rect, font_size, line_height)


func _draw_wrapped_column_layout(layout: Array, rect: Rect2, font_size: int, line_height: float) -> void:
	var column_width := rect.size.x / float(maxi(1, layout.size()))
	for column_index in layout.size():
		var lines := layout[column_index] as Array
		for row_index in lines.size():
			var position := Vector2(rect.position.x + column_index * column_width, rect.position.y + (row_index + 0.8) * line_height)
			_draw_text(str(lines[row_index]), position, font_size, INK, column_width - 24)


## Produces the exact line layout used by the printable loadout panel. Keeping
## this projection deterministic lets regression tests catch clipped records.
func layout_wrapped_columns(items: Array[String], column_width: float, columns: int, font_size: int, max_rows: int) -> Array:
	var pages := layout_wrapped_pages(items, column_width, columns, font_size, max_rows, max_rows)
	return pages[0] if not pages.is_empty() else []


## Paginates every wrapped loadout line. The first page uses the compact
## primary-sheet panel; continuation pages use a full printable panel.
func layout_wrapped_pages(items: Array[String], column_width: float, columns: int, font_size: int, first_max_rows: int, continuation_max_rows: int) -> Array:
	if font == null:
		font = ThemeDB.fallback_font
	var groups: Array[Array] = []
	for item in items:
		var wrapped: Array[String] = _wrap_text("- %s" % item, column_width - 24.0, font_size)
		for index in range(1, wrapped.size()):
			wrapped[index] = "  %s" % wrapped[index]
		groups.append(wrapped)
	if groups.is_empty():
		groups.append(["-"])
	var pages: Array = [_empty_columns(columns)]
	var page_index := 0
	var column_index := 0
	for group: Array in groups:
		var pending := group.duplicate()
		while not pending.is_empty():
			var max_rows := first_max_rows if page_index == 0 else continuation_max_rows
			var column := (pages[page_index] as Array)[column_index] as Array
			var remaining := max_rows - column.size()
			if remaining <= 0 or (pending.size() > remaining and not column.is_empty()):
				column_index += 1
				if column_index >= columns:
					pages.append(_empty_columns(columns))
					page_index += 1
					column_index = 0
				continue
			var take := mini(remaining, pending.size())
			for _line_index in take:
				column.append(pending.pop_front())
	return pages


func _empty_columns(columns: int) -> Array:
	var output: Array = []
	for _column in columns:
		output.append([])
	return output


func _columns_from_visual_lines(visual_lines: Array[String], columns: int, max_rows: int) -> Array:
	var output: Array = []
	for _column in columns:
		output.append([])
	var rows := mini(max_rows, ceili(float(visual_lines.size()) / float(columns)))
	for index in visual_lines.size():
		var column := mini(columns - 1, index / rows)
		(output[column] as Array).append(visual_lines[index])
	return output


func get_required_page_count(result: Dictionary, comrade_name: String = "") -> int:
	font = ThemeDB.fallback_font if font == null else font
	var pages := layout_wrapped_pages(build_loadout_lines(result, comrade_name), 2150.0 / 3.0, 3, 26, 10, 76)
	return 2 + maxi(0, pages.size() - 1)


func _draw_tracker(label: String, maximum: int, position: Vector2, box_count: int) -> void:
	_draw_text("%s  MAX %s" % [label, str(maximum) if maximum > 0 else "___"], position, 27, INK)
	for index in box_count:
		var box := Rect2(position.x + 300 + index * 58, position.y - 34, 44, 44)
		draw_rect(box, INK, false, 3.0)


func _draw_writing_lines(rect: Rect2, count: int) -> void:
	var spacing := rect.size.y / float(count)
	for index in count:
		var y := rect.position.y + spacing * float(index + 1)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(INK_MUTED, 0.65), 2.0)


func _draw_empty_value_box(rect: Rect2) -> void:
	draw_rect(rect, Color(PARCHMENT_DARK, 0.25), true)
	draw_rect(rect, INK, false, 3.0)


## Returns the concise printable projection. Inventory history intentionally
## remains in JSON/UI so the field sheet stays useful at the table.
func build_loadout_lines(result: Dictionary, comrade_name: String = "") -> Array[String]:
	var lines: Array[String] = []
	if not comrade_name.strip_edges().is_empty():
		lines.append("Comrade: %s" % comrade_name.strip_edges())
	for item: Dictionary in result.get("equipment", []):
		var custodian := item.get("custodian", {}) as Dictionary
		var owner := str(custodian.get("type", "character"))
		var owner_label := comrade_name.strip_edges() if owner == "comrade" and not comrade_name.strip_edges().is_empty() else owner.capitalize()
		var context := str(item.get("location", "carried")).capitalize() if owner == "character" else "%s / %s" % [owner_label, str(item.get("location", "carried")).capitalize()]
		var weapon := item.get("weapon", {}) as Dictionary
		if bool(weapon.get("valid", false)):
			lines.append("%dx %s [%s]" % [item.get("quantity", 1), _printable_weapon_name(item), context])
			_append_printable_weapon_lines(lines, weapon)
		else:
			lines.append("%dx %s [%s]" % [item.get("quantity", 1), item.get("name", item.get("definition_id", "Item")), context])
	var inventory := result.get("inventory", {}) as Dictionary
	var encumbrance := inventory.get("encumbrance", {}) as Dictionary
	if not encumbrance.is_empty():
		lines.append("Weight: %.2f / %.2f kg [%s]" % [float(encumbrance.get("known_weight_kg", 0.0)), float(encumbrance.get("carrying_limit_kg", 0.0)), str(encumbrance.get("status", "partial")).replace("_", " ")])
	var armour := inventory.get("armour_by_location", {}) as Dictionary
	if not armour.is_empty():
		lines.append("Armour: Head %d | Arms %d | Body %d | Legs %d" % [int((armour.get("Head", {}) as Dictionary).get("ap", 0)), int((armour.get("Arms", {}) as Dictionary).get("ap", 0)), int((armour.get("Body", {}) as Dictionary).get("ap", 0)), int((armour.get("Legs", {}) as Dictionary).get("ap", 0))])
	return lines


func _printable_weapon_name(item: Dictionary) -> String:
	var item_name := str(item.get("name", item.get("definition_id", "Weapon")))
	for legacy_prefix in ["Poor Craftsmanship ", "Common Craftsmanship ", "Good Craftsmanship ", "Best Craftsmanship "]:
		if item_name.begins_with(legacy_prefix):
			item_name = item_name.trim_prefix(legacy_prefix)
			break
	return "%s %s" % [item.get("craftsmanship", "Common"), item_name]


func _append_printable_weapon_lines(lines: Array[String], weapon: Dictionary) -> void:
	var installed_names: Array[String] = []
	for modification_value: Variant in weapon.get("installed_modifications", []):
		var modification := modification_value as Dictionary
		installed_names.append(str(modification.get("name", modification.get("id", "Upgrade"))))
	lines.append("Upgrades: %s" % (", ".join(installed_names) if not installed_names.is_empty() else "None"))
	var profile := weapon.get("final_profile", {}) as Dictionary
	var range_value: Variant = profile.get("range_m", profile.get("range_text", "-"))
	var qualities := profile.get("qualities", []) as Array
	lines.append("Final profile: Damage %s | Pen %s | Range %s | RoF %s | Magazine %s | Qualities %s | %.2f kg" % [
		profile.get("damage", "-"),
		profile.get("penetration", "-"),
		range_value,
		profile.get("rate_of_fire", "-"),
		profile.get("magazine", "-"),
		", ".join(qualities) if not qualities.is_empty() else "None",
		float(weapon.get("final_weight_kg", 0.0))
	])
	for step_value: Variant in weapon.get("steps", []):
		var step := step_value as Dictionary
		var target := str(step.get("target", ""))
		if not target.begins_with("situational.") and step.get("before") == step.get("after"):
			continue
		lines.append("%s: %s" % [step.get("label", "Rule"), _printable_step_summary(step)])


func _printable_step_summary(step: Dictionary) -> String:
	var target := str(step.get("target", ""))
	if target.begins_with("situational."):
		return str(step.get("summary", "Situational rule applies."))
	var before: Variant = step.get("before")
	var after: Variant = step.get("after")
	var label := "Weapon value"
	match target:
		"weight_kg":
			label = "Weight"
			return "%s %.2f to %.2f kg" % [label, float(before), float(after)]
		"profile.range_m":
			label = "Range"
		"profile.magazine":
			label = "Magazine"
		"profile.damage_bonus":
			label = "Damage bonus"
		"profile.penetration":
			label = "Penetration"
		"profile.qualities":
			label = "Qualities"
	if before is Array and after is Array:
		return "%s %s to %s" % [label, ", ".join(before as Array), ", ".join(after as Array)]
	return "%s %s to %s" % [label, before, after]


func _comrade_name() -> String:
	return str(character_state.comrade.get("name", "")) if character_state != null else ""


func _draw_footer() -> void:
	var bar := Rect2(120, 3230, 2240, 156)
	draw_rect(bar, STEEL, true)
	for index in 16:
		var x := bar.position.x + index * 142.0
		var points := PackedVector2Array([
			Vector2(x, bar.position.y),
			Vector2(x + 74, bar.position.y),
			Vector2(x + 28, bar.position.y + 42),
			Vector2(x - 46, bar.position.y + 42)
		])
		draw_colored_polygon(points, HAZARD if index % 2 == 0 else INK)
	_draw_text("UNOFFICIAL OWCA CHARACTER AID - PRINT AT 100% - A4", Vector2(310, 3324), 28, WHITE_INK, 1740, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text("PAGE %d OF %d" % [page_number, total_pages], Vector2(2070, 3324), 27, WHITE_INK, 230, HORIZONTAL_ALIGNMENT_CENTER)


func _abbreviation(characteristic: String) -> String:
	return {
		"Weapon Skill": "WS", "Ballistic Skill": "BS", "Strength": "S",
		"Toughness": "T", "Agility": "Ag", "Intelligence": "Int",
		"Perception": "Per", "Willpower": "WP", "Fellowship": "Fel"
	}.get(characteristic, characteristic.left(3))


func _value(value: String) -> String:
	return value if not value.strip_edges().is_empty() else "____________________"
