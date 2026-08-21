# OWCA changelog

All notable player-facing and developer-facing changes to the Only War Character Assistant are recorded here. New work should be added under **Unreleased** and moved into a dated version section when a release is prepared.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and OWCA uses semantic version numbers where practical.

## [Unreleased]

### Added

- Added per-instance Poor, Common, Good, and Best craftsmanship for every owned ranged or melee weapon; grenades and missiles remain Common and cannot receive these modifiers.
- Added compatible installation and removal for Mono, Compact, Red-dot laser sight, Telescopic sight, and Tripod/Bipod, including one-sight exclusivity, atomic audit events, and independent same-definition weapon instances.
- Added deterministic base/final weapon profiles, final modified weight, ordered source-labelled calculation steps, compatibility explanations, Armoury reference details, and printable dossier lines.
- Added state/envelope v5 and schema `1.4.0` persistence, v4 lifecycle-preserving migration, legacy craftsmanship-alias compatibility, and a refreshed modified-weapon example.
- Added catalogue, calculator, service, migration, UI, layout, Armoury, printable, and real-renderer export regression coverage for weapon modifications.
- Added a focused Create Character loadout workflow with only Starting Equipment, Add Optional Equipment, and Review and Finalize sections.
- Added plain-language starting-grant recovery and creation-mode defaults for optional equipment: character custody, Common craftsmanship, and carried location.
- Added regression coverage for the simplified creation mode, retained Manage Loadout maintenance controls, creation finalization, and the 960x650 minimum window.
- Added a shared Character Inventory editor to Create Character and a new standalone Manage Loadout landing workflow.
- Added durable owned-item instances with safe stack splitting, quantity, craftsmanship, origin, equipped/carried/stored location, character/Comrade/squad custody, and short notes.
- Added idempotent starting-loadout materialization, changed-creation grant rebuilding, durable issued-item reconciliation, explicit loadout finalization, minimal structured Comrade identity, and append-only inventory audit events.
- Added searchable supported-equipment selection, carried ammunition quantities in catalogue units, armour AP by body location, and Core carrying-capacity calculations.
- Added partial-weight reporting for genuinely missing catalogue definitions; valid catalogue definitions with no printed source weight count as `0 kg`.
- Added character inventory service, calculator, UI, migration, interoperability, responsive-layout, and printable-loadout regression tests.
- Added provenance-aware starting-grant signatures and protected grant-owned stacks so later equipment survives creation-input rebuilds.
- Added strict v4 integer, craftsmanship, timestamp, snapshot, lifecycle, and quantity-one weapon/armour validation at load and save boundaries.
- Added idempotent no-op inventory edits, named Comrade dossier output, and automatic loadout-continuation pages for large inventories.

- Added a single versioned Core equipment catalogue with 115 immutable weapon, ammunition, armour, wargear, upgrade, and explicit placeholder definitions.
- Added complete weapon-profile fields for the currently supported catalogue slice: class, range, rate of fire, Damage, Penetration, magazine capacity, Reload, weight, Availability, qualities, and ammunition links where applicable.
- Added a read-only Armoury browser with text search, category and Availability filters, live profile details, stable IDs, and printed source-page references.
- Added a formal Draft 2020-12 equipment-catalogue schema, strict stable-ID and cross-reference validation, and focused repository and UI regression tests.
- Added equipment catalogue content-version metadata to newly written regiment and character files.
- Added a living project roadmap covering JSON file safety, the weapon catalogue, character inventory, weapon modification, campaign advancement, editable journals and exports, and v1.0 stabilization.
- Added the OWCA JSON interoperability contract with public semantic `schema_version` fields for regiment and character saves.
- Added Draft 2020-12 schemas for `.owreg.json` and `.owchar.json` files, plus documented required and optional fields, stable-ID rules, and compatibility policy.
- Added fuller non-authoritative calculated previews for regiment and character consumers, including stable-ID Skills, Talents, equipment, derived totals, choices, sources, and validation messages.
- Added an opaque namespaced `extensions` object that external tools can use for their own data and that OWCA preserves through load/save cycles.
- Added compatibility coverage for legacy files, extension round trips, preview isolation, malformed extension containers, and unsupported future schema majors.
- Added durable UUID document identities and explicit draft/completed lifecycle state to regiment and character records.
- Added Save As identity preservation and Duplicate actions that create new draft record identities.
- Added validated atomic JSON replacement, automatic last-valid `.bak` files, interrupted `.tmp` detection, and explicit recovery prompts.
- Added player-facing migration reports for legacy envelopes, state versions, generated IDs, lifecycle defaults, and advancement defaults.
- Added regression coverage for atomic replacement, backup rotation, temporary recovery, corrupt-target recovery, and post-write validation failure.
- Added the complete Core Rulebook Talent catalogue with 124 browsable entries and supported specialisations across all three Tiers.
- Added Talent search plus Tier, Aptitude, prerequisite-status, and purchase-status filters.
- Added concise effect summaries, calculated Aptitude-based XP costs, prerequisite state, and explicit blocking reasons to every Talent card.
- Added prerequisite evaluation for Aptitudes, alternative Skills, Talent prefixes, and explicit special-state requirements.
- Added regression coverage for complete Talent data, new prerequisite forms, browser search, browser filters, and unsupported specialist choices.

