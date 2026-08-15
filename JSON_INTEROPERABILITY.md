# OWCA JSON interoperability contract

This document defines the public JSON boundary introduced in OWCA v0.5.1. It is intended for character-sheet tools, campaign utilities, virtual tabletops, and independent combat engines that exchange regiment or character data with OWCA.

The contract covers creation data only. It does not define attacks, damage resolution, current ammunition, temporary wounds, initiative, conditions, or other live gameplay state. Another tool may store those values in its own files or in OWCA's `extensions` object.

## Contract files

- Regiment saves use `.owreg.json` and the `owca_regiment` format.
- Character saves use `.owchar.json` and the `owca_character` format.
- [OWCA/data/owca_regiment_save.schema.json](OWCA/data/owca_regiment_save.schema.json) is the Draft 2020-12 regiment schema.
- [OWCA/data/owca_character_save.schema.json](OWCA/data/owca_character_save.schema.json) is the Draft 2020-12 character schema.
- [OWCA/data/equipment_catalog.json](OWCA/data/equipment_catalog.json) is the shared immutable equipment definition catalogue; its structure is documented by [OWCA/data/equipment_catalog.schema.json](OWCA/data/equipment_catalog.schema.json).
- [OWCA/examples/13th_varanox_light_infantry.owreg.json](OWCA/examples/13th_varanox_light_infantry.owreg.json) is the example regiment.
- [OWCA/examples/varanox_weapon_specialist.owchar.json](OWCA/examples/varanox_weapon_specialist.owchar.json) is the example character.

## The three kinds of version

OWCA records three different version concepts because they answer different compatibility questions.

| Field | Meaning | Consumer action |
| --- | --- | --- |
| `schema_version` | Public structure and field semantics, using `major.minor.patch` | Reject an unsupported major version; tolerate added fields within the same major |
| `version` | Legacy OWCA envelope/state migration number | Preserve it and follow the appropriate schema or reader migration |
| `*_content_version` | Version of the rules catalog used for calculation | Warn when reproducing results with different rules data |
| `producer.version` | Version of the application that wrote the file | Diagnostic only; do not use it instead of `schema_version` |

OWCA v0.7.0 writes interoperability schema `1.3.0`. It adds authoritative character inventory, Comrade identity, loadout reconciliation, and inventory audit records. It also records `inventory_rules_content_version` for the carrying-capacity table. OWCA continues to load compatible 1.x files and legacy saves without `schema_version`.

## Authoritative inputs and calculated previews

The `regiment` or `character` object is authoritative. It contains what the player named, selected, entered, resolved, or purchased. A consumer that has compatible OWCA rules data should calculate from this object.

`calculated_preview` is a convenient, non-authoritative snapshot. It includes totals and resolved collections such as Characteristics, Skills, Talents, Aptitudes, rules, equipment, Wounds, Fate, Movement, and XP when relevant. It lets a read-only consumer display a useful dossier without embedding the calculator.

Never write changes only into `calculated_preview`. OWCA ignores that object when loading and recalculates it from authoritative state. A preview may also differ when a file is opened with a newer rules content version.

```text
authoritative selections + compatible rules data -> fresh calculated result
                                             \
                                              -> calculated_preview at save time
```

## Common envelope fields

| Field | Required | Description |
| --- | --- | --- |
| `format` | Yes | Exact discriminator: `owca_regiment` or `owca_character` |
| `version` | Yes | Supported numeric OWCA envelope version |
| `schema_version` | Yes for v0.5.1+ | Public interoperability contract version |
| `producer` | No | Writing application name and version |
| `saved_at_utc` | No | Informational UTC save timestamp |
| `equipment_rules_content_version` | Yes for v0.6.0+ writes | Shared equipment catalogue used for names and profile definitions |
| `inventory_rules_content_version` | Yes for v0.7.0+ character writes | Carrying-capacity rules used for encumbrance previews |
| `calculated_preview` | No | Disposable derived result cache |
| `extensions` | No | Opaque namespaced data owned by other tools |

Unknown top-level fields are allowed so readers can tolerate additive contract changes. OWCA does not promise to preserve arbitrary unknown fields. Use `extensions` for data that must survive an OWCA load/save cycle.

