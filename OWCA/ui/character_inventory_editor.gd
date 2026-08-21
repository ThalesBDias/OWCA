class_name CharacterInventoryEditor
extends VBoxContainer

## Shared v0.7 loadout editor used by character creation and maintenance.
## It mutates only authoritative CharacterState through the inventory service;
## names, profiles, armour, and weight remain calculated projections.

signal inventory_changed(message: String)
signal creation_finished(message: String)

const InventoryServiceScript = preload("res://OWCA/scripts/character_inventory_service.gd")
const MODE_CREATION: StringName = &"creation"
const MODE_MAINTENANCE: StringName = &"maintenance"

var state: CharacterState
var calculation: Dictionary = {}
var character_repository: CharacterDataRepository
var presentation_mode: StringName = MODE_MAINTENANCE
var inventory_service: RefCounted = InventoryServiceScript.new()
var catalogue_search: LineEdit
var category_filter: OptionButton
var catalogue_selector: OptionButton
var catalogue_craftsmanship_selector: OptionButton
var catalogue_details: RichTextLabel
var _catalogue_matches: Array[Dictionary] = []
var owned_custodian_filter: String = "all"


func configure(character_state: CharacterState, result: Dictionary, repository: CharacterDataRepository, mode: StringName = MODE_MAINTENANCE) -> void:
	state = character_state
	calculation = result.duplicate(true)
	character_repository = repository
	presentation_mode = mode if mode in [MODE_CREATION, MODE_MAINTENANCE] else MODE_MAINTENANCE
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	add_theme_constant_override("separation", 10)
	if state == null or character_repository == null:
		add_child(_label("Load a character to manage its equipment."))
		return
	if presentation_mode == MODE_CREATION:
		_rebuild_creation()
		return
	_rebuild_maintenance()


func _rebuild_creation() -> void:
	var starting_equipment := VBoxContainer.new()
	starting_equipment.name = "CreationStartingEquipment"
	add_child(starting_equipment)
	_build_creation_starting_equipment(starting_equipment)
	var optional_equipment := _named_section("CreationOptionalEquipment", "ADD OPTIONAL EQUIPMENT")
	add_child(optional_equipment)
	_build_creation_optional_equipment(optional_equipment)
	var review := _named_section("CreationReviewFinalize", "REVIEW AND FINALIZE")
	add_child(review)
	_build_creation_review(review)


func _build_creation_review(parent: VBoxContainer) -> void:
	var inventory := calculation.get("inventory", {}) as Dictionary
	var encumbrance := inventory.get("encumbrance", {}) as Dictionary
	var encumbrance_status := "Weight partially known"
	match str(encumbrance.get("status", "partial")):
		"within_limit":
			encumbrance_status = "Within carrying limit"
		"encumbered":
			encumbrance_status = "Encumbered"
		"over_lift_limit":
			encumbrance_status = "Over lifting limit"
	parent.add_child(_label("Carried weight: %.2f / %.2f kg (%s)" % [
		float(encumbrance.get("known_weight_kg", 0.0)),
		float(encumbrance.get("carrying_limit_kg", 0.0)),
		encumbrance_status
	]))
	var armour := inventory.get("armour_by_location", {}) as Dictionary
	var armour_parts: Array[String] = []
	for location in ["Head", "Arms", "Body", "Legs"]:
		armour_parts.append("%s AP %d" % [location, int((armour.get(location, {}) as Dictionary).get("ap", 0))])
	parent.add_child(_label("  |  ".join(armour_parts)))
	var blocking_message := _creation_blocking_message()
	if not blocking_message.is_empty():
		parent.add_child(_label(blocking_message))
	var finalize := Button.new()
	finalize.name = "FinalizeAndContinueButton"
	finalize.text = "CONTINUE TO REVIEW" if state.loadout_state == CharacterState.LOADOUT_FINALIZED else "FINALIZE LOADOUT AND CONTINUE TO REVIEW"
	finalize.custom_minimum_size.y = 44
	finalize.disabled = not blocking_message.is_empty()
	finalize.pressed.connect(_finalize_and_continue)
	parent.add_child(finalize)


func _creation_blocking_message() -> String:
	if state.loadout_state == CharacterState.LOADOUT_FINALIZED:
		return ""
	if state.loadout_state == CharacterState.LOADOUT_UNPREPARED:
		return "Prepare your calculated starting equipment before continuing."
	var inventory := calculation.get("inventory", {}) as Dictionary
	if not (inventory.get("unresolved_items", []) as Array).is_empty():
		return "One owned item is no longer available in the equipment catalogue."
	if not bool(calculation.get("valid", false)):
		return "Resolve the remaining character choices before finalizing this loadout."
	var expected_grants := calculation.get("starting_equipment", []) as Array
	if expected_grants.is_empty():
		return "Starting equipment is not ready yet. Review the remaining character choices before continuing."
	if not bool(inventory_service.call("starting_loadout_matches", state, expected_grants)):
		return "Starting equipment changed after an earlier character choice. Restore it before finalizing."
	return ""


