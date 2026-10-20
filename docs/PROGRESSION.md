# Items and progression

| System | First version |
|---|---|
| Persistence | Whole run saved; death loses equipment, inventory and progression |
| Inventory | Item list; no weight or stash |
| Slots | Main hand, offhand, helm, chest, belt, gloves, boots, two rings, amulet |
| Equipment rules | Attribute requirements, one main-hand item plus an offhand, or a two-handed item |
| Requirements | Final loadout must remain valid; an item cannot fund its own requirement |
| Loot | Normal or magic; at most two distinct modifiers |
| Modifier pool | Life, mana, Strength, Dexterity, Intelligence |
| Armour | Physical damage reduction, capped at 75%; fractional damage rounds probabilistically |
| Gold | Drops from barrels/chests; collected automatically on movement, without an extra turn |
| Item actions | Pick up, drop, equip and unequip cost one turn; one direct action, screen stays open |
| Interact | Includes underfoot and adjacent visible objects; browsing/canceling costs no turn |
| XP | Foe kills grant XP; each level grants one passive and one active point |
| Passive tree | 81-node radial graph lifted from Soulslike; three origins, six branches and six bridges |
| Active trees | Per class, prerequisites, three ranks; only learned skills may be bound |
| Initial skills | Archer: Shoot/Juke; Wizard: Spark/Blink; Knight: Charge; all keep bump melee |
| Charge | Can target a clear empty line for retreat |
| Respec | Deferred |

Balance values live in `src/play/items.zig` (including barrel and chest gold), `src/play/progress.zig`, `src/play/passives.zig`, `src/play/attrs.zig` (life, mana, crit, dodge, armour cap), `src/play/hero.zig` (class bases, mana recovery), `src/play/flask.zig` and each skill module. These are small
prototype pools, not full Diablo/PoE itemization. Rank upgrades improve damage and mana cost;
non-damaging skills with cooldowns also recover sooner, down to 2 turns (1 for a skill that takes
no turn, since a 1-turn cooldown ends in the turn the skill used). Equipping or allocating life does not
heal current HP.

## Weapons and offhands

Strength scales **heavy** weapon damage; Dexterity scales **light** weapon damage.
Melee versus ranged determines which equipped weapon a skill uses, independently of
its scaling attribute. Spells still scale with Intelligence. The same weapon lookup
governs basic melee, skill damage, rank bonuses and live damage previews.

| Scaling | Basic weapon types |
|---|---|
| Heavy / Strength | Longsword, mace, greatsword, crossbow, greatclub; the existing great axe |
| Light / Dexterity | Bow, sling, dagger, short sword, handaxe |
| No innate attack | Wand, staff |
| Offhand | Tome, orb, buckler, shield, totem |

Each type has one basic item in the loot pool. One-handed melee weapons reuse the
existing short-sword tier, two-handed heavy melee weapons the great-axe tier, and
ranged weapons the bow tier. Requirements follow the scaling attribute. Greatsword,
greatclub, great axe, bow, crossbow and staff use both hands; sling and wand allow
an offhand. Wands and staves add no weapon damage to melee, ranged skills or spells;
the hero's existing unarmed fallback and spell bases remain separate.
Offhands use the existing requirement/armour tiers and can roll the ordinary modifier
pool. Inventory details identify weapon scaling or the absence of innate attack.

The expanded item enum and updated passive grants change the save fingerprint;
older saves are rejected by the existing compatibility check.

## Tree panels and maintained references

Read [DIABLO2_SKILL_TREE.md](DIABLO2_SKILL_TREE.md) before working on the class skill panel and
[POE2_PASSIVE_TREE.md](POE2_PASSIVE_TREE.md) before working on the passive panel. These research and
implementation references distinguish observed source behavior from this game's adaptations.

Skills use compact square glyphs, downward prerequisite arrows, attached rank badges and a fixed
inspection panel with effect text and current/next values. The existing class kits and three-rank
progression remain authoritative; unimplemented D2 categories or level gates are not shown.

Passives use the existing `zig-soulslike` graph construction and radial positions: three arms, two
branches per arm, branch widths 1/2/3/3/2/1 and six cross-arm bridges at branch rings three and five.
Small stat nodes grant attributes. Larger interest nodes carry the Soulslike tree's effects, translated
to turns: life, mana, armour, style damage, critical and dodge chance, leech (life per foe a blow
damages), life per kill, cull (blows kill foes left at or below a share of life), life flask recovery,
mana per turn and cheaper skills; usually with an attribute rider. Each branch ends at a larger
double-ring capstone whose rider may be a second effect. Bridges grant attributes from both
neighboring arms. Attribute-side grants go through `attrs`; the rest are `passives.Perks`, read by
`progress.State.perks` and applied in `game` (`wound`, `recover`, `drink`) and `State.cost`.

The chosen class's origin is allocated free and gives no extra bonus. The other two origins are
immediately purchasable from the hub for one point each. Further nodes require any one allocated
incoming feeder; branches climb outward, while bridges unlock their two endpoints in either direction.
Each allocation costs one passive point, never a turn or gold. XP still awards the two point pools;
Soulslike's purchase-to-level economy is not imported. Selection, zoom and browsing spend nothing.

The board opens zoomed in; zoom follows the selected node, with pan and a full-board overview control.
Node fill colour names its grant group (attribute, life, mana, offense, defense); from the opening
zoom each node carries its amount and stat under it. The sidebar leads with the grants, then the
de-emphasized name and branch, allocation state, point cost and a note where a grant needs one. One deliberate action allocates the selected eligible node. Node-index
layout, grants and feeder wiring participate in the save fingerprint; saves from the old hex tree are
rejected as incompatible rather than interpreting their allocations as different nodes.

## Equipment layout references

Item text, comparisons, character stats and inspection follow
[DATA_PRESENTATION.md](DATA_PRESENTATION.md). Its 2026-10-20 research pass uses Diablo II
as the complexity target and PoE2 as a reference for separating advanced detail.

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
| Outer left / outer right | Tall Main hand / Offhand slots |
| Lower row, left to right | Gloves, right ring, belt, left ring, boots |

The main hand is on the viewer's left and the offhand on the right, matching D2/PoE2.
Use role names in all player-facing labels. The stored `right_hand`/`left_hand` enum
values remain unchanged. A two-hander marks the offhand with Both hands and the held
weapon's name; it is not presented as an empty slot. Slot size and position follow
the reference; inventory remains the agreed list.
Selected and equipped items use separate cards with only applicable base properties,
nonzero requirements and actual magic modifiers. Legal equip previews list changed character
bonuses with signs; unmet requirements show the available attribute after displacement,
excluding the item's own bonus. Opposite-hand items returned to storage are named.
The Stats page separates attributes, survival, damage bonuses and progression, with
percent units on the values. Placeholder artwork is indexed in
[ART_PROVENANCE.md](ART_PROVENANCE.md).

## Event log

`src/ui/journal.zig` keeps 128 saved entries, newest at the bottom. Damage, incoming harm,
recovery, loot, progression and status events have separate colors. It remains visible in
exploration and combat, anchored at bottom left beside the compact HUD. Arriving on dropped
items names each item without picking it up or repeating while idle. Mouse wheel scrolls over
the log; HUD inspection can select it and scroll up/down, then leave sideways or cancel.
New events return to the newest entry, as in the local `bg2-threejs` example. Text wraps
inside the available width, as in `crawler`.
