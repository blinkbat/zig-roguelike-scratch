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
| Gold | Ground coins collect automatically on arrival at their cell; opening a chest drops its gold on the ground, and opening loot never collects coins |
| Item actions | Take item, Take all, drop, equip and unequip cost one turn when successful; Take all fills available inventory space and leaves excess items |
| Interact | First bump or Interact opens a closed chest for one turn, revealing its contents without a modal. Stepping onto a bag/open chest opens loot for the movement turn; bags remain walkable. Interact browses one bag/open chest for free, or offers a choice among multiple nearby containers/doors. Canceling is free |
| Loot artwork | One `item-bag.png` per ground item cell; `chest-item-bag.png` while a chest contains items, then `chest-open.png` when empty |
| Foe loot | Gold is common, plain white items occasional, magic blue items rare; white items have no rolled modifiers, blues have one or two |
| XP | Foe kills grant XP; each level grants one passive and one active point |
| Passive tree | 81-node radial graph lifted from Soulslike; three origins, six branches and six bridges |
| Active trees | Per class, prerequisites, three ranks; only learned skills may be bound |
| Initial skills | Archer: Shoot/Juke; Wizard: Spark/Blink; Knight: Charge/Cleave; all keep bump melee |
| Charge | Can target a clear empty line for retreat |
| Respec | Deferred |

Balance values live in `src/play/items.zig` (including loot rates and foe/barrel/chest gold), `src/play/progress.zig`, `src/play/passives.zig`, `src/play/attrs.zig` (life, mana, crit, dodge, armour cap), `src/play/hero.zig` (class bases, mana recovery), `src/play/flask.zig` and each skill module. These are small
prototype pools, not full Diablo/PoE itemization. Rank upgrades improve damage and mana cost;
non-damaging skills with cooldowns also recover sooner, down to 2 turns (1 for a skill that takes
no turn, since a 1-turn cooldown ends in the turn the skill used). Equipping or allocating life does not
heal current HP.

Mana uses small whole numbers alongside life. Starting pools are 20 for archer/knight and 24 for wizard;
base skill costs range from 2 to 7. Intelligence grants 2 mana per 5 points, and mana affixes grant 1–3.
Natural recovery is 1 mana per 5 spent turns; recovery passives add to that five-turn rate, with partial
progress retained across turns, doors and saves. Cost reductions round up to whole mana, with a minimum
of 1 for paid skills. Mana Shield still absorbs one damage per mana.

Both flasks spend charges without spending a turn. The first of three recovery ticks happens immediately;
the other two happen on the next two spent turns. A life flask restores half maximum life before passive
bonuses; a mana flask restores 10 mana. Drinking again restarts that flask's recovery and applies its first
tick immediately, without advancing the other flask, natural recovery, enemies, ailments or cooldowns.
The saved recovery remainder and revised passive grants change the save fingerprint; older saves are incompatible.

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

All 46 bases can drop white or blue. White items retain fixed base properties and have
no rolled modifiers; blues add one or two ordinary modifiers. Base identity is independent
of rarity. Requirements follow the relevant build attribute.

Daggers and hunting bows favor weapon critical strikes; handaxes and great axes bleed,
with great axes applying stronger bleeds. Maces and greatclubs can stun. Crossbows ignore
20 percentage points of physical reduction; bandits have 15% and beefy pibs 20%.
Short swords have a narrow damage range; greatswords and war bows favor raw damage.
Great weapons, bows, crossbows and staves occupy both hands; slings and wands allow an offhand.

Caster implements have no attack damage. The ordinary wand grants spell critical chance;
ash, rime and storm wands improve fire, cold and lightning damage respectively. Oak staves
grant a larger general spell bonus. Tomes grant mana, orbs spell critical chance, totems
life on kill, bucklers dodge, and shields physical reduction. Gloves, armour, belts, boots,
helmets and rings offer heavy/light/spell damage, life, mana, dodge, recovery or armour
identities. `items.Spec.innate` is the source; rolled modifiers never include these fixed effects.

Equipment recovery effects combine with passive perks through `Simulation.heroPerks`.
Weapon and spell critical bonuses remain separate, and elemental/physical bonuses apply
only to their matching damage component. Live damage and previews share these calculations.

## Class balance and status resistance

The knight starts with 24 Strength, 34 life, 10% physical reduction and a 3-5 basic strike.
Charge and Shield Bash cost 3 mana; Cleave starts learned and costs 2. Spark's base damage
is 2-4, retaining its 2-mana cost and 50% base stun chance.

Every hero and foe has separate temporary resistance meters for stun, burn, bleed, chill
and pin. A successful application adds 25 percentage points, up to 100%; each meter clears
after five spent turns without a successful reapplication. Failed attempts do not refresh
the timer. Idle frames, free actions and drinking flasks never age these meters. Innate
stun resistance adds to buildup: beefy pib starts at 75%, so one landed stun temporarily
makes it immune. These gates apply to spells, weapon effects and foes hitting heroes or
other foes. Slime halves inherit meters and bleed strength; doors and saves preserve them.
The HUD shows an inspectable resistance icon and meter, and wounded foes show a slim gold
bar for their highest current buildup below their life bar.

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
mana per five turns and cheaper skills; usually with an attribute rider. Each branch ends at a larger
double-ring capstone whose rider may be a second effect. Bridges grant attributes from both
neighboring arms. Attribute-side grants go through `attrs`; the rest are `passives.Perks`, read by
`progress.State.perks` and applied in `game` (`manaRegen`, `drink`), `game/combat.zig` (`wound`), `State.cost` and the
life flask's description (`flask.Life.describe`). `passives.INFO` holds each grant kind's group, label and wording.

The chosen class's origin is allocated free and gives no extra bonus. The other two origins are
immediately purchasable for one point each. There is no central hub. Further nodes require any one allocated
incoming feeder; branches climb outward, while bridges unlock their two endpoints in either direction.
Each allocation costs one passive point, never a turn or gold. XP still awards the two point pools;
Soulslike's purchase-to-level economy is not imported. Selection, zoom and browsing spend nothing.

The board opens zoomed in; zoom follows the selected node, with pan and a full-board overview control.
The graph uses simple circles and quiet lines without labels, legends or a central node. Allocated
nodes have solid arm-coloured fills and gold rims; reachable nodes have clear rims, and distant
nodes stay muted. The sidebar shows a small name, readable grants and riders, any essential note,
and one allocation action or status. One deliberate action allocates the selected eligible node. Node-index
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
