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
| Passive tree | Shared connected graph, different class starts; attributes come from allocations |
| Active trees | Per class, prerequisites, three ranks; only learned skills may be bound |
| Initial skills | Archer: Shoot/Juke; Wizard: Spark/Blink; Knight: Charge; all keep bump melee |
| Charge | Can target a clear empty line for retreat |
| Respec | Deferred |

Balance values live in `src/play/items.zig` and `src/play/progress.zig`. These are small
prototype pools, not full Diablo/PoE itemization. Rank upgrades improve damage and mana cost;
non-damaging skills with cooldowns also recover sooner, down to 2 turns (1 for a skill that takes
no turn, since a 1-turn cooldown ends in the turn the skill used). Equipping or allocating life does not
heal current HP.

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
