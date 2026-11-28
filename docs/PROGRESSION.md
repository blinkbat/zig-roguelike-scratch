# Items and progression

## Equipment and loot

Any class can wear gear whose requirements it meets. Validate the complete loadout, excluding each item's own bonuses from its requirements. A swap must leave room in the bag for every displaced item and preserve requirements already met by retained gear. Old saves can contain unmet requirements. Such items may come off or remain in their existing slots. A quiver fits beside a ranged weapon, including a two-handed one, or an empty main hand. [Gear rules](../src/play/gear.zig) · [Inventory transactions](../src/play/inventory.zig)

Each class starts with its own weapons and both flasks. Skills check their weapon, implement or shield requirement at use. A bump uses the wielded melee weapon or the class's unarmed blow. Equipping, removing or dropping an item costs an action. Raising maximum life through equipment or allocation preserves current HP. [Class kits](../src/play/hero.zig) · [Skill requirements](../src/play/skillbar.zig)

| Interaction | Result |
| --- | --- |
| Open a closed chest | Spend an action to reveal its contents in place. A mimic reveals itself. The jail's outside chest holds an interchangeable Small Key, consumed on a successful unlock. |
| Step onto a stocked bag or open chest | Movement opens its loot panel when no foe is visible. Deliberate Interact browses a sole bag or open chest for free. Doors always require a choice. |
| Take items or supplies | Take all fills available bag and stack space from the selected cell. Closing the panel spends one action for everything taken. Browsing is free. |
| Collect gold | Loose coins collect on arrival, or for an action through Interact. Bag and chest gold collects free when closing that cell's loot panel. A chest with only gold needs no panel. |

The ground displays one bag per stocked cell and distinct sprites for loose coins, stocked chests and empty chests. Arrival names items underfoot. [Loot commands](../src/game/character.zig) · [Reward resolution](../src/game/rewards.zig)

## Item rolls and damage

Normal gear has fixed base properties. Magic names reflect affixes. Rare names persist independently of modifiers. Gear rolls draw from the equippable bases except flasks. Small Keys have no equipment slot or affixes. A hidden tier limits eligible modifiers and their values. Chests and merchants use the area's door distance from the start. Foes use the higher of area level and the level derived from their base life. Spoils scales gold once at pickup with probabilistic rounding. Its rarity bonus scales the nested quality thresholds when loot rolls, preserving drop frequency. [Bases](../src/play/item_bases.zig) · [Affixes](../src/play/affixes.zig) · [Loot rolls](../src/play/loot.zig)

Strength scales heavy weapons, Dexterity light weapons and Intelligence spells. Multi-style attacks take the mean increase. The equipped weapon supplies its delivery and scaling, and caster implements supply spell scaling. Apply bonuses to their matching damage components. Use the same prepared blow, hit range, reach, area and cooldown helpers for previews, inspection and resolution. [Progression calculations](../src/play/progress.zig) · [Combat resolution](../src/game/attacks.zig)

| Effect | Rule |
| --- | --- |
| Serrated and Grievous | Serrated raises bleed chance for the wielded weapon's delivery. Grievous snapshots extra damage on a hero-inflicted bleed for ticks when its victim moves or is displaced. Refreshes keep the strongest base and movement bonus independently. Splits, travel and saves preserve the wound. |
| Composure and Cleansing | Composure resists every mental-tagged status. A successful life-flask drink clears one wound in status declaration order before the turn advances. Its resistance buildup survives. |
| Anchorage | Prevents a one-cell incoming knockback or pull while allowing the hit to resolve. |
| Thorns | A connected adjacent melee hit retaliates even when shielded or lethal. Attacker armour applies. Thorns use a separate damage path from weapon procs, criticals, culling, blow recovery and Unyielding. Death, splits and rewards resolve with the incoming impact. |
| Recovery | Equipment kill healing can trigger on status kills. Passive kill healing requires a killing blow. Show recovery with its hit or tick. Fractional regeneration progress survives travel and saves. |

## Turn and progression rules

A level grants separate active and passive points. Only learned class skills and innate utilities can be bound. Shoot has one fixed rank. Compatible saves refund excess ranks once. Mana costs round up with a minimum of one for paid skills. Cooldown floors account for the turn spent casting. [Active skills](DIABLO2_SKILL_TREE.md) · [Passives](POE2_PASSIVE_TREE.md) · [Save format](SAVE_FORMAT.md)

Worn flasks receive kill charges and can be drunk. Charges persist while unequipped. Drinking ends Guard and Overwatch and restarts that flask's recovery. Its first tick comes on the next spent turn before foes act. Supplies stack separately from equipment and can be used from inventory or a bound slot. [Flasks](../src/play/flask.zig) · [Supplies](../src/play/consumable.zig)

Haste can spare the action's turn. Waiting and forced stun turns always advance time. Idle frames and free actions do not age statuses, preparations or ground effects. Unyielding can be switched off at zero mana. Ground effects stay on their node, and the hero carries active stances through doors. Movement clears Steady Aim. A raised skeleton fights visible foes, including surfaced swimmers within melee reach, and follows through doors when space permits. [Tactical skills](../src/play/tactics.zig) · [Foe rules](../src/game/foe_rules.zig)

Harmful statuses build and expire resistance independently. A successful application refreshes its meter. Tags can overlap and are derived by status kind. Slime halves inherit meters, which travel and saves preserve. [Status rules](../src/play/resilience.zig) · [Terrain modifiers](TERRAIN.md) · [Impact timing](ARCHITECTURE.md)
