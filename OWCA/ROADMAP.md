# OWCA roadmap

This is the living development overview for the Only War Character Assistant. It describes intended scope and dependency order, not fixed release dates. Feedback and discoveries during implementation may move individual features, but a milestone should not silently absorb a different major system.

OWCA's central promise remains:

> Build and maintain a regiment and Guardsman record, apply the supported creation and advancement rules, save it safely, and export a readable dossier.

Attacks, damage rolls, tests, current-magazine tracking, temporary Wounds, conditions, vehicles, and encounter management remain at the physical or virtual table.

## Overview

| Version | Status | Theme | Player outcome |
| --- | --- | --- | --- |
| v0.3.0 | Released | Regiment and Guardsman foundation | Create a Core regiment and a character from the five supported Guardsman Specialities |
| v0.4.0 | Released | Creation rolls, starting XP, and printable dossiers | Complete creation inputs, spend the initial allowance, and export an A4 record |
| v0.5.0 | Implemented | Complete Core Talent browser | Search, filter, price, validate, and purchase the complete Core Talent catalogue |
| v0.5.1 | Released | JSON interoperability and file safety | Exchange versioned data safely, migrate older files, and recover interrupted saves |
| v0.6.0 | Implemented | Weapon and equipment catalogue | Browse complete supported equipment definitions and weapon statistics |
| v0.7.0 | Current development | Character inventory and loadouts | Maintain owned gear, armour locations, loadout completeness, and carried weight |
| v0.8.0 | Planned | Weapon modifications | Upgrade individual weapons and calculate compatible modified statistics |
| v0.9.0 | Planned | Campaign advancement | Award XP, manage lasting character changes, and advance Guardsmen and Comrades |
| v0.10.0 | Planned | Player journal and editable dossier | Maintain notes and logs, then choose how they appear in normal or ink-saving exports |
| v1.0.0 | Planned | Stable Core Guardsman release | Deliver a crash-safe, migration-safe, accessible, and release-quality application |

## v0.5.1 - JSON interoperability

Goal: treat `.owreg.json` and `.owchar.json` as public interfaces that other projects can consume without depending on OWCA's UI.

Scope:

- semantic `schema_version` fields and stable machine IDs;
- durable document IDs so Save As and Duplicate have unambiguous identity behavior;
- explicit `draft`, `creation_complete`, and future `campaign_active` lifecycle states;
- formal Draft 2020-12 schemas;
- explicit separation between authoritative player inputs and calculated previews;
- rules-content and producer-version metadata;
- namespaced, consumer-owned extension data preserved through load/save cycles;
- Save As for choosing a new path while preserving document identity;
- Duplicate for creating a new regiment or character identity from an existing file;
- atomic saving through a same-directory temporary file that is reopened and validated before replacing the destination;
- automatic backup before a migration or replacement can alter the previous valid file;
- recovery detection for interrupted temporary saves and available backups;
- a migration report listing applied migrations, defaults, and player-relevant warnings;
- example regiment and character files;
- legacy loading, round-trip, malformed-data, and future-version tests; and
- a public compatibility and migration policy.

Combat engines may consume these files, but combat rules and session state do not become OWCA responsibilities. See [JSON_INTEROPERABILITY.md](../JSON_INTEROPERABILITY.md).

Save As is not the same operation as Duplicate. Save As preserves the record's document ID at a different path; Duplicate generates a new document ID so external tools do not mistake two independent characters for one record. A lifecycle transition is explicit and validated rather than inferred merely because every current field happens to be filled.

## v0.6.0 - Weapon and equipment catalogue (implemented)

Goal: establish one trustworthy, searchable source of supported Core weapon, ammunition, armour, gear, and upgrade definitions.

Planned scope:

