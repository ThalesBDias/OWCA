extends SceneTree

## Run with: godot --headless --path . --script res://OWCA/tests/character_calculator_test.gd

var _failures := 0


func _init() -> void:
	var regiment_repository := RegimentDataRepository.new()
	_assert_equal(regiment_repository.load_data(), OK, "regiment catalog loads")
	var character_repository := CharacterDataRepository.new()
	_assert_equal(character_repository.load_data(), OK, "Guardsman Speciality catalog loads")
	_assert_equal(character_repository.get_advancement_entries("characteristics").size(), 9, "nine Characteristic advancement tracks")
	_assert_true(character_repository.get_advancement_entries("skills").size() >= 40, "Core Skill advancement catalog loads")
	var talent_catalog := character_repository.get_advancement_entries("talents")
	_assert_equal(talent_catalog.size(), 124, "complete Core Talent catalog and supported specialisations load")
	for talent_id: Variant in talent_catalog:
		_assert_true(not str((talent_catalog[talent_id] as Dictionary).get("summary", "")).is_empty(), "Talent '%s' has a brief effect summary" % talent_id)
	for expected_talent in ["berserk_charge", "combat_master", "never_die", "warp_lock", "whirlwind_of_death"]:
		_assert_true(talent_catalog.has(expected_talent), "complete catalog includes %s" % expected_talent)
	_assert_equal(character_repository.get_specialities().size(), 5, "five Core Guardsman Specialities")
	_assert_speciality(character_repository, "heavy_gunner", 10, 4)
	_assert_speciality(character_repository, "medic", 8, 3)
	_assert_speciality(character_repository, "operator", 6, 2)
	_assert_speciality(character_repository, "sergeant", 10, 3)
	_assert_speciality(character_repository, "weapon_specialist", 8, 6)

	var regiment_state := RegimentState.new()
	regiment_state.load_example()
	var state := CharacterState.new()
	state.character_name = "Varanox Operator"
	state.player_name = "Test Player"
	state.set_regiment(regiment_state.to_dict(), str(regiment_repository.data.get("content_version", "")))
	_fill_base_characteristics(state, 30)
	state.set_speciality("operator")
	state.set_wounds_roll(3)
	state.set_fate_roll(8)
	state.set_choice("regiment", "hive_characteristic_1", "agility")
	state.set_choice("regiment", "hive_characteristic_2", "fellowship")
	state.set_choice("regiment", "hive_urban_violence", "paranoia")
	state.set_choice("regiment", "close_order_talent", "combat_formation")
	state.set_choice("speciality", "operator_knowledge_skill", "common_lore_tech")
	state.set_choice("speciality", "operator_weapon_training", "las")

	var calculator := CharacterCalculator.new()
	var result := calculator.calculate(state, regiment_repository, character_repository)
	_assert_true(result["valid"], "complete Varanox Operator is valid")
	_assert_equal(result["speciality_name"], "Operator", "Operator selected")
	_assert_equal(result["characteristics"]["Agility"], 41, "base, regiment choice, regiment type, and Speciality combine")
	_assert_equal(result["characteristics"]["Fellowship"], 33, "second Hive choice combines")
	_assert_equal(result["characteristics"]["Toughness"], 27, "Light Infantry penalty combines")
	_assert_equal(result["characteristic_bonuses"]["Agility"], 4, "Characteristic Bonus")
	_assert_equal(result["wounds"], 8, "Operator Wounds with Hive modifier")
	_assert_equal(result["fate_points"], 2, "Fate lookup")
	_assert_equal(result["movement"], { "half": 4, "full": 8, "charge": 12, "run": 24 }, "Agility movement")
	_assert_equal(result["xp_budget"], 600, "Guardsman starting XP")
	_assert_true(_entry_exists(result["skills"], "common_lore_tech"), "Operator chosen Skill")
	_assert_true(_entry_exists(result["talents"], "technical_knock"), "Operator fixed Talent")
	_assert_true(_entry_exists(result["talents"], "weapon_training_las"), "Operator chosen Weapon Training")
	_assert_true(_entry_exists(result["equipment"], "auspex_scanner"), "Operator equipment")
	_assert_true("speciality_issue" in (_entry(result["equipment"], "auspex_scanner").get("origins", []) as Array), "Speciality equipment retains its issue origin")
	_assert_true("standard_issue" in (_entry(result["equipment"], "lascarbine").get("origins", []) as Array), "regimental equipment retains its issue origin")

	var incomplete := CharacterState.new()
	incomplete.set_regiment(regiment_state.to_dict(), str(regiment_repository.data.get("content_version", "")))
	var incomplete_result := calculator.calculate(incomplete, regiment_repository, character_repository)
	_assert_true(not incomplete_result["valid"], "incomplete character is invalid")
	_assert_true((incomplete_result["errors"] as Array).size() >= 3, "missing core stages are reported")

	var weapon_state := CharacterState.new()
	weapon_state.set_regiment(regiment_state.to_dict(), str(regiment_repository.data.get("content_version", "")))
	_fill_base_characteristics(weapon_state, 30)
	weapon_state.set_speciality("weapon_specialist")
	weapon_state.set_wounds_roll(5)
	weapon_state.set_fate_roll(10)
	_resolve_varanox_choices(weapon_state)
	weapon_state.set_choice("speciality", "weapon_specialist_characteristic", "ballistic_skill")
	weapon_state.set_choice("speciality", "weapon_specialist_field_skill", "athletics")
	weapon_state.set_choice("speciality", "weapon_specialist_talent", "rapid_reload")
	weapon_state.set_choice("speciality", "weapon_specialist_trainings", "las", true, 3)
	var partial_weapon_result := calculator.calculate(weapon_state, regiment_repository, character_repository)
	_assert_true(not partial_weapon_result["valid"], "partial choose-three package remains unresolved")
	_assert_true(_entry_exists(partial_weapon_result["talents"], "weapon_training_las"), "partial multi-choice grants appear in the live result")
	weapon_state.set_choice("speciality", "weapon_specialist_trainings", "launcher", true, 3)
	weapon_state.set_choice("speciality", "weapon_specialist_trainings", "low_tech", true, 3)
	weapon_state.set_choice("speciality", "weapon_specialist_grenades", "frag")
	weapon_state.set_choice("speciality", "weapon_specialist_weapon", "lasgun")
	var weapon_result := calculator.calculate(weapon_state, regiment_repository, character_repository)
	_assert_true(weapon_result["valid"], "Weapon Specialist three-selection choice resolves")
	_assert_equal(weapon_result["characteristics"]["Ballistic Skill"], 35, "Weapon Specialist characteristic choice")
	_assert_equal(_equipment_quantity(weapon_result["equipment"], "frag_grenade"), 6, "Speciality grenades merge with regiment kit")
	_assert_equal((_entry(weapon_result["equipment"], "frag_grenade").get("origin_quantities", {}) as Dictionary).get("standard_issue"), 2, "merged grenades retain their standard-issue quantity")
	_assert_equal((_entry(weapon_result["equipment"], "frag_grenade").get("origin_quantities", {}) as Dictionary).get("speciality_issue"), 4, "merged grenades retain their Speciality-issue quantity")
	var good_lasgun := _entry(weapon_result["equipment"], "m36_lasgun")
	_assert_true(not good_lasgun.is_empty(), "Weapon Specialist Good lasgun uses the base definition")
	_assert_equal(good_lasgun.get("craftsmanship"), "Good", "Weapon Specialist Good lasgun carries individual craftsmanship")
	_assert_true(not _entry_exists(weapon_result["equipment"], "lasgun_good"), "new calculation does not emit the legacy Good-lasgun alias")

	# A duplicate Aptitude generates a required replacement choice.
	var aptitude_regiment := RegimentState.new()
	aptitude_regiment.selections = {
		"home_world": ["imperial_world"],
		"commander": ["fixed"],
		"regiment_type": ["line_infantry"],
		"training_doctrine": ["sharpshooters"],
		"equipment_doctrine": []
	}
	var aptitude_state := CharacterState.new()
	aptitude_state.set_regiment(aptitude_regiment.to_dict(), str(regiment_repository.data.get("content_version", "")))
	_fill_base_characteristics(aptitude_state, 30)
	aptitude_state.set_speciality("operator")
	aptitude_state.set_wounds_roll(3)
	aptitude_state.set_fate_roll(7)
	aptitude_state.set_choice("regiment", "imperial_other_characteristic", "strength")
	aptitude_state.set_choice("speciality", "operator_knowledge_skill", "common_lore_tech")
	aptitude_state.set_choice("speciality", "operator_weapon_training", "las")
	var aptitude_result := calculator.calculate(aptitude_state, regiment_repository, character_repository)
	_assert_true(not aptitude_result["valid"], "duplicate Aptitude requires a replacement")
	_assert_true(_unresolved_prompt_contains(aptitude_result["unresolved_choices"], "Replacement for duplicate Ballistic Skill"), "duplicate Aptitude choice is exposed")
	aptitude_state.set_choice("speciality", "duplicate_aptitude_ballistic_skill_1", "strength")
	aptitude_result = calculator.calculate(aptitude_state, regiment_repository, character_repository)
	_assert_true(aptitude_result["valid"], "duplicate Aptitude replacement resolves")
	_assert_true("Strength" in aptitude_result["aptitudes"], "replacement Aptitude is applied")

	# XP purchases use Aptitude matches, existing Skill ranks, prerequisites, and the ordered ledger.
	var xp_state := CharacterState.new()
	xp_state.set_regiment(regiment_state.to_dict(), str(regiment_repository.data.get("content_version", "")))
	_fill_base_characteristics(xp_state, 40)
	xp_state.set_speciality("operator")
	xp_state.set_wounds_roll(3)
	xp_state.set_fate_roll(8)
	_resolve_varanox_choices(xp_state)
	xp_state.set_choice("speciality", "operator_knowledge_skill", "common_lore_tech")
	xp_state.set_choice("speciality", "operator_weapon_training", "las")
	var xp_result := calculator.calculate(xp_state, regiment_repository, character_repository)
	_assert_true(xp_result["advancement_ready"], "complete character can spend XP")
	var enemy_option := _entry_by_id(xp_result["advancement_options"], "talent:enemy")
	_assert_true(not enemy_option["purchase_supported"], "GM-awarded Enemy Talent is listed but not purchasable")
	_assert_true(not enemy_option["available"], "unsupported specialist Talent is disabled")
	_assert_true(not str(enemy_option["summary"]).is_empty(), "Talent option exposes a brief effect summary")
	var psychic_power_option := _entry_by_id(xp_result["advancement_options"], "talent:psychic_power")
	_assert_true(not psychic_power_option["prerequisites_met"], "Aptitude prerequisite is evaluated")
	_assert_true("Psyker" in psychic_power_option["missing_prerequisites"], "missing Aptitude is explained")
	var step_aside_option := _entry_by_id(xp_result["advancement_options"], "talent:step_aside")
	_assert_true(not step_aside_option["prerequisites_met"], "Dodge-or-Parry prerequisite starts unmet without either Skill")
	_assert_true("Dodge or Parry" in step_aside_option["missing_prerequisites"], "alternative Skill prerequisite is explained")
	var step_state := CharacterState.new()
	_assert_equal(step_state.from_dict(xp_state.to_dict()), OK, "clone alternative Skill prerequisite state")
	step_state.purchase_advance("skill:dodge")
	var step_result := calculator.calculate(step_state, regiment_repository, character_repository)
	_assert_true(_entry_by_id(step_result["advancement_options"], "talent:step_aside")["prerequisites_met"], "Dodge-or-Parry prerequisite accepts either trained Skill")
	var weapon_tech_before := _entry_by_id(xp_result["advancement_options"], "talent:weapon_tech")
	_assert_true(not weapon_tech_before["available"], "Weapon-Tech is locked before Tech-Use +10")
	xp_state.purchase_advance("skill:tech_use")
	xp_result = calculator.calculate(xp_state, regiment_repository, character_repository)
	_assert_equal(xp_result["xp_spent"], 200, "two-Aptitude Trained Skill costs 200 XP")
	_assert_equal(_entry_by_id(xp_result["skills"], "tech_use")["rank"], 2, "starting Known Skill advances to Trained +10")
	var weapon_tech_option := _entry_by_id(xp_result["advancement_options"], "talent:weapon_tech")
	_assert_true(weapon_tech_option["available"], "Tech-Use +10 unlocks Weapon-Tech")
	_assert_equal(weapon_tech_option["cost"], 200, "two-Aptitude Tier 1 Talent costs 200 XP")
	xp_state.purchase_advance("talent:weapon_tech")
	xp_result = calculator.calculate(xp_state, regiment_repository, character_repository)
	_assert_true(xp_result["valid"], "ordered prerequisite purchases remain valid")
	_assert_equal(xp_result["xp_spent"], 400, "XP ledger totals purchases")
	_assert_equal(xp_result["xp_remaining"], 200, "XP ledger reports remaining budget")
	_assert_true(_entry_exists(xp_result["talents"], "weapon_tech"), "purchased Talent joins calculated Talents")
	var next_tech_use := _entry_by_id(xp_result["advancement_options"], "skill:tech_use")
	_assert_equal(next_tech_use["cost"], 300, "next Skill rank uses the Experienced cost column")
	_assert_true(not next_tech_use["available"], "unaffordable next rank is disabled")

	var characteristic_state := CharacterState.new()
	_assert_equal(characteristic_state.from_dict(xp_state.to_dict()), OK, "clone XP test state")
	characteristic_state.clear_advances()
	characteristic_state.purchase_advance("characteristic:intelligence")
	var characteristic_result := calculator.calculate(characteristic_state, regiment_repository, character_repository)
	_assert_equal(characteristic_result["xp_spent"], 250, "one-Aptitude Simple Characteristic advance costs 250 XP")
	_assert_equal(characteristic_result["characteristics"]["Intelligence"], 45, "Characteristic purchase adds 5")
	var next_intelligence := _entry_by_id(characteristic_result["advancement_options"], "characteristic:intelligence")
	_assert_equal(next_intelligence["cost"], 500, "next Characteristic purchase is Intermediate")
	_assert_true(not next_intelligence["available"], "unaffordable Intermediate advance is disabled")

	var wounds_state := CharacterState.new()
	_assert_equal(wounds_state.from_dict(xp_state.to_dict()), OK, "clone repeatable Talent state")
	wounds_state.clear_advances()
	wounds_state.purchase_advance("talent:sound_constitution")
	wounds_state.purchase_advance("talent:sound_constitution")
	var wounds_result := calculator.calculate(wounds_state, regiment_repository, character_repository)
	_assert_equal(wounds_result["xp_spent"], 600, "repeatable one-Aptitude Tier 1 Talent costs 300 XP each")
	_assert_equal(wounds_result["wounds"], 10, "Sound Constitution purchases add to maximum Wounds")
	_assert_equal(_entry_by_id(wounds_result["talents"], "sound_constitution")["count"], 2, "repeatable Talent keeps its purchase count")

	var invalid_order := CharacterState.new()
	_assert_equal(invalid_order.from_dict(xp_state.to_dict()), OK, "clone ordered ledger")
	invalid_order.remove_advance_at(0)
	var invalid_order_result := calculator.calculate(invalid_order, regiment_repository, character_repository)
	_assert_true(not invalid_order_result["valid"], "removing a prerequisite invalidates the dependent purchase")
	_assert_equal(invalid_order_result["xp_spent"], 0, "invalid dependent purchase spends no XP")

	var persistence := CharacterPersistence.new()
	var save_result := persistence.save_character("user://owca_character_roundtrip.json", xp_state, xp_result, character_repository)
	_assert_equal(save_result["error"], OK, "save character JSON")
	var loaded := CharacterState.new()
	var load_result := persistence.load_character("user://owca_character_roundtrip.json", loaded)
	_assert_equal(load_result["error"], OK, "load character JSON")
	var loaded_result := calculator.calculate(loaded, regiment_repository, character_repository)
	_assert_true(loaded_result["valid"], "loaded character remains valid")
	_assert_equal(loaded_result["xp_spent"], 400, "character save/load preserves XP purchases")
	_assert_equal(loaded.purchased_advances, xp_state.purchased_advances, "ordered XP ledger round-trips")
	var legacy_data := state.to_dict()
	legacy_data["version"] = 1
	legacy_data.erase("purchased_advances")
	var legacy_state := CharacterState.new()
	_assert_equal(legacy_state.from_dict(legacy_data), OK, "version 1 character state remains loadable")
	_assert_true(legacy_state.purchased_advances.is_empty(), "legacy character starts with an empty XP ledger")

	if _failures > 0:
		printerr("OWCA character calculator tests failed: %d assertion(s)." % _failures)
		quit(1)
		return
	print("OWCA character calculator tests passed.")
	quit(0)


