# Save compatibility

`save.zig` owns slots and autosave. `save_data.zig` classifies fields, `save_format.zig` validates detached snapshots, and `save_values.zig` converts gameplay values.

## Loading policy

Load and slot inspection use the same decoder. Starting a run checks only whether a slot is missing or empty. A failed load preserves the live game, map and file. A successful load marks the run dirty for an atomic rewrite on its next save.

Name, class, level state, actor pool, hero reference, combat RNG and progression are required. Missing optional fields take their declared defaults. These include empty inventory, ground and history, full inactive flasks, zero mana and cooldowns, the starting clock, right-facing bodies and loot RNG seed 1. Restore starting skills and class origins, derive a missing skill bar from learned skills and refund excess ranks. Restore maximum life, maximum mana and elemental resistances from repaired gear and progression.

Validate collection sizes, numeric ranges, enum tags, booleans, finite floats and RNG state before applying a snapshot. Check actor identities and occupancy, door markers, unique coin piles, and agreement between summary and run. The hero occupies the first pool slot on active and visited levels. Reject missing required data, duplicate known fields and checksum failures.

Autosave captures owned state on the frame. Its worker encodes, checksums and atomically replaces the slot. Join the worker before reusing snapshot or byte storage. Failed writes rearm dirty state. Track changed visits across travel so a reused snapshot includes every modified level.

## Encoding and evolution

`core/store.zig` wraps the body in magic, a little-endian u64 version and a little-endian u64 Wyhash body checksum. Run magic is `cistern-save\n`. Ossuary magic is `cistern-ossuary-v1\n`, version 1.

| Run version | Migration on load |
| --- | --- |
| 1 | Equip the original flasks. Restore class arms in empty slots where the hand rules allow. |
| 2 | Preserve empty flask slots. Restore class arms only if both hands are empty and the bag holds no class arm. |
| 3 | Preserve deliberately emptied hands. Versions 1–3 derive climate locations from the saved level. |
| 4 | Read saved climate locations. Missing node weather overrides inherit the node's weather. |

`core/wire.zig` writes a u16 field count. Each field has a u16 name length, name bytes, u32 payload length and payload. Integers use a signedness byte and 64 little-endian bits. Floats use little-endian f64 bits. Enums and union tags use names. Arrays have u32 counts, byte arrays store bytes directly, and optionals have a checked presence byte. Enum-indexed arrays use key names. Counted containers store active entries. Fixed geometry requires exact dimensions.

Record order, alignment, enum ordinals and integer widths can change while represented values still fit. Skip unknown record fields. Renamed fields need a `(new, old)` entry in `WAS`. Renamed enum tags or changed representations need an explicit conversion. Preserve Xoshiro256's four state words and passive node identities `(arm, branch, seam, ring, slot)`. Retired nodes refund a point. Duplicate identities are invalid.

Older portable actors default missing bleed movement bonuses and projectile or quickstep cooldowns to zero. Missing stun defaults to false. In-flight orbs use the thrower's kind for their element. Missing zoo definitions default to none. Authored map edits affect new runs.

Legacy loose zoo keys become key chests. For a taken key at a still-locked gate, restore the carried Small Key or put it back in its chest if the bag is full. A chest that would block a body or cut off the gate opens and leaves the key on the ground if space permits. An open gate grants no replacement. Migrate each visited level once, skipping the stale copy of the active level.

## Legacy files

Raw saves have no field schema. Accept only a matching ABI, type and passive-tree fingerprint, then validate the detached state. Enum membership and raw layouts contribute to that fingerprint. Other fingerprints require their original schema and a migration. Keep the recorded fingerprint and legacy fixtures.

`LegacyMap` omits the script and `LegacyLevel` omits fields from `LEVEL_ADDED_FROM` onward. Conversion fills their defaults. `PORTABLE_FIELDS` holds trigger state, elapsed days, life recovery and climate locations. A converted run or ossuary is marked for portable rewrite.

Use in-memory fixtures to verify recovery and rejection before mutation when changing a persistent identity or representation.
