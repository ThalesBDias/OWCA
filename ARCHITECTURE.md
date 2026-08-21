# OWCA architecture

This document explains how the Only War Character Assistant is divided, why those boundaries exist, and where new code belongs. It is intended for contributors who have not followed the project's development history.

## Design goals

OWCA is a data-driven creation assistant rather than a digital game table. Its responsibilities are to:

- collect regiment and character-creation inputs;
- validate combinations and unresolved choices;
- apply concise mechanical effects deterministically;
- calculate derived values and XP costs;
- save editable, versioned JSON files; and
- produce readable summaries for physical tabletop play.

Combat resolution, attack rolls, damage rolls, automated ammunition consumption, vehicles, and campaign simulation remain outside the current scope. Creation dice are allowed because they produce inputs to the builder; they do not resolve play at the table.

## Layered structure

OWCA uses five layers. Dependencies should move down this list, never upward.

### 1. Rules data

Files under `OWCA/data/` contain catalogs, costs, prerequisites, concise effect summaries, and source references. Stable snake-case IDs are saved; display names may change without invalidating saves.

Rules data must not depend on UI node names. Long copyrighted text is deliberately excluded.

### 2. Repositories

`RegimentDataRepository` and `CharacterDataRepository` load JSON, perform structural checks, expose lookup methods, and format source labels. A repository answers questions about the catalog; it does not hold a player's selections.

### 3. State and services

State objects contain user-authored inputs:

- `RegimentState` stores option IDs and resolved regiment-level choices.
- `CharacterState` stores the loaded regiment snapshot, rolled base values, manual adjustments, individual choices, the ordered XP-purchase ledger, and authoritative owned-item state including per-weapon craftsmanship and installed modification IDs.

State must remain serializable. Calculated Characteristics, final Skills, final equipment, and XP totals do not belong in state because they can be reproduced from inputs and current rules data.

Small services own operations that are neither state nor rules aggregation:

- persistence services read and write versioned JSON envelopes;
- `CharacterCreationRoller` generates optional character-creation dice;
- exporters transform a completed calculation into text, PNG, or PDF output;
- `MusicManager` owns persistent soundtrack playback.

Randomness is isolated in `CharacterCreationRoller`. The service accepts an injected seeded random-number generator so tests remain deterministic. Roll breakdowns are transient UI evidence; only the resulting input is stored in `CharacterState`.

### 4. Calculators

Calculators are deterministic engines. Given the same state and rules data, they must return the same result without reading UI nodes, files, clocks, or random generators.

`RegimentCalculator` validates the 12-point build and aggregates regiment effects.

`CharacterCalculator` performs the character pipeline:

1. validate and apply the loaded regiment snapshot;
2. apply the selected Speciality;
3. resolve regiment and Speciality choices;
4. resolve duplicate Aptitudes and starting Talent compensation;
5. calculate Characteristics;
6. replay ordered XP purchases through `CharacterAdvancementCalculator`;
7. calculate Wounds, Fate, Characteristic Bonuses, and Movement; and
8. normalize Skills, Talents, equipment, sources, errors, and warnings for consumers.

`CharacterAdvancementCalculator` replays purchases in order because a purchase can change the cost or legality of every later purchase. Removing an earlier purchase intentionally causes later entries to be recalculated.

`WeaponModificationCalculator` resolves legacy craftsmanship aliases to immutable base definitions, validates the complete installed-upgrade set, applies craftsmanship before modifications in stable data-defined order, and returns base/final profiles, final weight, situational effects, and source-labelled calculation steps. It treats an omitted valid base weight as zero; missing base or modification definitions remain invalid and unresolved.

Calculators return dictionaries because their results combine several heterogeneous catalogs. Result keys form an internal contract used by the UI and exporters; changes therefore require regression tests.

### 5. UI scenes and controllers

Scenes provide layout roots. Their GDScript controllers construct most widgets programmatically and translate user actions into state changes.

The UI may:

- read repositories and calculated results;
- update state inputs;
- call focused services; and
- display errors, warnings, roll details, or export messages.

The UI must not reproduce rules calculations. If two screens need the same mechanical result, that result belongs in a calculator or service.

## Data flow

```text
JSON rules -> Repository -----> Calculator -> Result -> UI / Exporter
                    \             ^
User input ----------> State -----|
Creation roller ------> UI ------> State
```

