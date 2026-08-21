# Only War Character Assistant v0.8.0 development

This module is a data-driven Godot 4 regiment and Guardsman creation assistant. Regiment creation includes every Core Rulebook option in the five supported categories: 8 Home Worlds, 9 Commanding Officers, 8 Regiment Types, 7 Training Doctrines, and 7 Equipment Doctrines. The current character-creation testing slice implements the five Core Guardsman Specialities: Heavy Gunner, Medic, Operator, Sergeant, and Weapon Specialist. Entries were checked against the supplied Only War Core Rulebook PDF; content files record printed book pages rather than PDF viewer indices.

## Unofficial fan-project disclaimer

OWCA is an unofficial, non-commercial fan-made tool. It is not affiliated with, sponsored by, or endorsed by Games Workshop, Fantasy Flight Games, or any other rights holder. *Warhammer 40,000*, *Only War*, and all related names, settings, characters, and game material remain the property of their respective owners.

This repository does not include rulebook PDFs or reproduce long-form rules text. Users are expected to own the relevant source books. Its rules data is limited to numerical effects, concise summaries, and source/page references for personal tabletop use. The GNU GPL in this repository applies only to original OWCA code and other material the project authors have the right to license; it does not grant rights to third-party intellectual property.

See [OWCA/ROADMAP.md](OWCA/ROADMAP.md) for the path to v1.0, [OWCA/CHANGELOG.md](OWCA/CHANGELOG.md) for version history and patch notes, [ARCHITECTURE.md](ARCHITECTURE.md) for system boundaries and data flow, [JSON_INTEROPERABILITY.md](JSON_INTEROPERABILITY.md) for the public save-file contract, and [CONTRIBUTING.md](CONTRIBUTING.md) for the commenting, rules-data, save-format, and testing standards used by contributors.

## Project layout

```text
OWCA/
  audio/
    war_grinder.mp3           Persistent background soundtrack
  data/
    regiment_options.json       Regiment rules and catalog data
    guardsman_specialities.json Five Core Guardsman starting packages
    guardsman_advancements.json XP costs, Aptitudes, prerequisites, and complete Core Talent catalog
    equipment_catalog.json      Shared immutable equipment and weapon definitions
    equipment_catalog.schema.json Formal equipment-catalogue JSON Schema
    inventory_rules.json          Core carrying-capacity lookup and source metadata
    regiment_options.schema.json Formal JSON Schema (Draft 2020-12)
    owca_regiment_save.schema.json Public regiment-save JSON Schema
    owca_character_save.schema.json Public character-save JSON Schema
    schema.md                    Data contract and extension guide
  examples/
    13th_varanox_light_infantry.owreg.json Example saved regiment
    varanox_weapon_specialist.owchar.json  Example saved Guardsman
  scripts/
    regiment_data_repository.gd Rules loading and lookup
    regiment_state.gd           Serializable user selections
    regiment_calculator.gd      Pure aggregation and validation
    regiment_persistence.gd     JSON save/load
    dossier_exporter.gd         Readable text export
    character_data_repository.gd Character rules loading and lookup
    character_state.gd          Serializable individual inputs
    character_calculator.gd     Character aggregation and validation
    character_advancement_calculator.gd Ordered XP ledger and purchase validation
    equipment_data_repository.gd Shared equipment validation, search data, and lookup
    inventory_rules_repository.gd Carrying-capacity data loading and validation
    character_inventory_service.gd Owned-item mutations and audit events
    character_inventory_calculator.gd Weight, encumbrance, armour, and definition projection
    weapon_modification_calculator.gd Per-instance craftsmanship, compatibility, and final weapon profiles
    interoperability_contract.gd Shared public-schema and extension validation
    document_identity.gd       Durable UUID generation and validation
    atomic_json_store.gd       Validated atomic writes, backups, and recovery
    character_persistence.gd    Character JSON save/load
    character_creation_roller.gd Optional, testable creation dice
    music_manager.gd           Persistent looping soundtrack and mute control
    character_sheet_exporter.gd Off-screen A4 page rendering and export orchestration
    pdf_image_writer.gd         Dependency-free image-to-PDF writer
  ui/
    landing_page.gd             Landing-page controller
    LandingPage.tscn            Main scene and workflow selection
    regiment_creator.gd         UI/controller
    RegimentCreator.tscn        Regiment workflow
    character_creator.gd        Guardsman workflow UI/controller
    CharacterCreator.tscn       Guardsman workflow scene
    armoury_catalogue.gd        Read-only searchable equipment browser
    ArmouryCatalogue.tscn       Armoury reference scene
    character_inventory_editor.gd Shared creation and maintenance loadout editor
    loadout_manager.gd           Saved-character loadout maintenance workflow
    LoadoutManager.tscn          Standalone loadout scene
    printable_character_sheet.gd Original paginated field-dossier drawing
    save_recovery_dialog.gd     Explicit interrupted-save recovery prompt
  tests/
    regiment_calculator_test.gd Headless smoke tests
    character_calculator_test.gd Guardsman package and persistence tests
    character_sheet_export_test.gd Normal-renderer PDF/PNG visual test
    character_creation_roller_test.gd Deterministic creation-dice tests
    character_creation_roll_ui_test.gd Roll controls and overwrite-safety tests
    character_ui_layout_test.gd Responsive character-workflow layout tests
    music_manager_test.gd      Background-music import and control test
    app_version_ui_test.gd     Visible application-version regression test
    talent_browser_ui_test.gd  Complete Talent search and filter tests
    interoperability_test.gd   Public JSON contract and compatibility tests
    atomic_json_store_test.gd  Atomic replacement, backup, and recovery tests
    file_safety_ui_test.gd     Save As, Duplicate, lifecycle, and recovery UI contract
    equipment_catalog_test.gd  Equipment schema, profiles, references, and shared lookup
    armoury_catalogue_ui_test.gd Armoury search and detail rendering
    character_inventory_service_test.gd Ownership, reconciliation, history, and lifecycle tests
    character_inventory_calculator_test.gd Weight, encumbrance, armour, and missing-definition tests
    inventory_ui_test.gd         Shared editor, landing workflow, and minimum-window tests
    printable_loadout_test.gd    Printable owned-loadout projection tests
    weapon_modification_catalog_test.gd Craftsmanship and upgrade data-contract tests
    weapon_modification_calculator_test.gd Deterministic final-profile tests
    weapon_modification_service_test.gd Atomic install/remove and independent-instance tests
```