func _build_creation_starting_equipment(parent: VBoxContainer) -> void:
	if state.loadout_state == CharacterState.LOADOUT_UNPREPARED:
		parent.add_child(_label("Prepare your calculated starting equipment before continuing."))
		var prepare := Button.new()
		prepare.name = "PrepareStartingEquipmentButton"
		prepare.text = "PREPARE STARTING EQUIPMENT"
		prepare.custom_minimum_size.y = 44
		prepare.pressed.connect(_prepare_starting_loadout)
		parent.add_child(prepare)
		return
	var expected_grants := calculation.get("starting_equipment", []) as Array
	if expected_grants.is_empty():
		parent.add_child(_label("Starting equipment is not ready yet. Review the remaining character choices before continuing."))
		return
	var grants_match := bool(inventory_service.call("starting_loadout_matches", state, expected_grants))
	if not bool(calculation.get("valid", false)) and not grants_match:
		parent.add_child(_label("Resolve the remaining character choices before finalizing this loadout."))
		return
	if not grants_match:
		parent.add_child(_label("Starting equipment changed after an earlier character choice. Restore it before finalizing."))
		var restore := Button.new()
		restore.name = "RestoreStartingEquipmentButton"
		restore.text = "RESTORE STARTING EQUIPMENT"
		restore.custom_minimum_size.y = 44
		restore.pressed.connect(_rebuild_starting_loadout)
		parent.add_child(restore)
		return
	var grouped_items: Dictionary = {
		"WEAPONS": [],
		"ARMOUR": [],
		"AMMUNITION": [],
		"GEAR": []
	}
	var resolved_by_instance_id := _resolved_items_by_instance_id()
	for owned: Dictionary in state.owned_items:
		var instance_id := str(owned.get("instance_id", ""))
		if not _is_starting_instance(instance_id):
			continue
		var resolved := resolved_by_instance_id.get(instance_id, {}) as Dictionary
		var definition := character_repository.equipment_repository.get_item(str(owned.get("definition_id", "")))
		var category := str(resolved.get("category", definition.get("category", "")))
		(grouped_items[_creation_group_for_category(category)] as Array).append({
			"owned": owned,
			"resolved": resolved,
			"definition": definition
		})
	for group_name in ["WEAPONS", "ARMOUR", "AMMUNITION", "GEAR"]:
		var entries := grouped_items[group_name] as Array
		if entries.is_empty():
			continue
		parent.add_child(_heading(group_name))
		for entry_value: Variant in entries:
			var entry := entry_value as Dictionary
			var owned := entry.get("owned", {}) as Dictionary
			var resolved := entry.get("resolved", {}) as Dictionary
			var item := VBoxContainer.new()
			item.add_child(_label(_creation_item_label(owned, resolved)))
			parent.add_child(item)


func _build_creation_optional_equipment(parent: VBoxContainer) -> void:
	_build_catalogue_add_controls(parent, "ADD EQUIPMENT")
	var grouped_items: Dictionary = {
		"WEAPONS": [],
		"ARMOUR": [],
		"AMMUNITION": [],
		"GEAR": []
	}
	var resolved_by_instance_id := _resolved_items_by_instance_id()
	for owned: Dictionary in state.owned_items:
		var instance_id := str(owned.get("instance_id", ""))
		if _is_starting_instance(instance_id):
			continue
		var definition := character_repository.equipment_repository.get_item(str(owned.get("definition_id", "")))
		var resolved := resolved_by_instance_id.get(instance_id, definition) as Dictionary
		var category := str(resolved.get("category", definition.get("category", "")))
		(grouped_items[_creation_group_for_category(category)] as Array).append({
			"owned": owned,
			"resolved": definition if not definition.is_empty() else resolved
		})
	for group_name in ["WEAPONS", "ARMOUR", "AMMUNITION", "GEAR"]:
		var entries := grouped_items[group_name] as Array
		if entries.is_empty():
			continue
		parent.add_child(_heading(group_name))
		for entry_value: Variant in entries:
			var entry := entry_value as Dictionary
			parent.add_child(_build_creation_item_card(entry.get("owned", {}) as Dictionary, entry.get("resolved", {}) as Dictionary, true))


func _build_creation_item_card(owned: Dictionary, resolved: Dictionary, removable: bool) -> Control:
	var item := VBoxContainer.new()
	item.add_child(_label(_creation_item_label(owned, resolved)))
	if removable:
		var remove := Button.new()
		remove.name = "CreationOptionalRemoveButton"
		remove.text = "REMOVE"
		remove.pressed.connect(func() -> void:
			var result: Dictionary = inventory_service.call(
				"remove_item",
				state,
				str(owned.get("instance_id", "")),
				"Removed during character creation",
				_timestamp()
			)
			_emit_result(result)
		)
		item.add_child(remove)
	return item