func _fill_base_characteristics(state: CharacterState, value: int) -> void:
	for characteristic in CharacterState.CHARACTERISTIC_ORDER:
		state.set_base_characteristic(characteristic, value)


func _resolve_varanox_choices(state: CharacterState) -> void:
	state.set_choice("regiment", "hive_characteristic_1", "agility")
	state.set_choice("regiment", "hive_characteristic_2", "fellowship")
	state.set_choice("regiment", "hive_urban_violence", "paranoia")
	state.set_choice("regiment", "close_order_talent", "combat_formation")


func _entry_exists(entries: Array, entry_id: String) -> bool:
	for entry: Dictionary in entries:
		if str(entry.get("id", "")) == entry_id:
			return true
	return false


func _entry_by_id(entries: Array, entry_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("id", "")) == entry_id:
			return entry
	_assert_true(false, "entry exists: %s" % entry_id)
	return {}


func _equipment_quantity(entries: Array, entry_id: String) -> int:
	for entry: Dictionary in entries:
		if str(entry.get("id", "")) == entry_id:
			return int(entry.get("quantity", 0))
	return 0


func _entry(entries: Array, entry_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("id", "")) == entry_id:
			return entry
	return {}


func _unresolved_prompt_contains(entries: Array, text: String) -> bool:
	for entry: Dictionary in entries:
		if str(entry.get("prompt", "")).contains(text):
			return true
	return false


func _assert_speciality(repository: CharacterDataRepository, speciality_id: String, wounds_base: int, choice_count: int) -> void:
	var speciality := repository.get_speciality(speciality_id)
	_assert_true(not speciality.is_empty(), "Speciality exists: %s" % speciality_id)
	_assert_equal(int(speciality.get("wounds_base", 0)), wounds_base, "Speciality Wounds base: %s" % speciality_id)
	_assert_equal((speciality.get("choices", []) as Array).size(), choice_count, "Speciality choice count: %s" % speciality_id)


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAILED: %s" % label)
		_failures += 1


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		printerr("FAILED: %s (expected %s, got %s)" % [label, expected, actual])
		_failures += 1
