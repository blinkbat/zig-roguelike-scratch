# Item and character information

Show relevant facts once: identity, effect, then values and the action or blocker.
Items, skills and tooltips carry no flavor text. Keep balance in source and
derive previews from gameplay calculations.

## Shared presentation

Names and headings use Balthazar; compact text at 18px and below uses Source Sans 3.
Use native font sizes, spare dividers and dark surfaces. Scaled panels use the
mipmapped faces; native panels retain crisp native atlases. Do not shrink text
to fit unnecessary tables.

Menus and focus use shared muted gold: `look.UI_GOLD` and `look.UI_FOCUS`.
Magic blue, rare yellow, resource/element colors and actual gain/loss colors
retain their meanings. Red marks a real blocker or loss. Zero values are dim.
Controls use device-aware glyphs, including keyboard keycaps.

Follow the foundational UI restraint rules in `AGENTS.md`: no explanatory
headings for self-evident content, repeated action text or permanent control
legends. Existing actionable controls keep their names and glyphs. Keep locked
skill names readable; borders, icons, ranks and selected details convey state.

Character and binding panels stay centered and grow at half the window-fitting
rate, capped at 1.25x, fitting small windows within a 16px margin. Drawing,
hit regions and passive clipping share the transform. Detail/body text is
18px/20px before scaling. The binding picker's range count stays clear of
skill-set labels and its details are left-aligned.

Descriptions explain the specific effect and exceptions, not repeated armour,
resistance, attribute-scaling, flask or status rules. Dedicated status inspection
owns status definitions. Use explicit units: damage bonuses are percentages,
critical damage is a multiplier, armour is physical damage reduction, and
cooldowns/durations are turns. Do not invent DPS or a universal gear score.

Status hover cards and controller Inspect show the effect first, then its Wounds,
Slows, Mental and/or Elemental tags as underlined keywords. Hover a word, or enter
keyword inspection with the Inspect action and navigate the available words, to
open its definition and member list above the current card. Back closes that
definition first. Advanced Stats also offers all four groups for lookup without
an active status. Membership comes from `play/resilience.zig`.
Show only the underlined words: no category prefix or controller/back hints.

`ui/keywords.zig` owns the shared keyword component. Menus and tooltips pass stable
term definitions and their drawing surface; hit regions use the same transform
as the words. Definitions stay on screen and preserve their underlying menu or
tooltip. All interaction uses the existing device-aware Inspect and Back actions.
Shared panel backgrounds become more opaque with stacking depth: base HUD,
menus/tooltips, then keyword definitions. `gfx/look.zig` owns the opacity steps.

## Items and equipment

An item card reads in this order:

1. Name in normal pale, magic blue or rare yellow text; rare items also show their
   base name. Quiet slot and hand/scaling metadata follow.
2. Applicable base properties in neutral text, including fixed innate effects.
   Damage is one range; innate bleed chance has no separate bleed-damage line.
3. Nonzero requirements using full attribute names. Show available attributes
   inline, computed after displacement and excluding the item's own bonus;
   red is reserved for unmet requirements.
4. A divider and actual rolled modifiers in rarity color. Omit an empty section.

Cards share a left edge, use 17px metadata, 18px effects and 22px property rows.
Requirement errors follow the actual card height. Selected and equipped items
have separate side-by-side cards, without a derived “If equipped” change list.
Keep the real loadout validation and explicit ring destination.

The paperdoll uses these positions:

| Position | Slot |
| --- | --- |
| Upper center | Helm |
| Upper center-right | Amulet |
| Center beneath helm | Chest |
| Outer left / right | Main hand / Offhand |
| Lower row, left to right | Gloves, right ring, belt, left ring, boots |

Player-facing labels say Main hand and Offhand; saved `right_hand`/`left_hand`
identities remain unchanged. Lists say Both hands and cards say Two-handed.
An occupied offhand names and shows the two-hander's faded glyph instead of
looking empty. Equipped glyphs use rarity colors, empty slots faded slot glyphs;
item lists lead with item glyphs. Inventory remains a list.

## Character, skills and HUD

The main Stats sheet leads with life, mana and each learned skill's hit range
and status chances, including the skill roll and weapon's separate roll.
Defenses, attributes, critical chances and progression follow. Advanced holds
damage bonuses, critical multiplier, recovery, elemental and status resistances,
including dimmed zeroes. `character_stats.Tier` separates large headline
numbers, Balthazar key rows and plain data rows.

Skills show effect, rank, current or first-rank properties, then a next-rank
section containing only changes. Hit ranges include equipment, attributes,
preparation and rank before critical hits and defenses. If only average damage
changes, show old/new rank bonus. Utility skills omit damage; maximum skills omit
the empty next-rank section. See [active skills](DIABLO2_SKILL_TREE.md).

Passives lead with actual grants and riders, followed by an essential exception
and one action or blocker. Preserve origins, feeders and costs; see
[passives](POE2_PASSIVE_TREE.md).

HUD inspection puts behavior before metrics and omits irrelevant zero cost,
cooldown and rank rows. Resource orbs can use compact label/value pairs.
Free actions, remaining drinks and turns until ready use ordinary phrases.
See [HUD_LAYOUT.md](HUD_LAYOUT.md) for placement and pictured timing.

## Actions and verification

Show the consequence before one deliberate action. Equip, unequip, drop and
point allocation need no secondary modal; save deletion retains its second
press. Item actions keep Character open. Navigation and binding follow
[CONTROLLER.md](CONTROLLER.md); loot transactions follow
[PROGRESSION.md](PROGRESSION.md).

Owners are `ui/book.zig`, `ui/item_card.zig`, `ui/character_stats.zig`,
`ui/trees.zig`, `ui/hud.zig` and shared `ui/character_layout.zig`.
Inspect actual captures at 1280x720 and larger supported sizes. Cover rarity,
requirements, both rings, two-handed displacement, empty slots, skill states and
multi-grant passives. Comparisons and browsing must not mutate inventory or spend
turns. Use [AGENTS.md](../AGENTS.md#verification) for capture and build procedures.