The roller returns a transparent record to the UI. The UI shows the dice and writes the total to state. The calculator sees only the resulting input, exactly as it would for a physical or Discord roll.

## Save-file policy

Regiment and character files use a versioned envelope plus a versioned state object. The public field contract, stable-ID rules, calculated-preview boundary, and third-party extension namespace are defined in [JSON_INTEROPERABILITY.md](JSON_INTEROPERABILITY.md).

`schema_version` governs public interoperability. Numeric envelope/state `version` fields govern OWCA migrations, while rules `content_version` fields identify the data used for calculation. Do not substitute one kind of version for another.

When changing saved fields:

1. increase the relevant state or file version;
2. keep backward loading support when practical;
3. validate container types before casting;
4. provide defaults for fields absent from older versions; and
5. add a round-trip and backward-compatibility test.

Calculated previews in saves are informational. They are never trusted as authoritative when loading.

Every replacement save goes through `AtomicJsonStore`: write a same-directory temporary file, flush, reopen, parse, run the format/state validator, rotate the previous valid destination to `.bak`, and only then rename the candidate into place. Valid interrupted `.tmp` files are recovery candidates and must never be overwritten without an explicit player decision.

Save As preserves the state's durable document ID. Duplicate creates a new identity and resets lifecycle to `draft`. Migration is reported to the player and remains in memory until an atomic save persists it.

## Source and copyright policy

Mechanical numbers, concise original summaries, stable IDs, and book/page references are acceptable project data. Do not add rulebook PDFs, copied paragraphs, artwork, logos, or other third-party assets without explicit authorization.

Project-owner-created assets should include a short provenance note, as demonstrated by `OWCA/audio/README.md`.

## Testing boundaries

Tests under `OWCA/tests/` are executable documentation:

- calculator tests cover deterministic rules aggregation and edge cases;
- persistence tests cover versioning and round trips;
- UI tests protect discoverability and responsive layout;
- creation-roll tests inject a seeded generator and verify ranges and structure;
- visual PDF tests require a real renderer and inspect generated A4 output.

Every bug fix should add a test that fails before the fix. Every new rules-data shape should include at least one accepted and one rejected example.

## Equipment architecture

`EquipmentDataRepository` owns the immutable catalogue and is shared by the regiment and character repositories. Equipment work distinguishes definitions from owned instances:

- a weapon definition contains immutable base statistics;
- an owned weapon instance has a unique ID, craftsmanship, modifications, and notes;
- temporary ammunition belongs to session/loadout state rather than the immutable definition; and
- modified statistics are calculated through a documented pipeline rather than written back into base data.

The seven old craftsmanship-specific IDs remain exact-lookup legacy aliases, but normal Armoury and add-equipment selection expose only canonical base definitions. Craftsmanship rules and the five supported upgrade operations live in validated catalogue data. The read-only Armoury explains those rules without mutating them; each owned ranged or melee weapon independently selects craftsmanship and installed upgrades. Grenades and missiles are outside this pipeline.

## Inventory architecture

`CharacterState` owns current item instances, a minimal Comrade identity, provenance-aware starting-grant reconciliation, explicit loadout state, and append-only audit events. Current ownership is authoritative; events explain issue, acquisition, exchange, transfer, modification, loss, and corrections but are not replayed as a gameplay simulation. Grant-owned stacks cannot absorb later acquisitions or have their issue provenance rewritten, so rebuilding creation gear cannot delete later equipment.

`CharacterInventoryService` is the only mutation boundary used by the UI. It materializes starting grants idempotently, preserves source quantities when packages merge, splits stacks without fabricating acquisitions, validates complete weapon profiles before changing craftsmanship or upgrades, and receives timestamps from callers. When creation choices change, it can rebuild only obsolete starting-issue records while preserving unchanged weapon instances, later acquisitions, and append-only history. `CharacterInventoryCalculator` joins saved instances to `EquipmentDataRepository`, attaches the shared final weapon projection, applies its modified weight through the data-driven carrying table from `InventoryRulesRepository`, selects the highest equipped armour AP per location, and keeps missing definitions visible as unresolved player records.

`CharacterInventoryEditor` is a reusable presentation control. Both the creation-stage Loadout page and standalone Manage Loadout scene use it; persistence, calculations, and audit rules therefore remain identical in both workflows. Its item and reconciliation forms stack vertically at the minimum window width. Printable loadout projection paginates overflow and includes the minimal Comrade identity without printing the complete audit ledger.
