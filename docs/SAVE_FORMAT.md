# Save compatibility

Run saves and ossuary records use versioned envelopes and named values. They no
longer contain Zig struct bytes, padding, compiler versions or enum ordinals.
`save.zig` owns slots and asynchronous writes; `save_data.zig` classifies saved
fields; `save_format.zig` parses, validates and applies detached snapshots;
`save_values.zig` owns conversions for gameplay values.

## Loading policy

Preserve recoverable state and convert on parse. Missing fields with declared
defaults use those defaults; unknown record fields are skipped. Required identity
and world state must still be present. Renaming a persistent field or enum requires
an explicit alias or migration: its spelling is now part of the file contract.
Changing record order, enum ordinals, native alignment or integer widths within
the stored value's range needs no migration.

Missing run fields use empty inventory/ground/history, zero counters and cooldowns,
full inactive flasks, initial clock, right-facing bodies and deterministic loot RNG
seed 1. Missing mana starts at zero. A missing skill bar uses the loaded class and
learned skills. Name, class, level state, actor pool, hero reference, combat RNG and
progression are required. Within progression, absent additions have their declared
defaults; class origins and initial skills are restored. Reduced rank limits refund
excess points. Flask capacities and generator settings fit current supported ranges.

Passive allocations use `(arm, branch, seam, ring, slot)` identities, independent of
array order, display names and grants. Removed identities refund a passive point;
duplicates are rejected. Preserve those identities when rearranging the tree, and
add an explicit migration if their meaning changes. RNG state explicitly names
Xoshiro256 and stores its four words; changing algorithms requires a converter.

Lengths and counts are bounded before indexing. Unknown enum/union tags, invalid
booleans, numeric overflow, non-finite floats, duplicate known fields, impossible
actor references, incomplete required data and checksum failures are rejected.
Active and visited levels validate occupancy and positions. Summary data must agree
with the run. Parsing and validation complete before either the live game or its map
is changed. A successful load marks the run dirty for an atomic canonical rewrite.
Reading a save never changes its file.
Autosave copies owned snapshot data on the frame; the existing worker performs
encoding, checksum calculation and atomic writing. Snapshot and byte buffers are
reused only after worker completion, and failed encodes or writes rearm dirty state.

## Legacy files

The previous raw format remains readable when its recorded ABI/type/tree
fingerprint matches this build. Its counts, primitive tags and semantic state are
checked in detached storage before applying it. Its next save uses the portable
format; legacy ossuary records similarly become dirty after conversion.

Raw files with an unknown layout cannot be safely inferred from a fingerprint:
they carry no field schema. They remain untouched and are reported as incompatible.
Supporting one requires its original schema and an explicit migration. Keep
`RECORDED_FINGERPRINT` and the legacy fixtures as guards against accidentally
claiming compatibility.

The reader takes the map and level in their raw shape without the fields added
to their ends since (`save_data.LegacyMap`, `LegacyLevel`: the script, folk, healing gas and steam),
then converts with those fields defaulted. Run state added after the raw format
(`PORTABLE_FIELDS`, the trigger runtime) lives in portable saves alone.

## Encoding and evolution

`core/store.zig` supplies atomic replacement and an envelope: magic, a little-endian
u64 format version, body, and a little-endian u64 Wyhash checksum of that body.
The checksum detects damage; it is not authentication. Unknown envelope versions
are refused. Run magic is `cistern-save\n`, version 2; ossuary magic is
`cistern-ossuary-v1\n`, version 1. Version 1 runs predate flasks worn as items and load
with both flasks equipped; version 2 keeps an empty flask slot empty.

`core/wire.zig` writes structs as a u16 field count followed by length-delimited
named fields. Each field has a u16 name length, name bytes, u32 payload length and
payload. Integers carry a signedness byte and 64 little-endian bits; floats use
little-endian f64 bits. Enum and union tags are names. Arrays have u32 counts,
byte arrays have byte payloads, and optionals have a checked presence byte.
Enum-indexed arrays use key names. Counted containers write only active entries.
Fixed geometric arrays must retain their exact dimensions.

Add defaults only when omission has a safe meaning. Keep essential fields required.
For changed identities or representations, add conversions in `save_values.zig`
or a version-specific reader, plus in-memory fixtures proving both recovery and
rejection without mutation. Never silently reinterpret an unknown tag or truncate
an overflowing value. Tests must not write save files.