### Changed

- Create Character now shows only item names and meaningful quantities, omits the selected-item detail panel, and retains Search, filters, Add Equipment, and Remove; Manage Loadout and Armoury remain detailed.
- Create Character now lets players prepare calculated starting grants with **Prepare Starting Equipment**, then automatically reconciles intact prepared grants; it also groups loadout items as Weapons, Armour, Ammunition, and Gear, and keeps profiles, armour, carried weight, and the Finalize Loadout and Continue to Review action visible without exposing maintenance controls.
- Manage Loadout retains custody, provenance, reconciliation, audit-history, and other detailed maintenance controls outside the player-focused creation flow.
- Character saves now use envelope/state version 5 and public interoperability schema `1.4.0`; v4 retains its lifecycle and inventory while initializing weapon modification state, and v1-v3 migration still returns to an unprepared draft loadout.
- Normal Armoury and add-equipment browsing now show canonical base weapons once; the seven old craftsmanship variants remain exact-lookup aliases for compatible saves.
- The landing page uses a responsive four-workflow layout and the application version is `0.8.0-dev`.
- Character dossiers now print the owned loadout, custody/location context, known carried weight, and armour by location instead of only the calculated starting-equipment preview.

- Regiment and character starting packages now resolve equipment through the same shared catalogue instead of maintaining duplicate local definition maps.
- The landing page now includes a responsive third Armoury workflow and the displayed application version is `0.6.0-dev`.
- The public interoperability schema is now `1.2.0`; older compatible major-version files remain supported and receive a migration note when equipment metadata is absent.
- Regiment saves now use envelope/state version 2, character saves use envelope/state version 3, and both remain compatible with their earlier supported versions.
- The advancement rules content version is now `0.5.0-core-talents`.
- OWCA now displays specialist and variable-cost Talents it cannot safely purchase instead of omitting them from the catalogue.

### Fixed

- Kept dossier identity text below the Identification header band when Godot's fallback font is used.
- Valid catalogue definitions with no printed weight now count as `0 kg`; only missing definitions remain unresolved and block loadout finalization.

### Known limitations

- Weapon modification support is limited to the five verified Core upgrades above; requisition economics, temporary combat bonuses, firing modes, current ammunition, jams, and damage remain at the table.
- Specialist choices such as Peer, Hatred, Resistance, Psychic Power, Mastery, and individual Exotic Weapons are visible and priced but disabled until their selected specialisation can be stored safely.
- Implant, Psy Rating, and Squad Logistics prerequisites are displayed but remain unmet because those character-state systems are outside the current Guardsman slice.

## [0.4.0] - 2026-08-03

### Added

- Added optional character-creation rolls for all nine base Characteristics (`2d10 + 20`), Wounds (`1d5`), and Fate (`1d10`), while keeping every value manually editable.
- Added individual dice breakdowns, roll-all and per-field actions, and confirmation before replacing entered values.
- Added deterministic creation-roll service tests, UI behavior tests, and responsive roll-control coverage.
- Added `ARCHITECTURE.md` and `CONTRIBUTING.md` with layer boundaries, data flow, commenting standards, save-version policy, rules-data guidance, and contributor checklists.
- Expanded Godot `##` documentation across state, repositories, calculators, persistence, and advancement processing.
- Added **War Grinder** as a persistent looping background soundtrack, with a landing-page toggle and global `M` shortcut.
- Added a headless regression test for soundtrack import, looping, volume, pause, and resume behavior.
- Added a **Spend Starting XP** character-creation stage with separate Characteristic, Skill, and Talent browsers.
- Added the Core Aptitude-matched cost tables for all four Characteristic ranks, all four Skill ranks, and all three Talent tiers.
- Added all nine Characteristic advancement tracks and the Core Skill categories/specialisations currently relevant to OWCA.
- Added a curated Core Talent advancement catalog covering the five Guardsman Specialities' recommended advances and Weapon Training prerequisite chains.
- Added specialty recommendation markers, source/page references, affordability feedback, and unmet-prerequisite explanations to advancement cards.
- Added an ordered purchase ledger with per-purchase XP costs and removal controls.
- Added headless tests for Aptitude pricing, sequential Skill and Characteristic costs, Talent prerequisites, affordability, invalidated dependencies, and XP save/load.
- Added a headless responsive-layout regression test at 960, 1090, and 1280 pixel window widths.
- Added an original two-page A4 Guardsman field-dossier design with riveted steel framing, parchment panels, oxblood section headers, and restrained hazard-strip accents.
- Added Review-stage export of one printable PDF plus two 2480x3508 PNG pages containing Characteristics, Skills, Talents, equipment, trackers, rules, choices, sources, advances, and campaign notes.
- Added a dependency-free Godot PDF writer and a normal-renderer visual export regression test.

