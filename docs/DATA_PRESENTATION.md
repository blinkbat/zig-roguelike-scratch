# Item and character information

Research and implementation pass: **2026-10-20**. Diablo II is the main reference for
the amount of information shown at once. PoE2 informs the separation of ordinary
inspection from specialist detail. This governs items, the character sheet, skill
and passive inspection, confirmations and HUD tooltips. Keep balance in source.

## Reference evidence

- Blizzard's [item overview](https://classic.battle.net/diablo2exp/items/) describes
  blue magic item names and distinguishes item quality from the actual properties.
  Its [sword listings](https://classic.battle.net/diablo2exp/items/normal/uswords.shtml)
  group damage, requirements and modifiers into complete item descriptions. These
  are historical reference material, not current D2R balance recommendations.
- Blizzard's [character guide](https://classic.battle.net/diablo2exp/basics/characters.shtml)
  distinguishes character attributes from attack damage, life, mana and defenses.
  Its [item basics](https://classic.battle.net/diablo2exp/items/basics.shtml) also
  records limits of the character damage display. We should copy the hierarchy,
  not preserve an incomplete or misleading damage estimate for authenticity.
- The inspected [original D2 inventory image](https://www.game-over.net/review/july2000/diablo2/Screen0.JPG)
  uses stable equipment positions and a restrained gold/dark shell. Item identity
  remains recognizable within a dense inventory. No Blizzard artwork is copied.
- An inspected [D2 Spirit sword card](https://i.ibb.co/KWW6mL2/Untitled.png) puts
  identity above ordinary weapon properties and requirements, then blue modifier
  lines. Centered text and gaps separate the groups without a grid. This is a
  third-party-hosted game capture used for layout, not a balance source.
- The inspected [PoE2 vendor screenshot](https://i.imgur.com/MYfchKw.png), published
  in this [gold guide](https://dving.net/guides/path-of-exile-2-guides/gold), shows a
  compact Wooden Club card: title, weapon class, a damage range, critical chance
  and attack rate. It does not pad the card with unrelated defensive attributes.
  This is a visual observation of that capture, not a current-client interaction test.
- GGG's [May 2025 plans](https://www.pathofexile.com/forum/view-thread/3783548/filter-account-type/staff)
  explicitly discuss modifier tiers in advanced item display and separating modifier
  sources. Borrow that distinction between everyday reading and specialist detail;
  our prototype does not need tier ratings, crafting metadata or a build calculator.

## Judgment for this game

An item should read like an object with properties. It should not require the player
to reconstruct it from a spreadsheet. First identify it, then read what it does,
then see whether it can be equipped. Keep a stable order and use short, complete
phrases. Dense information is useful when every line earns its place.

The previous helmet panel showed minimum damage, maximum damage, all five possible
modifiers and three requirement attributes, including zeroes. Its WORN/ITEM/DELTA
columns gave a two-modifier item the visual weight of an endgame spreadsheet.
The character sheet's bare `Heavy 14` was ambiguous between damage and a bonus.
Skill tables included zero rank bonuses on utility skills; HUD skill tooltips listed
numbers before explaining the skill. These are the problems this pass addresses.

### The useful complexity

D2's useful density comes from a stable reading order and familiar vocabulary.
Many independent properties can coexist because each line describes one property.
Players can recognize a useful item before doing every calculation. Our basic item
has zero to four rolled modifiers, so it should be especially quick to read.

For example, a magic Iron helm reads in this order:

```text
Iron helm
Helm

Physical damage reduced by 4%
+3 to maximum life
Requires 16 Strength (14 available)

---
+6 to maximum life
+2 to maximum mana

Cold iron and a narrow view.
```

Every item kind carries one dim flavor line after its gameplay properties (`items.Spec.flavor`,
at most `items.FLAVOR_MAX` characters so it fits the compared card). Skills put their `FLAVOR`
after current/next-rank details. Flavor never states a mechanic or interrupts the factual reading order.

Names and headings use Balthazar; compact text at 18px and below uses Source Sans 3.
Item cards share a left edge, group hand/scaling metadata on one small line, keep requirement
availability inline, and use 22px property rows. Metadata and flavor use 17px text; primary
effects stay 18px. Requirement errors follow the actual card height. The character sheet groups
critical chances and point pools; Advanced includes recovery and all elemental bonuses, with zeros dimmed.
The binding picker has its own labeled strip, clear of both skill-set labels, and left-aligned details.

The worn Leather cap remains a separate, much shorter card. This preserves the
objects' identities and shows the real equipping blocker. Selected and equipped cards
show their own properties directly, without an "If equipped" character-change section.
Item cards show the innate bleed chance without a separate bleed-damage line.

Across item, skill, passive and stat panels, show the specific effect, values and
differences. Omit repeated explanations of core rules such as bleed movement damage,
resistance and armour caps, attribute scaling, flask timing or charge refills. Keep
skill-specific exceptions and rank changes; dedicated status inspection owns status definitions.

PoE2's source/tier metadata becomes useful when a player needs to inspect a roll or
craft an item. This prototype has no crafting and a small fixed modifier pool.
Keep that extra detail out of ordinary inspection. If the pool later grows enough
to need roll ranges or provenance, add a deliberate details layer and retain this
short ordinary view.

Keep the character sheet honest: damage bonuses are percentages, critical damage
is a multiplier, and armour is physical reduction. The skill panel supplies actual
hit ranges for the current weapon and rank. There is no invented DPS metric in a
turn-based game, and no single score can decide a Strength/Dexterity tradeoff for
the player's build.

## Presentation contract

1. **Item cards:** name in rare yellow, magic blue or normal pale text; quiet slot
   and handling information; only applicable base properties; only nonzero
   requirements; then a horizontal divider and actual added modifiers in their rarity color; flavor last.
   Base properties and any future built-in base bonuses stay neutral, including on
   magic or rare items. Rare cards show the base name beneath their generated two-part name.
   Item-name rarity color never recolors the base section.
   Damage is one range. A requirement
   uses its full attribute name and red only when unmet. Ordinary items do not need
   an empty modifier section. Do not invent affix names, rarity grades or stats.
2. **Comparisons:** selected and equipped items retain separate identities. Keep
   their cards side by side, with no derived character-change list. Preserve real
   loadout validation, requirement errors and ring destination. No gear score and
   no universal better/worse verdict.
3. **Character sheet:** the main sheet answers "how much life, how much damage, what
   chance to afflict"; everything rarer goes on the Advanced sheet. Three type tiers
   (`character_stats.Tier`): headline numbers engraved large (life, mana, skill hits), key rows
   engraved at body size (attributes, skill names), plain rows in the data face. Colour
   carries meaning: life red, mana blue, each element and status in its own ink, gold
   for gold and unspent points, zeros dim. Attach units to values. Name each
   attribute directly. Damage bonuses explicitly say bonus; critical damage explicitly
   says multiplier. Our armour is physical damage reduction, unlike D2 defense: never
   relabel it Defense.
4. **Skills:** effect first, rank second, current or first-rank properties together,
   then a separate next-rank section containing only changes. Actual hit ranges
   include equipment, attributes and rank, before critical hits and defenses.
   Combat, HUD and tree share `progress.State.blowOf` (`Act.equippedBases` plus rank bonus).
   If an upgrade changes average damage without changing the integer range endpoints,
   show the old/new rank bonus explicitly. State mana, turn and range units. A utility
   skill has no damage line. At maximum rank, remove the empty next-rank section.
   Skill descriptions explain behavior without repeating raw base-hit ranges.
   Keep skill-specific duration, area and proc chance; omit the standard status rules
   already covered by status inspection.
5. **Passives:** name and actual grants lead. Write complete modifier phrases;
   use plain language for the next action or blocker. Topological terms are secondary
   to the grant. Preserve origins, feeders and point costs exactly.
6. **HUD inspection:** behavior before metrics. Resources can use a small labelled
   pair list; skills and ailments need readable descriptions. Omit irrelevant zero
   cost/cooldown/rank lines. Cooldowns and remaining durations always say turns.
7. **Actions:** show the object and consequence before one deliberate action. Use direct
   commands, controller navigation and input glyphs; no secondary confirmation modal.
8. **Hands:** say Main hand and Offhand. The main hand is on the viewer's left of the
   paperdoll; the offhand is on the right. Great weapons, bows, crossbows and staves
   use both hands. Lists say Both hands and cards say Two-handed; an occupied offhand
   names the weapon using it instead of looking empty. Ring destinations remain
   left/right because either ring can use either slot.

Use dark, quiet surfaces, Balthazar headings, Source Sans 3 compact text, native text
sizes and spare dividers. Gold marks focus or section hierarchy, blue marks magic, yellow marks rare items, muted text carries
supporting information, and red marks a real blocker or loss. Do not shrink text to
fit a table that should have been removed. Tables remain appropriate when the reader
actually needs aligned values; they are not the default container for all information.

The owner's global menu direction is **muted gold, never bright yellow**.
`look.UI_GOLD` (`#bca06b`) and `look.UI_FOCUS` (`#d0b581`) are shared by
menus, character pages, trees, naming, binding, HUD inspection and editor controls.
The yellow controller face glyph uses the focus gold too. Keep magic blue and actual
gain/loss colors distinct. UI selection no longer borrows the world targeting color.

## Verification

Inspect real headless captures at 1280x720 and the larger HUD capture sizes. Cover
normal, magic and rare items, unmet and met requirements, both ring destinations,
two-handed displacement, empty slots, each class's skill states, and passive grants.
Check that comparisons do not mutate inventory and that browsing/cancelling spends
nothing. Reuse source calculations and test any new requirement/preview derivation.
Keep screenshots and research downloads in the temporary directory.

Implemented in `ui/book.zig`, `ui/item_card.zig`, `ui/character_stats.zig`,
`ui/trees.zig` and `ui/hud.zig`, with shared geometry in `ui/character_layout.zig` and
damage inputs in `play/skillbar.zig`/`play/progress.zig`, role names in
`play/items.zig`, and the global menu palette in `gfx/look.zig`.

## Direct manipulation and readable scale (2026-10-20)

The input audit found four confirmations to equip, a forced return to play after every item action, a hidden hold to bind, and two back presses just to leave content. These were interface costs without a useful decision.

Character opens directly through its control glyph; the game menu has its own control. Equip, unequip, drop, pickup and point spending have one explicit action. Shoulder glyphs change pages without moving focus through a tab row. Back closes Character. Binding starts from Skills, with the selected learned skill already chosen. A first bump or Interact opens a closed chest for one turn, revealing its items and gold without a modal. Stepping onto a bag or stocked open chest opens its loot modal for the movement turn; Interact browses a sole bag or open chest for free. Ground gold without items uses a coin drop and auto-loots when stepped onto, with no extra turn or modal; Interact can also take a sole coin drop for one turn. Multiple nearby drops, containers and doors use a choice list, and a sole door still lists. Loot shows only the selected cell, with items and a gold row, offering Take item, Take gold and Take all. Each successful pickup action costs one turn; Take all collects gold, fills available inventory space and leaves excess items. Gold needs no inventory space. Movement and browsing never collect gold from bags or chests. An empty loot modal closes. Ground cells containing items use one bag marker, including any gold in that cell. Gold alone uses a coin sprite, without coin lights.

Character and binding panels stay centered and grow at half the rate needed to fill the window, capped at 1.25x. Smaller windows still fit within a 16px margin. At 1600x900 the 1100x640 panel is 1296x754, leaving space around it; 18px detail text and 20px body text become about 21px and 24px. Menu titles, rows and spacing are restrained too. Hit regions and passive clipping use the same transform. Scaled panels use mipmapped type; native-size panels retain the crisp native atlases.

Blizzard explicitly discusses larger type, UI scaling, reducing repeated clicks, bindable interactions and alternatives to holds in its [D2R accessibility article](https://news.blizzard.com/en-us/article/23700733/how-were-making-diablo-ii-resurrectedtm-more-accessible-to-everyone). The [original D2 manual](https://download.blizzard.com/pub/misc/Diablo%20II%20Manual.pdf) describes direct manipulation of equipment. These support the direction; the exact shortcuts above are this project's choices. GGG's [0.2.1 plans](https://www.pathofexile.com/forum/view-thread/3783548/filter-account-type/staff) describe passive search and navigation improvements; they support keeping navigation cheap, without establishing today's controller bindings. Historical player reports in CONTROLLER.md are not treated as an official current map.