Current regiment envelopes use numeric version `2`; current character envelopes use version `4`. Supported older envelope versions are migration inputs, not examples of the current write contract.

## Regiment authoritative state

The top-level `regiment` object contains:

| Field | Required | Description |
| --- | --- | --- |
| `version` | Yes | Regiment state migration version; currently `2` |
| `document_id` | Yes | Durable UUID identifying the record independently from its name or path |
| `workflow_state` | Yes | `draft` or `creation_complete` |
| `name` | Yes | Player-facing regiment name |
| `selections` | Yes | Arrays of stable option IDs grouped by creation category |
| `resolutions` | Yes | Regiment-wide choice ID to selected answer-ID arrays |

`selections` always provides these category keys:

- `home_world`
- `commander`
- `regiment_type`
- `training_doctrine`
- `equipment_doctrine`

The top-level `rules_content_version` identifies the regiment rules catalog. `character_creation_choices` contains snapshots of deferred `per_character` choices for inspection and older integrations, but current OWCA character calculation regenerates those choices from the selected regiment and current rules data.

## Character authoritative state

The top-level `character` object contains:

| Field | Required | Description |
| --- | --- | --- |
| `version` | Yes | Character state migration version; currently `4` |
| `document_id` | Yes | Durable UUID identifying the character record |
| `workflow_state` | Yes | `draft`, `creation_complete`, or the reserved `campaign_active` state |
| `name`, `player_name` | Yes | Player-entered identity fields |
| `regiment` | Yes | Authoritative embedded regiment-state snapshot |
| `regiment_rules_content_version` | Yes | Regiment rules used when the snapshot was selected |
| `speciality_id` | Yes | Stable Guardsman Speciality ID |
| `base_characteristics` | Yes | The nine raw accepted creation values |
| `manual_adjustments` | Yes | Explicit signed adjustments applied after package modifiers |
| `regiment_resolutions` | Yes | Per-character answers to regiment choice IDs |
| `speciality_resolutions` | Yes | Answers to Speciality choice IDs |
| `wounds_roll`, `fate_roll` | Yes | Accepted raw creation dice, or `0` while unresolved |
| `purchased_advances` | Yes | Ordered stable advancement IDs |
| `comrade` | Yes | Minimal durable Comrade ID and player-facing name |
| `loadout_state` | Yes | `unprepared`, `draft`, or `finalized` |
| `starting_loadout` | Yes | Calculated starting grants, issue provenance, issued instance IDs, and reconciliation state |
| `owned_items` | Yes | Authoritative durable equipment instances and stacks |
| `inventory_events` | Yes | Append-only issue, acquisition, quantity, transfer, loss, exchange, and correction audit entries |

Purchase order is meaningful. Advancement IDs such as `skill:dodge` or `talent:rapid_reload` must be replayed in order because costs, ranks, affordability, and prerequisites can depend on earlier entries.

Lifecycle state is explicit, not inferred from the current calculated preview. Editing a completed creation input reopens the record as a draft and invalidates its finalized loadout until starting grants match the newly calculated package. OWCA can rebuild obsolete starting-issue records while preserving later acquisitions and recording corrections. Ordinary inventory maintenance after creation does not reopen character creation. `campaign_active` is reserved by the schema for the v0.9 campaign-advancement workflow.

Each starting grant retains its `standard_issue` or `speciality_issue` origin, the durable item IDs issued for it, and an explicit reconciliation value: `present`, `exchange`, `loss`, `transfer`, `correction`, or `unresolved`. A grant marked present must still contain its full issued quantity; any other resolution needs a short player explanation before finalization. Equal definition totals with different issue origins are not interchangeable.

Each owned item uses a durable `instance_id` and immutable catalogue `definition_id`. Weapons and armour are quantity-one records; stackable ammunition and ordinary gear may use a positive quantity. Location is `equipped`, `carried`, or `stored`; custody belongs to the character, squad, or the character's declared Comrade. An unresolved definition remains authoritative and visible, but blocks finalization rather than being deleted.

Current owned inventory is authoritative. `inventory_events` provide an audit trail and are not an event-sourced combat simulation. Calculated names, weapon profiles, armour by location, and encumbrance belong only in `calculated_preview`.