## Run

Open the repository's `project.godot` in Godot 4 and run the project. The landing page separates regiment and character creation. The **13th Varanox** button fills the regiment acceptance example.

## Headless tests

On a fresh clone, let Godot build its generated global-class cache before running the script-based tests:

```text
godot --headless --editor --path . --quit
godot --headless --path . --script res://OWCA/tests/regiment_calculator_test.gd
godot --headless --path . --script res://OWCA/tests/character_calculator_test.gd
godot --headless --path . --script res://OWCA/tests/character_ui_layout_test.gd
godot --headless --path . --script res://OWCA/tests/character_creation_roller_test.gd
godot --headless --path . --script res://OWCA/tests/character_creation_roll_ui_test.gd
godot --headless --path . --script res://OWCA/tests/music_manager_test.gd
godot --headless --path . --script res://OWCA/tests/app_version_ui_test.gd
godot --headless --path . --script res://OWCA/tests/talent_browser_ui_test.gd
godot --headless --path . --script res://OWCA/tests/interoperability_test.gd
godot --headless --path . --script res://OWCA/tests/atomic_json_store_test.gd
godot --headless --path . --script res://OWCA/tests/file_safety_ui_test.gd
godot --headless --path . --script res://OWCA/tests/equipment_catalog_test.gd
godot --headless --path . --script res://OWCA/tests/armoury_catalogue_ui_test.gd
godot --headless --path . --script res://OWCA/tests/character_inventory_service_test.gd
godot --headless --path . --script res://OWCA/tests/character_inventory_calculator_test.gd
godot --headless --path . --script res://OWCA/tests/inventory_ui_test.gd
godot --headless --path . --script res://OWCA/tests/printable_loadout_test.gd
```

The character-sheet visual test needs a real renderer because Godot's Windows headless display driver is a dummy. It runs minimized and writes the example output to the path in `OWCA_PDF_OUTPUT`:

```text
godot --rendering-method gl_compatibility --path . --script res://OWCA/tests/character_sheet_export_test.gd
```

The Regiment Creator resolves only regiment-wide decisions. Choices marked `per_character` are listed as deferred benefits, do not prevent a regiment from being valid, and are not answered or stored as resolutions in the regiment file. The file carries a snapshot of those choice definitions for the future Character Creator.