func _resolved_items_by_instance_id() -> Dictionary:
	var resolved_by_instance_id: Dictionary = {}
	var inventory := calculation.get("inventory", {}) as Dictionary
	for item: Dictionary in inventory.get("items", []):
		resolved_by_instance_id[str(item.get("instance_id", ""))] = item
	return resolved_by_instance_id


func _creation_group_for_category(category: String) -> String:
	match category:
		"ranged_weapon", "melee_weapon", "grenade_missile":
			return "WEAPONS"
		"armour":
			return "ARMOUR"
		"ammunition":
			return "AMMUNITION"
		_:
			return "GEAR"


func _creation_item_label(owned: Dictionary, resolved: Dictionary) -> String:
	var name := str(resolved.get("name", owned.get("definition_id", "Item")))
	var quantity := int(owned.get("quantity", 1))
	if quantity > 1:
		return "%dx %s" % [quantity, name]
	return name


func _rebuild_maintenance() -> void:
	add_child(_heading("CHARACTER INVENTORY AND LOADOUT"))
	add_child(_label("Loadout: %s  |  Owned rows: %d  |  Audit events: %d" % [state.loadout_state, state.owned_items.size(), state.inventory_events.size()]))
	_build_comrade_controls()
	if state.loadout_state == CharacterState.LOADOUT_UNPREPARED:
		add_child(_label("Prepare the calculated starting grants once. This creates durable owned-item records and issue history."))
		var prepare := Button.new()
		prepare.text = "PREPARE STARTING LOADOUT"
		prepare.custom_minimum_size.y = 44
		prepare.disabled = not bool(calculation.get("valid", false))
		prepare.pressed.connect(_prepare_starting_loadout)
		add_child(prepare)
		return
	_build_metrics()
	var expected_grants := calculation.get("starting_equipment", []) as Array
	if not bool(inventory_service.call("starting_loadout_matches", state, expected_grants)):
		add_child(_label("Creation choices no longer match the materialized starting issue. Rebuild only the starting-grant records before finalization; later acquired gear and audit history are preserved."))
		var rebuild := Button.new()
		rebuild.text = "REBUILD STARTING GRANTS"
		rebuild.custom_minimum_size.y = 44
		rebuild.pressed.connect(_rebuild_starting_loadout)
		add_child(rebuild)
	_build_starting_grant_reconciliation()
	_build_catalogue_add_controls(self)
	_build_owned_items()
	_build_history()
	if state.loadout_state != CharacterState.LOADOUT_FINALIZED:
		var finalize := Button.new()
		finalize.text = "FINALIZE LOADOUT"
		finalize.custom_minimum_size.y = 44
		finalize.pressed.connect(_finalize_loadout)
		add_child(finalize)


func _build_comrade_controls() -> void:
	add_child(_heading("COMRADE CUSTODY"))
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = "Optional Comrade name"
	edit.text = str(state.comrade.get("name", ""))
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var save := Button.new()
	save.text = "SAVE COMRADE"
	save.pressed.connect(func() -> void:
		var result: Dictionary = inventory_service.call("set_comrade", state, edit.text)
		_emit_result(result)
	)
	row.add_child(save)
	add_child(row)


func _build_metrics() -> void:
	var inventory := calculation.get("inventory", {}) as Dictionary
	var encumbrance := inventory.get("encumbrance", {}) as Dictionary
	add_child(_heading("CARRIED WEIGHT AND ARMOUR"))
	var weight_text := "Known %.2f kg / Carry %.2f kg / Lift %.2f kg | %s" % [
		float(encumbrance.get("known_weight_kg", 0.0)),
		float(encumbrance.get("carrying_limit_kg", 0.0)),
		float(encumbrance.get("lifting_limit_kg", 0.0)),
		str(encumbrance.get("status", "partial")).replace("_", " ").capitalize()
	]
	add_child(_label(weight_text))
	add_child(_label("Capacity: Strength Bonus + Toughness Bonus lookup (Only War Core, pp. 36–37)."))
	var armour := inventory.get("armour_by_location", {}) as Dictionary
	var armour_parts: Array[String] = []
	for location in ["Head", "Arms", "Body", "Legs"]:
		armour_parts.append("%s AP %d" % [location, int((armour.get(location, {}) as Dictionary).get("ap", 0))])
	add_child(_label("  |  ".join(armour_parts)))
	var unknown := inventory.get("unknown_weight_items", []) as Array
	if not unknown.is_empty():
		add_child(_label("Partial total: %d carried item row(s) have no verified weight." % unknown.size()))


