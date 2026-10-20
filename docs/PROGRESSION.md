# Items and progression

| System | First version |
|---|---|
| Persistence | Whole run saved; death loses equipment, inventory and progression |
| Inventory | Item list; no weight or stash |
| Slots | Left/right hand, helm, chest, belt, gloves, boots, two rings, amulet |
| Equipment rules | Attribute requirements, one weapon plus shield or a two-handed weapon |
| Requirements | Final loadout must remain valid; an item cannot fund its own requirement |
| Loot | Normal or magic; at most two distinct modifiers |
| Modifier pool | Life, mana, Strength, Dexterity, Intelligence |
| Armour | Physical damage reduction, capped at 75%; fractional damage rounds probabilistically |
| Gold | Drops from barrels/chests; collected automatically on movement, without an extra turn |
| Item actions | Pick up, drop, equip and unequip cost one turn; separate confirmation defaults to Cancel |
| Interact | Includes underfoot and adjacent visible objects; browsing/canceling costs no turn |
| XP | Foe kills grant XP; each level grants one passive and one active point |
| Passive tree | 81-node radial graph lifted from Soulslike; three origins, six branches and six bridges |
| Active trees | Per class, prerequisites, three ranks; only learned skills may be bound |
| Initial skills | Archer: Shoot/Juke; Wizard: Spark/Blink; Knight: Charge; all keep bump melee |
| Charge | Can target a clear empty line for retreat |
| Respec | Deferred |

Balance values live in `src/play/items.zig`, `src/play/progress.zig` and `src/play/passives.zig`. These are small
prototype pools, not full Diablo/PoE itemization. Rank upgrades improve damage and mana cost;
non-damaging skills with cooldowns also recover sooner, down to 2 turns (1 for a skill that takes
no turn, since a 1-turn cooldown ends in the turn the skill used). Equipping or allocating life does not
heal current HP.

## Tree panels and maintained references

Read [DIABLO2_SKILL_TREE.md](DIABLO2_SKILL_TREE.md) before working on the class skill panel and
[POE2_PASSIVE_TREE.md](POE2_PASSIVE_TREE.md) before working on the passive panel. These research and
implementation references distinguish observed source behavior from this game's adaptations.

Skills use compact square glyphs, downward prerequisite arrows, attached rank badges and a fixed
inspection panel with effect text and current/next values. The existing class kits and three-rank
progression remain authoritative; unimplemented D2 categories or level gates are not shown.

Passives use the existing `zig-soulslike` graph construction and radial positions: three arms, two
branches per arm, branch widths 1/2/3/3/2/1 and six cross-arm bridges at branch rings three and five.
Small stat nodes grant attributes. Larger interest nodes grant life, mana, armour or damage for a
specific style, sometimes with an attribute rider. Each branch ends at a larger double-ring capstone.
Bridges grant attributes from both neighboring arms. These capstones are numerical endpoints, not
PoE2 rule-changing keystones. Every printed grant is applied through the actual attribute/damage system.

The chosen class's origin is allocated free and gives no extra bonus. The other two origins are
immediately purchasable from the hub for one point each. Further nodes require any one allocated
incoming feeder; branches climb outward, while bridges unlock their two endpoints in either direction.
Each allocation costs one passive point, never a turn or gold. XP still awards the two point pools;
Soulslike's purchase-to-level economy is not imported. Selection, zoom and browsing spend nothing.

The full board fits initially; zoom follows the selected node. The sidebar names node tier, branch,
grants, point cost and allocation state. Separate confirmation still defaults to Cancel. Node-index
layout, grants and feeder wiring participate in the save fingerprint; saves from the old hex tree are
rejected as incompatible rather than interpreting their allocations as different nodes.

## Equipment layout references

The paperdoll follows the actual Diablo II slot arrangement, inspected against this
[Diablo II inventory screenshot](https://www.game-over.net/review/july2000/diablo2/Screen0.JPG).
It was also compared with the
[PoE2 inventory screenshot](https://deltiasgaming.com/wp-content/uploads/2024/12/Path-of-Exile-2-Inventory.jpg).
The games share the central helm/body/belt stack and tall outer hand slots; PoE2 places
rings beside the body, while D2 puts rings alongside the belt. This implementation uses D2.

| Position | D2 equipment slot |
|---|---|
| Upper center | Helm |
| Upper center-right | Small amulet slot |
| Center | Tall chest slot, beneath helm |
| Outer left / outer right | Tall right-hand weapon / left-hand offhand slots |
| Lower row, left to right | Gloves, right ring, belt, left ring, boots |

Left/right name the character's hands, so the right-hand weapon appears on the viewer's
left. Slot size and position follow the reference; inventory remains the agreed list.
The details table compares worn/item/delta values and reports final loadout requirements
and any opposite-hand item returned to storage. Placeholder artwork is indexed in
[ART_PROVENANCE.md](ART_PROVENANCE.md).

## Event log

`src/ui/journal.zig` keeps 128 saved entries, newest at the bottom. Damage, incoming harm,
recovery, loot, progression and status events have separate colors. It remains visible in
exploration and combat, anchored at bottom left beside the compact HUD. Arriving on dropped
items names each item without picking it up or repeating while idle. Mouse wheel scrolls over
the log; HUD inspection can select it and scroll up/down, then leave sideways or cancel.
New events return to the newest entry, as in the local `bg2-threejs` example. Text wraps
inside the available width, as in `crawler`.
