# Contributing to OWCA

Thank you for helping improve the Only War Character Assistant. OWCA is designed to be understandable and modifiable by people learning Godot as well as experienced contributors.

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing state, calculators, persistence, or rules-data structures.

## Development setup

1. Install Godot 4.7 or a compatible Godot 4 release.
2. Open `project.godot` and allow the editor to import resources.
3. Run the project and confirm the landing page opens.
4. Run the automated tests listed in `README.md`.

Keep generated `.godot/`, local saves, exports, and temporary profiles out of commits.

## Commenting standard

OWCA intentionally favors explanatory documentation because rules code often looks simpler than the tabletop decision it represents.

Use Godot `##` documentation comments for:

- every reusable class;
- public methods that form a contract with another layer;
- signals and saved fields whose meaning is not obvious; and
- algorithms whose ordering affects legality or cost.

Good comments explain:

- why a rule is implemented in a particular layer;
- invariants that callers must preserve;
- why operation order matters;
- compatibility behavior for old saves;
- whether data is permanent state or transient presentation; and
- which source/page supports a mechanical entry.

Avoid comments that merely translate syntax, such as “increment the counter.” Those comments add maintenance cost without helping a future contributor.

## GDScript style

- Prefer typed variables, parameters, and return values.
- Use `snake_case` for variables/functions and `PascalCase` for classes.
- Keep UI code free of rules arithmetic.
- Keep calculators deterministic and free of file, clock, random, or scene-tree access.
- Use stable IDs in saves and data; use display names only for presentation.
- Duplicate dictionaries and arrays when crossing ownership boundaries.
- Return structured errors instead of silently accepting malformed data.
- Use `apply_patch`-sized, reviewable changes rather than unrelated rewrites.

## Adding or changing rules data

1. Confirm the owned source and printed page.
2. Add a stable snake-case ID.
3. Store numerical effects and a concise original summary.
4. Add a source-catalog reference and printed page.
5. Validate every referenced Skill, Talent, equipment, or option ID.
6. Add calculator coverage for the new effect or prerequisite shape.
7. Update `OWCA/data/schema.md` when introducing a new field.

Do not paste long rulebook passages. Contributors and users are expected to own the relevant books.

Equipment definitions belong in `OWCA/data/equipment_catalog.json`, never in a Speciality or regiment UI script. Each definition needs a stable ID, category, printed source reference, and the fields appropriate to that category. Weapon profiles must declare class, Damage, Penetration, and qualities; ranged profiles should also declare range, rate of fire, magazine capacity, Reload, and an ammunition relationship when one exists. Add or update `equipment_catalog_test.gd` whenever the catalogue shape or a cross-reference changes.

Inventory records store only durable identity and player decisions. Do not copy catalogue names, profiles, weights, armour values, or resolved encumbrance into authoritative state. Inventory operations belong in `CharacterInventoryService`, accept timestamps from callers, preserve append-only audit history, and receive deterministic domain coverage. Derived weight and armour belong in `CharacterInventoryCalculator`.

## Adding a Talent

Talent entries belong in the advancement catalog and should include:

- stable ID and display name;
- Tier;
- exactly two Aptitudes;
- structured prerequisites;
- repeatability when applicable;
- concise prerequisite labels for the UI; and
- source/page reference.

If an existing prerequisite type cannot express the Talent, extend the prerequisite evaluator and schema deliberately. Do not encode a prerequisite in display text alone.

## Adding a creation roll

Creation randomness belongs in `CharacterCreationRoller`, not a calculator or UI callback.

- Return the individual dice, base modifier, notation, and total.
- Allow deterministic testing through an injected seeded generator.
- Store only the accepted input in `CharacterState`.
- Clear displayed roll evidence when a user manually edits the value.
- Confirm before replacing existing character inputs.
- Do not add gameplay rolls to this service.

## Changing save formats

Treat saved JSON as a public API:

- follow [JSON_INTEROPERABILITY.md](JSON_INTEROPERABILITY.md);
- update the matching Draft 2020-12 JSON Schema and example file;
- keep selections and entered values authoritative while calculated previews remain disposable;
- preserve consumer-owned data only through the namespaced `extensions` object;
- preserve `document_id` for Save As and generate a new one for Duplicate;
- regenerate nested Comrade, owned-item, and inventory-event IDs when duplicating a character;
- route replacement writes through `AtomicJsonStore` rather than direct `FileAccess.WRITE` calls;
- report every migration/default and test that the previous valid file survives rejected or interrupted writes;
- increase the relevant version;
- preserve older readers when practical;
- reject invalid container types;
- document migrations and defaults;
- test loading the previous version; and
- test save/load round trips.

Never rely on `calculated_preview` as authoritative state, and never silently repurpose an existing stable ID.

## UI changes

- Keep the 960x650 minimum window usable.
- Avoid horizontal scrolling for primary actions.
- Make destructive or overwriting actions explicit.
- Provide manual entry alongside automated helpers.
- Put rules explanations and validation near the affected control.
- Update the responsive UI regression test when adding important actions.

## Testing checklist

Before opening a pull request:

- run the Godot editor import/compile pass;
- run regiment calculator tests;
- run character calculator tests;
- run relevant service tests;
- run responsive UI tests for UI changes;
- start every affected scene; and
- inspect generated documents or images visually when layout matters.

Include the exact commands and results in the pull-request description.

## Pull requests

Keep each pull request focused. Explain what changed, why the change belongs in its chosen layer, player impact, compatibility considerations, and validation performed.

When development branches are stacked, target the immediately preceding feature branch and state the dependency clearly. Retarget to `main` after earlier work is merged.