func _build_starting_grant_reconciliation() -> void:
	add_child(_heading("STARTING-GRANT RECONCILIATION"))
	for grant: Dictionary in state.starting_loadout:
		# Grant explanations can be long. Stacking the controls keeps every
		# action usable at the supported 960 px minimum without horizontal scroll.
		var row := VBoxContainer.new()
		var item_name := character_repository.equipment_repository.get_item_name(str(grant.get("definition_id", "")))
		var description := Label.new()
		description.text = "%dx %s (%s)" % [grant.get("quantity", 1), item_name, str(grant.get("scope", "per_character")).replace("_", " ")]
		description.custom_minimum_size.x = 230
		row.add_child(description)
		var selector := OptionButton.new()
		selector.name = "StartingGrantReconciliation"
		for value in CharacterState.STARTING_GRANT_RECONCILIATIONS:
			if value == "unresolved":
				continue
			selector.add_item(value.capitalize())
			selector.set_item_metadata(selector.item_count - 1, value)
			if value == str(grant.get("reconciliation", "unresolved")):
				selector.select(selector.item_count - 1)
		row.add_child(selector)
		var note := LineEdit.new()
		note.placeholder_text = "Required explanation if not present"
		note.text = str(grant.get("note", ""))
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(note)
		var apply := Button.new()
		apply.text = "RECONCILE"
		apply.pressed.connect(func() -> void:
			var result: Dictionary = inventory_service.call("reconcile_starting_grant", state, str(grant.get("grant_id", "")), str(selector.get_item_metadata(selector.selected)), note.text, _timestamp())
			_emit_result(result)
		)
		row.add_child(apply)
		add_child(row)


func _build_catalogue_add_controls(parent: VBoxContainer, add_button_label: String = "ADD TO CHARACTER") -> void:
	parent.add_child(_heading("ADD SUPPORTED EQUIPMENT"))
	var filters: Container = VBoxContainer.new() if presentation_mode == MODE_CREATION else HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	catalogue_search = LineEdit.new()
	catalogue_search.placeholder_text = "Search equipment name, ID, family, class, or quality..."
	catalogue_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalogue_search.text_changed.connect(func(_value: String) -> void: _refresh_catalogue_matches())
	filters.add_child(catalogue_search)
	category_filter = OptionButton.new()
	for pair in [["All categories", "all"], ["Ranged weapons", "ranged_weapon"], ["Melee weapons", "melee_weapon"], ["Grenades and missiles", "grenade_missile"], ["Ammunition", "ammunition"], ["Armour", "armour"], ["Wargear", "wargear"]]:
		category_filter.add_item(str(pair[0]))
		category_filter.set_item_metadata(category_filter.item_count - 1, str(pair[1]))
	category_filter.item_selected.connect(func(_index: int) -> void: _refresh_catalogue_matches())
	filters.add_child(category_filter)
	parent.add_child(filters)
	var add_row: Container = VBoxContainer.new() if presentation_mode == MODE_CREATION else HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	catalogue_selector = OptionButton.new()
	catalogue_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalogue_selector.item_selected.connect(func(_index: int) -> void: _catalogue_selection_changed())
	add_row.add_child(catalogue_selector)
	if presentation_mode == MODE_MAINTENANCE:
		catalogue_craftsmanship_selector = OptionButton.new()
		catalogue_craftsmanship_selector.name = "CatalogueCraftsmanshipSelector"
		for value in CharacterState.CRAFTSMANSHIP_VALUES:
			catalogue_craftsmanship_selector.add_item(value)
			catalogue_craftsmanship_selector.set_item_metadata(catalogue_craftsmanship_selector.item_count - 1, value)
			if value == "Common":
				catalogue_craftsmanship_selector.select(catalogue_craftsmanship_selector.item_count - 1)
		add_row.add_child(catalogue_craftsmanship_selector)
	else:
		catalogue_craftsmanship_selector = null
	var add_button := Button.new()
	add_button.text = add_button_label
	add_button.pressed.connect(_add_selected_item)
	add_row.add_child(add_button)
	parent.add_child(add_row)
	if presentation_mode == MODE_MAINTENANCE:
		catalogue_details = RichTextLabel.new()
		catalogue_details.bbcode_enabled = true
		catalogue_details.fit_content = true
		catalogue_details.custom_minimum_size.y = 76
		parent.add_child(catalogue_details)
	else:
		catalogue_details = null
	_refresh_catalogue_matches()


func _refresh_catalogue_matches() -> void:
	if catalogue_selector == null:
		return
	_catalogue_matches.clear()
	catalogue_selector.clear()
	var query := catalogue_search.text.strip_edges().to_lower() if catalogue_search != null else ""
	var category := "all"
	if category_filter != null and category_filter.item_count > 0:
		category = str(category_filter.get_item_metadata(category_filter.selected))
	for item: Dictionary in character_repository.equipment_repository.get_selectable_items():
		var item_category := str(item.get("category", ""))
		if item_category == "weapon_upgrade" or (category != "all" and item_category != category):
			continue
		if not query.is_empty() and query not in _search_text(item):
			continue
		_catalogue_matches.append(item)
	_catalogue_matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	for item: Dictionary in _catalogue_matches:
		var selector_text := str(item.get("name", item.get("id", "Item")))
		if presentation_mode == MODE_MAINTENANCE:
			selector_text = "%s  [%s]" % [
				selector_text,
				str(item.get("category", "")).replace("_", " ").capitalize()
			]
		catalogue_selector.add_item(selector_text)
	_catalogue_selection_changed()