### Changed

- Character calculations now apply purchased Characteristic, Skill, Talent, and Sound Constitution Wound advances to the live summary and derived values.
- Character JSON saves now use format/state version 2, record the advancement-data content version, and remain compatible with version 1 character files.
- Character summaries and status panels now show XP spent, remaining, and total.
- Advancement cards now use a vertically stacked action layout, and narrow windows automatically reclaim the live-summary column for the active creation stage.
- The character workflow scope text and Review guidance now advertise printable dossier export while retaining physical or Discord dice rolling.

### Fixed

- Fixed long advancement names pushing the Buy button outside the visible centre panel and requiring horizontal scrolling.
- Fixed the landing page and Regiment Creator continuing to display `v0.3` after the application version changed; both now read the version from `project.godot`.

### Known limitations

- The v0.4 Talent browser is a focused Guardsman testing catalog, not every Talent in the Core Rulebook.
- Character-sheet PDFs are image-based; their text is not selectable.
- Only the five Core Guardsman Specialities are available for character testing.
- OWCA only rolls optional character-creation values; attacks, damage, tests, and other gameplay dice remain outside the app.

## [0.3.0] - 2026-08-02

### Added

- Added a landing page separating regiment creation from character creation.
- Added all Core Rulebook Home Worlds, Commanding Officers, Regiment Types, Training Doctrines, and Equipment Doctrines used by the regiment creator.
- Added validation for the 12-point regiment budget, one required Regiment Type, and up to two optional doctrines.
- Added live aggregation of Characteristic modifiers, Skills, Talents, Aptitudes, special rules, Wounds modifiers, and equipment.
- Added support for single-answer and multiple-answer starting choices.
- Added correct duplicate Skill advancement and duplicate non-stackable Talent XP compensation.
- Added versioned regiment JSON save/load and readable text dossier export.
- Added the first Guardsman character-creation slice with Heavy Gunner, Medic, Operator, Sergeant, and Weapon Specialist.
- Added manual entry for the nine rolled Characteristics and manual Wounds and Fate rolls; OWCA performs the resulting arithmetic and lookups without rolling dice.
- Added character calculation for final Characteristics, Characteristic Bonuses, Wounds, Fate Points, Movement, Skills, Talents, Aptitudes, rules, and equipment.
- Added duplicate Aptitude replacement choices.
- Added versioned character JSON save/load.
- Added example 13th Varanox regiment and Weapon Specialist character files.
- Added source-book and printed-page references throughout the rules data.
- Added headless regiment and character calculator tests.
- Added an unofficial, non-commercial fan-project and third-party intellectual-property disclaimer.

### Changed

- Regiment Type is displayed as its own required creation stage instead of being counted in the optional doctrine counter.
- Choices that belong to individual soldiers are deferred from regiment creation and resolved in the Character Creator.
- The project was separated from the original beat-'em-up prototype and cleaned into a standalone OWCA Godot project.
- Repository documentation was promoted to the project root and expanded with fresh-clone test instructions.

### Fixed

- Fixed confusing doctrine-slot reporting by showing Regiment Type as `1/1` and optional doctrines as `0/2` through `2/2`.
- Fixed partial multiple-choice packages so selected benefits appear in the live summary while the package remains unresolved.
- Removed obsolete game input mappings, resources, plugins, caches, and broken legacy references.

### Known limitations

- Starting XP purchases and advancement costs are not implemented yet.
- Printable character-sheet PDF export is not implemented yet.
- Only the five Core Guardsman Specialities are available for character testing.
- OWCA intentionally does not roll dice.
