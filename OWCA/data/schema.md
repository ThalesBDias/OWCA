# Regiment data schema (v1)

This document describes OWCA's source rules catalogs. It is separate from the public saved-regiment and saved-character contract in [`JSON_INTEROPERABILITY.md`](../../JSON_INTEROPERABILITY.md). The machine-readable save schemas are `owca_regiment_save.schema.json` and `owca_character_save.schema.json` in this directory.

The regiment root object provides `schema_version`, `content_version`, `budget`, `maximum_doctrines`, rule catalog dictionaries, `base_effects`, and `options`. Equipment definitions are owned separately by `equipment_catalog.json`.

Each option has:

```json
{
  "id": "stable_snake_case_id",
  "category": "home_world | commander | regiment_type | training_doctrine | equipment_doctrine",
  "name": "Display name",
  "cost": 0,
  "summary": "Short original summary",
  "effects": {},
  "choices": [],
  "requirements": { "all": [], "any": [] },
  "excludes": [],
  "source": { "book": "source_catalog_id", "page": 0 }
}
```

Supported effect keys are:

- `characteristics`: map of characteristic name to signed integer.
- `skills`: array of skill catalog IDs. Grants advance through Known, Trained (+10), Experienced (+20), and Veteran (+30), capped by the catalog's `maximum_rank`.
- `talents`: array of talent catalog IDs. Stackable talents keep a count. Each extra grant of a non-stackable starting Talent is converted to 100 bonus XP per character.
- `aptitudes`: array of Starting Aptitude names. Repeated names are de-duplicated in the regiment result.
- `special_rules`: array of `{ "name", "summary" }` objects.
- `wounds`: signed integer.
- `equipment`: array of catalog references. Entries support `quantity`, `scope`, `slot`, `replace_slot`, and `merge` (`add`, `replace`, or `unique`).
- `equipment_adjustments`: adjusts only matching existing kit. It can target a catalog `tag` or the current main weapon's `ammunition_id`; Well-Provisioned uses both forms.
- `standard_kit_points_base`: overrides the normal 30-point additional kit pool before adding 2 points per unused Regiment Creation point.

A choice belongs to its parent option and contains `id`, `prompt`, `minimum`, `maximum`, optional `scope`, optional `unique_group`, and an `options` array. Every choice option has its own `id`, `label`, and `effects`. Choice IDs must be globally stable. `unique_group` prevents two choice fields from resolving to the same option, as used by Hive World's two distinct characteristic bonuses. Core options marked with an "or" use `scope: "per_character"`. The Regiment Creator lists those choices without resolving them; their definitions are copied into the regiment save so the Character Creator can answer them independently for every character.

`requirements.all` means every listed option ID must be selected. `requirements.any` means at least one listed option ID must be selected. `excludes` lists incompatible option IDs. These checks are symmetrical at calculation time even if only one side declares the exclusion.

The UI reads `selection_rules`; category limits and doctrine-slot participation are therefore data rather than widget logic.

## Equipment catalogue schema (v1)

`equipment_catalog.json` is the single immutable definition source used by regiment creation, character creation, the Armoury browser, exports, and future inventory consumers. Every item has a stable `id`, `name`, category, concise source information, and a printed source-page reference. Applicable records add weight, Availability, ammunition relationships, armour coverage, or a weapon `profile` containing class, Damage, Penetration, qualities, and ranged profile fields.

The catalogue does not store ownership, current ammunition, equipped state, or installed modifications. Those values describe a particular character's item instance and must not be written back into a shared definition. `equipment_catalog.schema.json` documents the machine-readable shape; `EquipmentDataRepository` additionally checks unique IDs, source references, weapon profile completeness, and ammunition cross-references at runtime.

## Character advancement data schema (v1)

`guardsman_advancements.json` keeps XP rules separate from Speciality starting packages. Its `costs` object contains three matrices: `characteristic`, `skill`, and `talent`. Each matrix has `two`, `one`, and `zero` arrays selected by the number of matching Aptitudes. Characteristic and Skill arrays have four sequential entries; Talent arrays have one entry for each of three tiers.

Every Characteristic or Skill entry provides a display `name`, exactly two `aptitudes`, an optional `recommended_for` array of Speciality IDs, and an optional `source`. Talent entries additionally provide `tier`, `prerequisites`, a concise original `summary`, and optional `repeatable` or `specialist` flags. A Talent that OWCA can price and explain but cannot safely add to the purchase ledger sets `purchase_supported` to `false` and supplies a player-facing `unsupported_reason`; the browser keeps the entry visible and disables its purchase action.

Supported prerequisite objects are:

- `characteristic`: requires a named Characteristic at `minimum`.
- `skill`: requires a Skill ID at `minimum_rank`, where 1 is Known and 2 is Trained (+10).
- `skill_any`: requires any Skill from an explicit `ids` array at `minimum_rank`.
- `talent`: requires one Talent ID.
- `talent_any`: requires any Talent from an explicit `ids` array.
- `talent_prefix`: requires any known Talent whose stable ID shares a prefix.
- `talent_prefix_count`: requires a minimum number of known Talents whose stable IDs share a prefix.
- `skill_prefix`: requires any known Skill specialisation whose stable ID shares a prefix.
- `aptitude`: requires one named Aptitude.
- `special`: records an implant, Psy Rating, selected-skill rank, or other state not yet represented by the current character model. It remains unmet until a dedicated subsystem exposes that state explicitly.

Each prerequisite includes a short `label` for the UI. Full rule text is deliberately omitted. When an entry has no explicit source, `source_defaults` supplies the book and printed-page reference for its category.

Character state version 4 stores durable document identity, explicit workflow and loadout state, minimal Comrade identity, materialized starting grants, owned item instances, inventory audit events, and purchases as an ordered array of stable IDs such as `characteristic:agility`, `skill:dodge`, or `talent:rapid_reload`. Each starting grant retains its `standard_issue` or `speciality_issue` provenance, the durable IDs issued for it, and an explicit `present`, `exchange`, `loss`, `transfer`, or `correction` reconciliation (or `unresolved` until reviewed). Owned instances reference immutable equipment definitions and record positive integer quantity, supported craftsmanship, origin, equipped/carried/stored location, custodian, and a short note. Inventory events require UTC timestamps and matching identity/definition/quantity snapshots. Replaying the XP list in order makes rank costs and prerequisite chains deterministic. Versions 1 through 3 remain migration inputs and return to draft with an unprepared loadout.

`inventory_rules.json` contains the concise Core carrying-capacity lookup for Strength Bonus plus Toughness Bonus, with its printed source reference. Missing item weights produce an explicit partial total rather than a fabricated value.
