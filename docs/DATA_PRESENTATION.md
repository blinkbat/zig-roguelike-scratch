# Item and character information

Show identity, effect, relevant values and one action or blocker. Derive previews from gameplay calculations. Omit flavor text, repeated rules and permanent control legends. [UI requirements](../AGENTS.md#ui-restraint--foundational-requirement)

## Shared presentation

- Use Balthazar for names and headings and Source Sans 3 for compact text at 18px and below. Native panels use crisp atlases. Scaled panels use mipmapped faces. Character and binding panels grow at half the window-fitting rate up to 1.25×, with a 16px margin in smaller windows. Drawing, clipping and hit-testing share the transform.
- Use muted gold for menus and focus, blue for magic items, yellow for rares, and red for unmet requirements or losses. Dim zero values. Preserve readable locked-skill names. Show controls as device glyphs. [Colors and surface depth](../src/gfx/look.zig)
- Combat keywords use physical, mental/chaos, fire, cold and lightning hues. Phrase colors survive wrapping and scrolling, inherit paragraph brightness and opacity, and preserve red blockers and item rarity. Keep generic metrics neutral. Label damage bonuses and armour reduction as percentages, critical damage as a multiplier, and cooldowns and durations in turns. [Keyword colors](../src/gfx/text_keywords.zig)
- Status cards lead with the effect, then show only applicable underlined group words (Wounds, Slows, Mental, Elemental). Hover or Inspect opens the definition and group membership above the parent. Back dismisses the definition first. Keyword hit regions share the text transform. Each higher surface is more opaque. Advanced Stats exposes the groups even when no status is active. [Membership](../src/play/resilience.zig) · [Keyword inspection](../src/ui/keywords.zig)

## Items and equipment

Place the selected and equipped cards side by side with aligned content, 17px metadata, 18px effects and 22px property rows. Keep comparison tied to the chosen ring destination. Leave derived gear scores and hypothetical change lists out of the cards. [Item card](../src/ui/item_card.zig)

1. Show the rarity-colored name and, for rares, the base name. Follow with slot, handedness and scaling.
2. Show applicable base properties and fixed innate effects. Damage uses one range. Innate bleed chance occupies one line.
3. Show nonzero requirements with full attribute names. Compute availability after displacing equipment and excluding the candidate's own bonuses. Show available points inline for unmet requirements and position errors below the card's actual contents.
4. If rolled modifiers exist, add a divider and their actual values. Preserve keyword hues within rarity-colored text.

The paperdoll puts helm at upper center, amulet upper right and chest beneath helm. Main hand and Offhand sit at the edges. The lower row runs Gloves, right ring, Belt, left ring, Boots. Saved slot identities are `right_hand` and `left_hand`. Lists say “Both hands” and cards say “Two-handed”. The occupied offhand shows the two-hander's name and faded glyph. Empty slots use faded slot glyphs, equipped items use rarity colors and inventory rows lead with the item glyph.

## Character, skills and HUD

| Surface | Reading order |
| --- | --- |
| Main Stats | Life, mana, defenses, attributes and progression. Learned skills show their hit ranges and one chance per ailment, combining the skill and weapon rolls. Critical chances follow the skill list. |
| Advanced Stats | Damage bonuses, critical multiplier, recovery, elemental and status resistances, including dim zeroes. Two columns group statuses under inspectable headings. List Maim under Wounds and Chill under Elemental once, with percentage and remaining turns. Inspection retains all memberships. |
| Skills | Effect, rank, current or first-rank properties, then only next-rank changes. Hit ranges include equipment, attributes, preparation and rank before critical hits and defenses. Show old/new rank bonuses if only average damage changes. Utility skills omit damage. At maximum rank omit the next-rank section. |
| Passives | Actual grants and riders, essential exceptions, then one action or blocker. Preserve origins, feeders and costs. |
| Binding picker | Keep the visible range count clear of set labels and align details left. |
| HUD inspection | Behavior before metrics. Omit irrelevant zero costs, cooldowns and ranks. Use ordinary phrases for free actions, remaining drinks and turns until ready. Unit cards show name, pictured HP, then the tile and its signed effects. |

The stat sheet, tree rules and HUD layout have separate owners. [Stats rendering](../src/ui/character_stats.zig) · [Active skills](DIABLO2_SKILL_TREE.md) · [Passives](POE2_PASSIVE_TREE.md) · [HUD timing](HUD_LAYOUT.md)

## Actions and verification

Equip, unequip, drop and point allocation each take one deliberate action. Browsing, comparing and binding spend no turns. Check rendered cards at 1280×720 and larger sizes for rarity, unmet requirements, both rings, two-handed displacement, empty slots, skill states and multi-grant passives. [Controls](CONTROLLER.md) · [Loot transactions](PROGRESSION.md) · [Builds and captures](../AGENTS.md#verification)