- stable IDs and concise names for supported equipment;
- weapon class, Damage, type, Penetration, Range, Rate of Fire, magazine capacity, Reload, weight, Availability, and relevant qualities;
- ammunition relationships and carried-unit definitions;
- armour and general equipment statistics where applicable;
- brief original summaries rather than copied rulebook paragraphs;
- printed source-book and page references;
- search and useful category/statistic filters;
- machine-readable validation and catalogue completeness tests; and
- reusable definition lookup for character creation, inventory, export, and external consumers.

Catalogue definitions are immutable rules data. They are not the individual objects a character owns, and magazine capacity does not imply shot-by-shot ammunition tracking.

## v0.7.0 - Character inventory and loadouts (current development)

Goal: let a completed character maintain personal equipment without changing the shared catalogue definition.

Planned scope:

- add and remove supported equipment from a character;
- convert calculated starting grants into an owned starting loadout when creation is completed;
- require an explicit, validated loadout-finalization step before creation is marked complete;
- give individually owned items durable instance IDs;
- track definition ID, quantity, craftsmanship, origin, and optional short item notes;
- mark items as equipped, carried, or stored;
- calculate carried weight and encumbrance from current character values and catalogue weights;
- store armour coverage and protection by body location;
- track carried ammunition quantities without becoming a live combat counter;
- distinguish standard issue, Speciality gear, later issue, exchange, acquisition, and loss where useful;
- retain an inventory event history for issue, acquisition, exchange, transfer, modification, loss, and correction;
- introduce the minimum structured Comrade identity and ownership link required to assign gear safely;
- show inventory and loadout information in the character summary and dossier; and
- save, load, migrate, and expose owned instances through the interoperability contract.

Equipment acquisition and XP advancement remain separate systems. OWCA records what changed without assuming every item was bought with XP.

Inventory history is an audit record, not a simulation of every moment at the table. Corrections remain possible, but they should be represented clearly enough that a player can understand why the current loadout differs from the original issue.

## v0.8.0 - Weapon modifications

Goal: attach upgrades to a particular owned weapon and produce explainable final statistics.

Planned scope:

- add and remove supported modifications from an owned weapon instance;
- filter or block known incompatible combinations;
- preserve immutable base statistics;
- calculate modifications through a documented, deterministic pipeline;
- show base and modified values together;
- retain craftsmanship, modifications, and notes independently for two weapons of the same type;
- identify the source of every changed statistic;
- include modified weapon records in save files and printable dossiers; and
- add compatibility, ordering, and round-trip tests.

Temporary bonuses, firing-mode choices, ammunition expenditure, jams, and combat damage remain outside this pipeline.

## v0.9.0 - Campaign advancement

Goal: advance a saved character beyond the initial creation allowance without rebuilding them.

Planned scope:

- add an **Advance Character** option to the landing page;
- load an existing `.owchar.json` character;
- transition a validated `creation_complete` character into `campaign_active` state explicitly;
- record campaign XP awards with amount and an optional reason or session note;
- display Starting XP, Campaign XP Awarded, Total XP Earned, XP Spent, and XP Available separately;
- reuse the full Characteristic, Skill, and Talent browsers;
- support applicable Speciality Advances and Comrade Advances;
- recalculate Aptitude costs, ranks, prerequisites, and affordability immediately;
- preserve purchase order because earlier advances can affect later costs or prerequisites;
- distinguish creation purchases from campaign purchases without breaking stable advancement IDs;
- retain an advancement audit trail containing awards, purchases, removals, costs, and reasons;
- provide safe removal or refund behavior with dependent-advance warnings;
- record Insanity and Corruption values as persistent character state;
- record permanent Characteristic modifiers, lasting injuries, and other enduring campaign changes;
- expand the minimal Comrade link into a structured identity, status, and advancement record;
- make the completed inventory and weapon systems available while advancing; and
- save and export the updated long-term character record.

Existing character files will migrate with their current purchases treated as creation advances and with no campaign XP awards.

Insanity, Corruption, injuries, and permanent modifiers are record-keeping values. OWCA may calculate their declared mechanical consequences where supported, but it does not automate the encounters or gameplay events that cause them.

## v0.10.0 - Player journal and editable dossier

