class_name CharacterInventoryEditor
extends VBoxContainer

## Shared v0.7 loadout editor used by character creation and maintenance.
## It mutates only authoritative CharacterState through the inventory service;
## names, profiles, armour, and weight remain calculated projections.

signal inventory_changed(message: String)

const InventoryServiceScript = preload("res://OWCA/scripts/character_inventory_service.gd")

var state: CharacterState
var calculation: Dictionary = {}
var character_repository: CharacterDataRepository
var inventory_service: RefCounted = InventoryServiceScript.new()
var catalogue_search: LineEdit
var category_filter: OptionButton
var catalogue_selector: OptionButton
var catalogue_details: RichTextLabel
var _catalogue_matches: Array[Dictionary] = []
var owned_custodian_filter: String = "all"


func configure(character_state: CharacterState, result: Dictionary, repository: CharacterDataRepository) -> void:
	state = character_state
	calculation = result.duplicate(true)
	character_repository = repository
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	add_theme_constant_override("separation", 10)
	if state == null or character_repository == null:
		add_child(_label("Load a character to manage its equipment."))
		return
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
	_build_catalogue_add_controls()
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


func _build_catalogue_add_controls() -> void:
	add_child(_heading("ADD SUPPORTED EQUIPMENT"))
	var filters := HBoxContainer.new()
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
	add_child(filters)
	var add_row := HBoxContainer.new()
	catalogue_selector = OptionButton.new()
	catalogue_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalogue_selector.item_selected.connect(func(_index: int) -> void: _render_catalogue_details())
	add_row.add_child(catalogue_selector)
	var add_button := Button.new()
	add_button.text = "ADD TO CHARACTER"
	add_button.pressed.connect(_add_selected_item)
	add_row.add_child(add_button)
	add_child(add_row)
	catalogue_details = RichTextLabel.new()
	catalogue_details.bbcode_enabled = true
	catalogue_details.fit_content = true
	catalogue_details.custom_minimum_size.y = 76
	add_child(catalogue_details)
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
	for item: Dictionary in character_repository.equipment_repository.get_items():
		var item_category := str(item.get("category", ""))
		if item_category == "weapon_upgrade" or (category != "all" and item_category != category):
			continue
		if not query.is_empty() and query not in _search_text(item):
			continue
		_catalogue_matches.append(item)
	_catalogue_matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	for item: Dictionary in _catalogue_matches:
		catalogue_selector.add_item("%s  [%s]" % [item.get("name", item.get("id", "Item")), str(item.get("category", "")).replace("_", " ").capitalize()])
	_render_catalogue_details()


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
	controls.add_child(craftsmanship)
	var location := OptionButton.new()
	for value in CharacterState.ITEM_LOCATIONS:
		location.add_item(value.capitalize())
		location.set_item_metadata(location.item_count - 1, value)
		if value == str(owned.get("location", "carried")):
			location.select(location.item_count - 1)
	controls.add_child(location)
	var custodian := OptionButton.new()
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
	return panel


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


func _rebuild_starting_loadout() -> void:
	var result: Dictionary = inventory_service.call("rebuild_starting_loadout", state, calculation.get("starting_equipment", []) as Array, character_repository.equipment_repository, _timestamp())
	_emit_result(result)


func _add_selected_item() -> void:
	if _catalogue_matches.is_empty() or catalogue_selector.selected < 0:
		return
	var definition := _catalogue_matches[catalogue_selector.selected]
	var result: Dictionary = inventory_service.call("add_item", state, character_repository.equipment_repository, str(definition.get("id", "")), 1, str(definition.get("craftsmanship", "Common")), "later_issue", "carried", "character", "", "Added by player", _timestamp())
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


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	return label


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