## Document identity, Save As, and Duplicate

`document_id` is the stable identity of a regiment or character record. Consumers should use it when matching the same record across renamed or relocated files.

- **Save As** changes the destination path and preserves `document_id`.
- **Duplicate** creates new character, Comrade, item-instance, and event IDs and resets the duplicated record and loadout to `draft`.
- Display names and filenames are not identity keys.

An embedded regiment snapshot inside a character retains the regiment document ID that supplied it. The character has its own separate document ID.

## Atomic saves, backups, and recovery

OWCA never writes a replacement directly over the destination. It writes `filename.tmp` in the same directory, flushes it, reopens it, parses it, and validates the complete format and state. Only a valid candidate may replace the destination.

When replacing a valid existing file, OWCA rotates that file to `filename.bak` before renaming the validated temporary file into place. If replacement fails, it restores the previous destination where possible. A surviving valid `.tmp` is treated as interrupted work and is never silently overwritten.

On load, OWCA reports:

- a valid interrupted `.tmp` candidate alongside an otherwise valid file;
- a valid `.bak` when the selected destination is invalid; and
- every envelope/state migration, generated document ID, default, or lifecycle decision applied in memory.

Recovery and discard operations require an explicit player choice. Migrated data is not written until the player saves it, at which point atomic replacement preserves the previous valid file as a backup.

## Stable IDs

Machine integrations must use IDs, never display names. Names and short summaries may be corrected, translated, or restyled without a contract change.

- Rules entity IDs use lowercase snake case, such as `hive_world`, `light_infantry`, and `weapon_specialist`.
- Choice and answer IDs use the same convention.
- Advancement ledger IDs add a type prefix, such as `characteristic:agility`, `skill:tech_use`, or `talent:weapon_tech`.
- Collections in `calculated_preview` retain stable `id` fields wherever the source catalog has one.

An existing ID must not be silently reused for different rules. If a concept genuinely changes identity, add a new ID and document the migration.

## Extension data

`extensions` is an optional JSON object. OWCA does not interpret it, but validates that it is an object and preserves it through load/save cycles. Each first-level key must be namespaced as `owner/area` to avoid collisions.

```json
{
  "extensions": {
    "com.example.combat/character": {
      "external_id": "character-operator-1",
      "current_wounds": 7,
      "conditions": ["pinned"]
    }
  }
}
```

Use a domain, project ID, or similarly controlled prefix before the slash. Values beneath that key belong entirely to the external producer. Do not place essential OWCA creation selections only in an extension.

## Consumer checklist

1. Parse the root as a JSON object.
2. Check `format` before interpreting any other fields.
3. Read `schema_version`; reject unsupported major versions and treat a missing value as a legacy file.
4. Validate against the matching JSON Schema when practical.
5. Read authoritative `regiment` or `character` state and stable IDs.
6. Use `document_id`, not a display name or file path, to match records.
7. Compare rules content versions before reproducing calculated results.
8. Recalculate when compatible rules are available; otherwise label `calculated_preview` as a save-time snapshot.
9. Preserve `extensions` that the consumer does not own.
10. Ignore unknown fields within a supported schema major.

## Compatibility policy

Patch and minor schema releases may add optional fields, preview fields, or new extension guidance without changing existing meaning. A schema major release is required for incompatible field removal, a type change, a semantic change, or reassignment of an existing stable ID.

OWCA's loader accepts legacy regiment state v1 and current v2, plus character state v1–v3 and current v4. Character state v1 is migrated with an empty advancement ledger. Every character v1–v3 record receives an empty inventory, an `unprepared` loadout, and a `draft` lifecycle so its starting grants can be prepared and finalized. Legacy records receive a generated document ID when necessary, and the migration report describes every lifecycle decision. A future reader should preserve the same principle: default absent newer fields only when the old meaning is unambiguous, and reject malformed containers rather than guessing.

The executable compatibility suite is [OWCA/tests/interoperability_test.gd](OWCA/tests/interoperability_test.gd). Any save-contract change must update the schemas, examples, this document, and both round-trip and backwards-compatibility tests.