Save files use a public, versioned JSON contract with stable rule and document IDs, explicit draft/completed lifecycle state, separate authoritative inputs and calculated previews, formal schemas, and an opaque namespaced extension area for external tools. Validated atomic writes, automatic `.bak` rotation, interrupted `.tmp` recovery, and player-facing migration reports protect existing records. Files written before this contract remain loadable. See [JSON_INTEROPERABILITY.md](JSON_INTEROPERABILITY.md). Dossier export writes a readable plain-text summary that is suitable for printing from any editor. Rules are stored as short summaries with source/page pointers; consult the owned rulebook for complete wording.

Duplicate starting Skills advance from Known through Trained (+10), Experienced (+20), and Veteran (+30). Extra copies of a non-stackable starting Talent are reported as +100 XP per duplicate, following the Core Rulebook's regiment/character creation guidance.

The Guardsman Character Creator loads an `.owreg.json` regiment, accepts manually rolled base Characteristics, applies shared and individual modifiers, resolves regiment and Speciality choices, and calculates Wounds, Fate Points, Characteristic Bonuses, and Movement. It combines Skills, Talents, Aptitudes, rules, and equipment into one live summary and saves versioned `.owchar.json` character files. Physical and Discord dice remain fully supported.

Character creation also provides optional rolls for all nine base Characteristics (`2d10 + 20`), Wounds (`1d5`), and Fate (`1d10`). Every result shows its individual dice, remains manually editable, and requires confirmation before replacing an entered value. Manual edits clear the transient OWCA roll breakdown. Gameplay tests, attacks, damage, and ammunition use remain at the table.

The v0.5 development slice expands the ordered starting-XP ledger into a complete Core Talent browser. Its 124 entries and supported specialisations can be searched by name, brief effect, or prerequisite and filtered by Tier, Aptitude, prerequisite state, and purchase state. Every Talent displays its calculated Aptitude-based XP cost, short rules summary, prerequisites, availability reason, and Core Rulebook reference. Specialist, implant-dependent, Psy Rating, and variable Logistics-cost Talents remain visible but are disabled whenever OWCA cannot represent their required choice or state safely.

The v0.6 Armoury remains the immutable definition source, while v0.7 turns calculated starting grants into durable owned-item instances. In Create Character, the player-facing Loadout stage is limited to Starting Equipment, Add Optional Equipment, and Review and Finalize: players prepare starting equipment with **Prepare Starting Equipment**, then intact prepared grants reconcile automatically; optional equipment defaults to the character with Common craftsmanship in the carried location, and the stage keeps item profiles, armour, and carried weight concise. Manage Loadout is the detailed maintenance workflow, where players can add, remove, equip, carry, store, transfer, split, reconcile, and annotate equipment; manage custody and provenance; and review audit history.

v0.8 adds Poor, Common, Good, or Best craftsmanship to each individual ranged or melee weapon and supports the five Core upgrades already represented by the catalogue: Mono, Compact, Red-dot laser sight, Telescopic sight, and Tripod/Bipod. Normal selection shows one base weapon entry—so a Good M36 lasgun and a Good las carbine are separate owned instances, not separate catalogue definitions. Grenades and missiles remain Common and cannot receive upgrades. Manage Loadout explains compatibility, shows immutable base and calculated final profiles, and keeps two copies independent. Inventory weight and the printable dossier consume the same final projection; a valid definition with no `weight_kg` contributes `0 kg`, while a missing definition remains unresolved.

The character workflow is responsive down to a 960x650 minimum window. Advancement actions remain inside their cards, horizontal stage scrolling is disabled, and the live-summary column automatically hides below 1100 pixels so the active form keeps usable space.

The Review stage can export an original A4 field dossier as one printable PDF plus 2480x3508 (300-DPI) PNG pages. Page 1 is the table-ready character record; page 2 contains rules, resolved choices, source references, advances, and campaign notes. Most dossiers use those two pages; unusually large inventories receive full loadout-continuation pages so owned gear is never silently omitted. The PDF is image-based, so its text is not selectable. Open it in a PDF viewer and print at 100% scale on A4 paper.

“War Grinder” plays as OWCA's looping background soundtrack and continues uninterrupted while changing scenes. Use the landing-page music button or press `M` outside a text field to pause or resume it. The default level is deliberately lower than full volume.

## Acceptance example

- Hive World (3)
- Choleric commander (2)
- Light Infantry (2)
- Close Order Drill (2)
- Scavengers (3)
- Total: 12/12 points, Regiment Type 1/1, and Optional Doctrines 2/2