func _catalogue_selection_changed() -> void:
	_refresh_catalogue_craftsmanship()
	_render_catalogue_details()


func _refresh_catalogue_craftsmanship() -> void:
	if catalogue_craftsmanship_selector == null:
		return
	var eligible := false
	if not _catalogue_matches.is_empty() and catalogue_selector.selected >= 0:
		eligible = str((_catalogue_matches[catalogue_selector.selected] as Dictionary).get("category", "")) in ["ranged_weapon", "melee_weapon"]
	_select_option_metadata(catalogue_craftsmanship_selector, "Common")
	catalogue_craftsmanship_selector.disabled = not eligible
	catalogue_craftsmanship_selector.tooltip_text = "Choose craftsmanship for this individual weapon." if eligible else "Craftsmanship modifiers apply only to individual ranged and melee weapons."


func _render_catalogue_details() -> void:
	if catalogue_details == null:
		return
	if _catalogue_matches.is_empty() or catalogue_selector.selected < 0:
		catalogue_details.text = "No supported definitions match the current filters."
		return
	var item := _catalogue_matches[catalogue_selector.selected]
	var lines: Array[String] = ["[b]%s[/b]  |  %s" % [item.get("name", "Item"), item.get("availability", "-")]]
	if item.has("weight_kg"):
		lines.append("Weight: %s kg" % item.get("weight_kg"))
	var profile := item.get("profile", {}) as Dictionary
	if not profile.is_empty():
		lines.append("Damage %s | Pen %s | Range %s | RoF %s | Magazine %s" % [profile.get("damage", "-"), profile.get("penetration", "-"), profile.get("range_m", profile.get("range_text", "-")), profile.get("rate_of_fire", "-"), profile.get("magazine", "-")])
		lines.append("Class %s | Reload %s | Qualities %s" % [
			profile.get("class", "-"),
			profile.get("reload", "-"),
			", ".join(profile.get("qualities", []) as Array) if not (profile.get("qualities", []) as Array).is_empty() else "None",
		])
	lines.append("Source: %s" % character_repository.equipment_repository.get_source_label(item.get("source", {}) as Dictionary))
	catalogue_details.text = "\n".join(lines)


func _build_owned_items() -> void:
	add_child(_heading("OWNED EQUIPMENT"))
	var filter := OptionButton.new()
	filter.name = "OwnedCustodianFilter"
	for pair in [["All custodians", "all"], ["Character", "character"], ["Squad", "squad"], ["Comrade", "comrade"]]:
		filter.add_item(str(pair[0]))
		filter.set_item_metadata(filter.item_count - 1, str(pair[1]))
		if str(pair[1]) == owned_custodian_filter:
			filter.select(filter.item_count - 1)
	filter.item_selected.connect(func(index: int) -> void:
		owned_custodian_filter = str(filter.get_item_metadata(index))
		_rebuild()
	)
	add_child(filter)
	if state.owned_items.is_empty():
		add_child(_label("No current equipment records."))
		return
	var inventory := calculation.get("inventory", {}) as Dictionary
	var resolved_by_id: Dictionary = {}
	for item: Dictionary in inventory.get("items", []):
		resolved_by_id[str(item.get("instance_id", ""))] = item
	for owned: Dictionary in state.owned_items:
		if owned_custodian_filter != "all" and str((owned.get("custodian", {}) as Dictionary).get("type", "")) != owned_custodian_filter:
			continue
		var resolved := resolved_by_id.get(str(owned.get("instance_id", "")), owned) as Dictionary
		add_child(_build_item_row(owned, resolved))


