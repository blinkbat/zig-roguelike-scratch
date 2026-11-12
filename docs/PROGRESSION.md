# Items and progression

Balance, skill paths and item catalogs live in source. This document records
transaction rules and integration behavior.

| Responsibility | Owner under `src/` |
| --- | --- |
| Item identity, bases and innate effects | `play/items.zig`, `play/item_bases.zig` |
| Legal modifiers, rolls and names | `play/affixes.zig`, `play/loot.zig` |
| Loadout validation and storage | `play/gear.zig`, `play/inventory.zig`, `play/ground_items.zig` |
| Attributes and class bases | `play/attrs.zig`, `play/hero.zig` |
| XP, ranks, costs and point spending | `play/progress.zig` |
| Passive graph and grants | `play/passives.zig` |
| Flasks and supplies | `play/flask.zig`, `play/consumable.zig` |
| Combat and recovery integration | `game/sim.zig`, `game/attacks.zig`, `game/combat.zig`, `game/skills.zig`, `game/rewards.zig` |
| Equipment and loot commands | `game/character.zig` |

## Inventory and loot transactions

Inventory is a list without weight or stash. Equipment has main hand, offhand,
helm, chest, belt, gloves, boots, two rings, amulet and two flask slots.
A main-hand item allows an offhand unless it occupies both hands. The resulting
loadout must satisfy every requirement; an item cannot fund its own requirement.

Successful equip, unequip and drop each spend a turn. Raising maximum life through
equipment or allocation does not heal current HP. Death loses run equipment,
inventory and progression; persistence follows [SAVE_FORMAT.md](SAVE_FORMAT.md).

A first bump or Interact opens a closed chest for one turn, revealing contents
without a modal. Stepping onto a bag or stocked open chest opens loot for the
movement turn; bags remain walkable with items left behind. Automatic opening
is suppressed while a foe is visible. Deliberate Interact browses a sole bag/open
chest for free. Multiple nearby objects offer a choice; doors always keep that
choice so queued input cannot immediately return through an arrival door.

Loot shows only the selected cell. Take item affects its selected row; Take all
fills available inventory space and leaves excess items. All items and supplies
taken during one visit cost one turn together when loot closes, including Back
or leaving for another screen. Closing without taking items or supplies is free.
An empty modal closes.

Ground gold without items is a coin drop, collected on stepping onto it without
an extra turn or modal; Interact can take it for one turn. Gold with items shares
their bag, and chest gold stays in its chest. Loot shows gold beside the position
count, not as an item row, and takes it free as the modal closes. A chest containing
only gold is collected without opening loot. Gold needs no inventory space.
Movement and browsing do not collect gold from bags or chests.

One bag marker represents each item-bearing ground cell. Coin-only cells use coin
sprites; nonempty open chests use the chest/bag sprite and empty ones the open
chest sprite. Coins have no lights.

## Items and combat effects

Base identity is independent of normal, magic or rare quality. Normal items have
fixed base properties; magic and rare items add legal rolled modifiers.
Magic names describe their prefix/suffix rolls. Rare two-part names are saved
independently of their modifiers. Innate effects remain separate from affixes;
`affixes.Mod.allows` owns equipment restrictions.

Strength scales heavy weapons, Dexterity light weapons and Intelligence spells.
Melee/ranged delivery independently selects the equipped weapon. Basic attacks,
skills, rank bonuses and previews share weapon lookup and damage calculations.
Caster implements have no innate attack. Weapon and spell critical bonuses are
separate; damage-type bonuses affect only matching components.

Equipment and passive recovery combine through `Simulation.heroPerks`.
Worn-item kill recovery also applies to status kills; passive kill recovery
applies only to blows. Recovery is pictured with its killing impact or tick.
Mana recovery keeps partial progress across spent turns, travel and saves.
Paid skill costs round up to whole mana with a minimum of one.

Thorns retaliate against a connected adjacent melee hit, including one absorbed
by Mana Shield or lethal to the hero. Dodges, arrows and damage over time do not
trigger them. Attacker armour applies; thorns cannot crit, apply weapon statuses,
cull, trigger blow recovery or recurse. Kills still award normal rewards and
equipment kill recovery for a surviving hero. Picture returned damage, death and
splits with the incoming impact, separately from Unyielding.

Spoils supplies separate gold and item-rarity bonuses. Gold scales once on pickup,
with probabilistic fractional rounding. Rarity changes quality rather than drop
count and uses equipment at the time foes/chests roll items. Both rarity thresholds
scale and cap independently; the rare threshold is nested inside magic-or-rare.
Values and rounding implementation live in `play/loot.zig`.

Reach, area, penetration, recovery and cooldown modifiers must reach aiming,
previews, resolution and inspection through their shared simulation/progression
helpers. Haste can make an action free, aging nothing and giving foes no action;
waiting and stunned turns cannot be hastened.

## Flasks, supplies and skill lifetime

New runs equip life and mana flasks, which do not roll as loot. They can be
unequipped, dropped and worn for a turn. Only a worn flask can be drunk or receive
kill charges; stored charges remain while unequipped.

Consumables spend a turn. Flask drinking spends charges and applies its first
recovery tick before foes act; later ticks follow spent turns. Drinking again
restarts that flask's recovery. Supplies stack in Inventory and can be used there
or through bound slots showing their counts. Exact effects, capacities, durations
and drops belong to `play/consumable.zig` and `play/flask.zig`.

Idle frames and free actions never age preparations, stances or ground effects.
A flask drink is an action and ends Guard and Overwatch. Unyielding can always
be turned off, even with no mana. Barriers, fire walls and caltrops persist with
their level; hero preparations and stances travel with the hero.

Barrier and Fire Wall share two-endpoint targeting but retain their own placement
rules. Both preview and resolution read those rules. Barriers block movement and
projectiles but allow sight and do not replace terrain. Fire Wall applies normal
burn resistance and ignites flammable ground through the map fire system.
Reaction, projectile and split timing follow [ARCHITECTURE.md](ARCHITECTURE.md).

## Progression and statuses

Each level grants separate active and passive points. Only learned class skills
may be bound; innate utilities remain available. Shoot is a fixed basic attack
with equipment/attribute scaling and no skill-rank bonus. Compatible old saves
refund excess Shoot ranks once. Rank costs and cooldown floors come from
`progress.State`, including the turn consumed by using a skill.

See [active skills](DIABLO2_SKILL_TREE.md) and [passives](POE2_PASSIVE_TREE.md)
for graph and panel contracts. Keep authored paths and grant values in their
source tables rather than copying them here.

Each harmful status has independent innate resistance and temporary buildup.
Only successful applications build resistance or refresh its expiry. Free actions
and idle frames never age it. Slime splits inherit meters and bleed strength;
travel and saves preserve them. Terrain and rain modifiers are resolved at the
occupied tile, as described in [TERRAIN.md](TERRAIN.md). Duration, stacking and
proc values remain in the owning status modules.

## Presentation

Items, equipment layout and Stats follow
[DATA_PRESENTATION.md](DATA_PRESENTATION.md); input follows
[CONTROLLER.md](CONTROLLER.md). [HUD_LAYOUT.md](HUD_LAYOUT.md) owns pictured
resource timing and the event log's placement.

`play/log.zig` owns saved events; `ui/journal.zig` renders them newest at the
bottom. New events return scrolling to the newest entry. Arrival on dropped items
names them without collecting them or repeating while idle.