Goal: let players maintain and reprint their evolving written record inside OWCA.

Planned scope:

- editable general character notes;
- appearance, personality, background, and distinguishing-feature fields;
- squad, equipment, and weapon notes where appropriate;
- structured Comrade notes, current status, and printable summary fields;
- ordered campaign-log entries with a title, session or date label, and multiline body;
- optional campaign events that can feed selected advancement, injury, corruption, inventory, or Comrade changes into the journal;
- editing from both character creation and campaign advancement;
- plain UTF-8 text stored as authoritative player content in `.owchar.json`;
- inclusion of saved notes in the printable dossier;
- selective dossier-page export so players can omit pages they do not need;
- an ink-saving export profile with restrained backgrounds and decoration;
- automatic additional PDF pages when content exceeds the designed note areas;
- predictable print typography rather than shrinking long notes until unreadable; and
- migration defaults that give existing characters empty note and log fields.

An editable PDF form could be considered later. The first requirement is reliable editing inside OWCA followed by a readable generated dossier.

## v1.0.0 - Stable Core Guardsman release

Goal: turn the accumulated feature set into a dependable release rather than introducing another large subsystem.

Release criteria:

- the supported Core regiment and Guardsman workflows are complete and clearly documented;
- existing supported saves migrate without silent data loss;
- a recent-files list reopens valid records without exposing stale or unsafe paths;
- every editable workflow has a reliable unsaved-change indicator;
- players can inspect and restore available backups through a clear recovery interface;
- migrations produce understandable player-facing summaries rather than console-only messages;
- public schemas, examples, and extension behavior match the application;
- rules calculations and important UI paths have regression coverage;
- a global calculation breakdown explains where final Characteristics, Skills, Talents, Wounds, XP, encumbrance, and modified equipment values came from;
- the 960x650 minimum window remains usable without hidden primary actions;
- keyboard navigation, focus visibility, contrast, and readable scaling receive an accessibility pass;
- Windows and supported secondary-platform exports receive clean-install testing;
- printable dossiers remain legible on A4 at 100% scale;
- privacy, path-sanitization, traversal, and unsafe-filename tests protect player-controlled paths and metadata;
- forced interruption tests verify that an invalid temporary write cannot replace the last known valid save;
- crash-safe save validation covers atomic replacement, backup creation, recovery selection, and post-write parsing;
- player-facing errors explain invalid or unresolved state without requiring console access;
- contributor setup, data-extension guidance, and release procedures are current; and
- known limitations are explicit rather than disguised as complete features.

## Cross-cutting requirements

Every planned milestone must continue to follow these rules:

- Rules belong in data files or calculators, not UI callbacks.
- Saved selections and player-entered records are authoritative; calculated previews are disposable.
- Existing stable IDs are never silently reassigned to different concepts.
- Save-format changes include migration, round-trip, and backwards-compatibility tests.
- Atomic save and recovery behavior protects the most recent valid player record before replacing it.
- Lifecycle transitions, inventory events, and advancement changes remain auditable.
- External tools use the documented `extensions` namespace for their own state.
- Rules text remains limited to numerical effects, concise original summaries, and source references.
- Physical and Discord dice remain valid alternatives to OWCA's optional creation rolls.
- Responsive UI and readable print output are acceptance requirements, not later decoration.

## Unscheduled backlog

These ideas are valuable but do not yet have a committed milestone:

- additional Specialities beyond the five current Core Guardsman choices;
- supplement regiment and character content;
- homebrew catalogue import and validation;
- localization and translated display data;
- optional form-fillable PDF exports;
- external VTT or combat-engine adapters built on the public JSON contract;
- cloud synchronization or shared campaign storage; and
- broader campaign-management tools.

Moving an item from this backlog requires a defined data owner, save impact, copyright-safe content plan, UI boundary, and acceptance test. Independent tools are encouraged to build on OWCA's JSON contract rather than waiting for every adjacent feature to become part of the main application.