func _build_item_row(owned: Dictionary, resolved: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "%dx %s  |  %s  |  %s" % [owned.get("quantity", 1), resolved.get("name", owned.get("definition_id", "Item")), owned.get("craftsmanship", "Common"), (owned.get("custodian", {}) as Dictionary).get("type", "character")]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	# Owned-item forms deliberately use two vertical groups. Several selectors
	# include user-authored names and cannot be made safely narrow in one row.
	var controls := VBoxContainer.new()
	column.add_child(controls)
	var quantity := SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = 1 if str(resolved.get("category", "")) in ["ranged_weapon", "melee_weapon", "armour"] else 999
	quantity.value = int(owned.get("quantity", 1))
	quantity.custom_minimum_size.x = 80
	var starting_instance := _is_starting_instance(str(owned.get("instance_id", "")))
	quantity.editable = not starting_instance
	if starting_instance:
		quantity.tooltip_text = "Starting-grant quantity is fixed. Split/remove it or add later equipment separately."
	controls.add_child(quantity)
	var craftsmanship := OptionButton.new()
	craftsmanship.name = "CraftsmanshipSelector"
	for value in ["Poor", "Common", "Good", "Best"]:
		craftsmanship.add_item(value)
		craftsmanship.set_item_metadata(craftsmanship.item_count - 1, value)
		if value == str(owned.get("craftsmanship", "Common")):
			craftsmanship.select(craftsmanship.item_count - 1)
	var weapon_category := str(resolved.get("category", "")) in ["ranged_weapon", "melee_weapon"]
	craftsmanship.disabled = not weapon_category
	if not weapon_category:
		_select_option_metadata(craftsmanship, "Common")
		craftsmanship.tooltip_text = "Craftsmanship modifiers apply only to individual ranged and melee weapons."
	else:
		craftsmanship.tooltip_text = "Craftsmanship belongs to this individual owned weapon."
	controls.add_child(craftsmanship)
	var location := OptionButton.new()
	for value in CharacterState.ITEM_LOCATIONS:
		location.add_item(value.capitalize())
		location.set_item_metadata(location.item_count - 1, value)
		if value == str(owned.get("location", "carried")):
			location.select(location.item_count - 1)
	controls.add_child(location)
	var custodian := OptionButton.new()
	custodian.name = "CustodianSelector"
	for pair in [["Character", "character", ""], ["Squad", "squad", ""]]:
		custodian.add_item(str(pair[0]))
		custodian.set_item_metadata(custodian.item_count - 1, { "type": pair[1], "id": pair[2] })
	if not state.comrade.is_empty():
		custodian.add_item("Comrade: %s" % state.comrade.get("name", "Comrade"))
		custodian.set_item_metadata(custodian.item_count - 1, { "type": "comrade", "id": state.comrade.get("id", "") })
	var current_custodian := owned.get("custodian", {}) as Dictionary
	for index in custodian.item_count:
		if (custodian.get_item_metadata(index) as Dictionary) == current_custodian:
			custodian.select(index)
	controls.add_child(custodian)
	var details_row := VBoxContainer.new()
	column.add_child(details_row)
	var origin := OptionButton.new()
	origin.name = "OriginSelector"
	for value in CharacterState.ITEM_ORIGINS:
		origin.add_item(value.replace("_", " ").capitalize())
		origin.set_item_metadata(origin.item_count - 1, value)
		if value == str(owned.get("origin", "standard_issue")):
			origin.select(origin.item_count - 1)
	origin.disabled = starting_instance
	if starting_instance:
		origin.tooltip_text = "Starting-grant provenance is fixed."
	details_row.add_child(origin)
	var note := LineEdit.new()
	note.placeholder_text = "Short item note"
	note.text = str(owned.get("note", ""))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_row.add_child(note)
	if int(owned.get("quantity", 1)) > 1 and str(resolved.get("category", "")) not in ["ranged_weapon", "melee_weapon", "armour"]:
		var split := Button.new()
		split.text = "SPLIT ONE"
		split.pressed.connect(func() -> void:
			var result: Dictionary = inventory_service.call("split_stack", state, character_repository.equipment_repository, str(owned.get("instance_id", "")), 1, "Split by player", _timestamp())
			_emit_result(result)
		)
		details_row.add_child(split)
	var save := Button.new()
	save.text = "APPLY"
	save.pressed.connect(func() -> void:
		var instance_id := str(owned.get("instance_id", ""))
		var update: Dictionary = inventory_service.call("update_item", state, character_repository.equipment_repository, instance_id, int(quantity.value), str(craftsmanship.get_item_metadata(craftsmanship.selected)), str(location.get_item_metadata(location.selected)), note.text, "Player loadout edit", _timestamp(), str(origin.get_item_metadata(origin.selected)))
		if int(update.get("error", ERR_INVALID_DATA)) == OK:
			var owner := custodian.get_item_metadata(custodian.selected) as Dictionary
			update = inventory_service.call("transfer_item", state, instance_id, str(owner.get("type", "character")), str(owner.get("id", "")), "Player custody edit", _timestamp())
		_emit_result(update)
	)
	details_row.add_child(save)
	var remove := Button.new()
	remove.text = "REMOVE"
	remove.pressed.connect(func() -> void:
		var result: Dictionary = inventory_service.call("remove_item", state, str(owned.get("instance_id", "")), "Removed by player", _timestamp())
		_emit_result(result)
	)
	details_row.add_child(remove)
	if weapon_category:
		column.add_child(_build_weapon_modification_panel(owned, resolved))
	return panel


func _build_weapon_modification_panel(owned: Dictionary, resolved: Dictionary) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.name = "WeaponModificationPanel"
	panel.add_theme_constant_override("separation", 6)
	panel.add_child(_heading("WEAPON CRAFTSMANSHIP AND MODIFICATIONS"))
	var weapon := resolved.get("weapon", {}) as Dictionary
	if weapon.is_empty():
		weapon = WeaponModificationCalculator.new().calculate(owned, character_repository.equipment_repository)
	var comparison := _label(_weapon_profile_comparison(weapon))
	comparison.name = "WeaponProfileComparison"
	panel.add_child(comparison)
	var breakdown := _label(_weapon_calculation_breakdown(weapon))
	breakdown.name = "WeaponCalculationBreakdown"
	panel.add_child(breakdown)

	var installed := weapon.get("installed_modifications", []) as Array
	if installed.is_empty():
		panel.add_child(_label("Installed upgrades: None"))
	else:
		panel.add_child(_label("INSTALLED UPGRADES"))
		for modification_value: Variant in installed:
			var modification := modification_value as Dictionary
			var installed_row := VBoxContainer.new()
			installed_row.add_child(_label(str(modification.get("name", modification.get("id", "Upgrade")))))
			var remove := Button.new()
			remove.name = "RemoveModificationButton"
			remove.text = "REMOVE UPGRADE"
			remove.pressed.connect(_remove_weapon_modification.bind(
				str(owned.get("instance_id", "")),
				str(modification.get("id", ""))
			))
			installed_row.add_child(remove)
			panel.add_child(installed_row)

	panel.add_child(_label("AVAILABLE UPGRADES"))
	var selector := OptionButton.new()
	selector.name = "ModificationSelector"
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var first_compatible := -1
	var installed_ids := owned.get("modification_ids", []) as Array
	for modification: Dictionary in character_repository.equipment_repository.get_weapon_upgrades():
		var modification_id := str(modification.get("id", ""))
		if modification_id in installed_ids:
			continue
		var evaluation := WeaponModificationCalculator.new().evaluate_install(owned, modification_id, character_repository.equipment_repository)
		var compatible := bool(evaluation.get("compatible", false))
		var text := str(modification.get("name", modification_id))
		if not compatible:
			text += " — %s" % evaluation.get("message", "Incompatible")
		selector.add_item(text)
		var index := selector.item_count - 1
		selector.set_item_metadata(index, modification_id)
		selector.set_item_disabled(index, not compatible)
		if compatible and first_compatible < 0:
			first_compatible = index
	if first_compatible >= 0:
		selector.select(first_compatible)
	panel.add_child(selector)
	var compatibility_details := _label("")
	compatibility_details.name = "ModificationCompatibilityDetails"
	panel.add_child(compatibility_details)
	var install := Button.new()
	install.name = "InstallModificationButton"
	install.text = "INSTALL SELECTED UPGRADE"
	install.disabled = first_compatible < 0
	install.pressed.connect(func() -> void:
		if selector.selected < 0 or selector.is_item_disabled(selector.selected):
			return
		var result: Dictionary = inventory_service.call(
			"install_modification",
			state,
			character_repository.equipment_repository,
			str(owned.get("instance_id", "")),
			str(selector.get_item_metadata(selector.selected)),
			"Installed by player",
			_timestamp()
		)
		_emit_result(result)
	)
	selector.item_selected.connect(func(index: int) -> void:
		_update_modification_selection(selector, install, compatibility_details, owned, index)
	)
	panel.add_child(install)
	if selector.item_count == 0:
		compatibility_details.text = "Every supported upgrade is already installed."
	elif first_compatible >= 0:
		_update_modification_selection(selector, install, compatibility_details, owned, first_compatible)
	else:
		compatibility_details.text = "No remaining supported upgrade is compatible with this weapon. Incompatible choices remain listed above with their reason."
	return panel


func _update_modification_selection(selector: OptionButton, install: Button, details: Label, owned: Dictionary, index: int) -> void:
	if index < 0 or index >= selector.item_count:
		install.disabled = true
		return
	var modification_id := str(selector.get_item_metadata(index))
	var evaluation := WeaponModificationCalculator.new().evaluate_install(owned, modification_id, character_repository.equipment_repository)
	var compatible := bool(evaluation.get("compatible", false))
	details.text = "Compatible with this weapon." if compatible else str(evaluation.get("message", "This upgrade is incompatible."))
	selector.tooltip_text = details.text
	install.disabled = not compatible


func _remove_weapon_modification(instance_id: String, modification_id: String) -> void:
	var result: Dictionary = inventory_service.call(
		"remove_modification",
		state,
		character_repository.equipment_repository,
		instance_id,
		modification_id,
		"Removed by player",
		_timestamp()
	)
	_emit_result(result)


func _weapon_profile_comparison(weapon: Dictionary) -> String:
	if not bool(weapon.get("valid", false)):
		return "Weapon profile unavailable: %s" % weapon.get("message", "calculation failed")
	return "Base: %s\nFinal: %s" % [
		_weapon_profile_summary(weapon.get("base_profile", {}) as Dictionary, float(weapon.get("base_weight_kg", 0.0))),
		_weapon_profile_summary(weapon.get("final_profile", {}) as Dictionary, float(weapon.get("final_weight_kg", 0.0)))
	]


func _weapon_profile_summary(profile: Dictionary, weight_kg: float) -> String:
	var range_value: Variant = profile.get("range_m", profile.get("range_text", "-"))
	var qualities := profile.get("qualities", []) as Array
	return "Damage %s | Pen %s | Range %s | Magazine %s | Weight %.2f kg | Qualities %s" % [
		profile.get("damage", "-"),
		profile.get("penetration", "-"),
		range_value,
		profile.get("magazine", "-"),
		weight_kg,
		", ".join(qualities) if not qualities.is_empty() else "None"
	]


func _weapon_calculation_breakdown(weapon: Dictionary) -> String:
	if not bool(weapon.get("valid", false)):
		return str(weapon.get("message", "Weapon profile calculation failed."))
	var lines: Array[String] = []
	for step_value: Variant in weapon.get("steps", []):
		var step := step_value as Dictionary
		lines.append("%s: %s" % [step.get("label", "Rule"), step.get("summary", "Applied")])
	if lines.is_empty():
		lines.append("Common craftsmanship; no profile-changing upgrades installed.")
	return "\n".join(lines)


func _build_history() -> void:
	add_child(_heading("RECENT INVENTORY HISTORY"))
	if state.inventory_events.is_empty():
		add_child(_label("No inventory events recorded."))
		return
	var start := maxi(0, state.inventory_events.size() - 8)
	for index in range(state.inventory_events.size() - 1, start - 1, -1):
		var event := state.inventory_events[index]
		var name := character_repository.equipment_repository.get_item_name(str(event.get("definition_id", "")))
		add_child(_label("%s | %s | %dx %s | %s" % [event.get("timestamp_utc", ""), str(event.get("type", "")).capitalize(), event.get("quantity", 1), name, event.get("reason", "")]))


func _prepare_starting_loadout() -> void:
	var grants := calculation.get("starting_equipment", calculation.get("equipment", [])) as Array
	var result: Dictionary = inventory_service.call("materialize_starting_loadout", state, grants, character_repository.equipment_repository, _timestamp())
	_emit_result(result)


func _finalize_loadout() -> void:
	var result: Dictionary = inventory_service.call("finalize_loadout", state, character_repository.equipment_repository, calculation.get("starting_equipment", []) as Array)
	_emit_result(result)


func _finalize_and_continue() -> void:
	if state.loadout_state == CharacterState.LOADOUT_FINALIZED:
		creation_finished.emit("Loadout is ready for review.")
		return
	var result: Dictionary = inventory_service.call(
		"finalize_loadout",
		state,
		character_repository.equipment_repository,
		calculation.get("starting_equipment", []) as Array
	)
	if int(result.get("error", ERR_INVALID_DATA)) == OK:
		creation_finished.emit(str(result.get("message", "Loadout finalized.")))
	else:
		_emit_result(result)


func _rebuild_starting_loadout() -> void:
	var result: Dictionary = inventory_service.call("rebuild_starting_loadout", state, calculation.get("starting_equipment", []) as Array, character_repository.equipment_repository, _timestamp())
	_emit_result(result)


func _add_selected_item() -> void:
	if _catalogue_matches.is_empty() or catalogue_selector.selected < 0:
		return
	var definition := _catalogue_matches[catalogue_selector.selected]
	var craftsmanship := "Common"
	if presentation_mode == MODE_MAINTENANCE and catalogue_craftsmanship_selector != null and not catalogue_craftsmanship_selector.disabled:
		craftsmanship = str(catalogue_craftsmanship_selector.get_item_metadata(catalogue_craftsmanship_selector.selected))
	var result: Dictionary = inventory_service.call("add_item", state, character_repository.equipment_repository, str(definition.get("id", "")), 1, craftsmanship, "later_issue", "carried", "character", "", "Added by player", _timestamp())
	_emit_result(result)


func _emit_result(result: Dictionary) -> void:
	inventory_changed.emit(str(result.get("message", "Inventory updated.")))


func _search_text(item: Dictionary) -> String:
	var profile := item.get("profile", {}) as Dictionary
	return " ".join([item.get("id", ""), item.get("name", ""), item.get("category", ""), item.get("family", ""), profile.get("class", ""), " ".join(profile.get("qualities", []) as Array)]).to_lower()


func _is_starting_instance(instance_id: String) -> bool:
	for grant: Dictionary in state.starting_loadout:
		if instance_id in (grant.get("issued_instance_ids", []) as Array):
			return true
	return false


func _timestamp() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


func _select_option_metadata(selector: OptionButton, metadata: Variant) -> void:
	for index in selector.item_count:
		if selector.get_item_metadata(index) == metadata:
			selector.select(index)
			return


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	return label


func _named_section(node_name: StringName, title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = node_name
	section.add_child(_heading(title))
	return section


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
