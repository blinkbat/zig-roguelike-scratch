# Diablo II skill-tree reference and panel contract

Research date: **2026-10-19**. Read this document before changing the Skills panel, its
navigation, prerequisite connections, rank presentation, or allocation details. Read
[PROGRESSION.md](PROGRESSION.md) and the current source alongside it. This reference describes
the design being adapted; source code remains authoritative for this game's rules.

The owner's direction is to follow Diablo II's skill-tree system and UI as closely as the
current prototype permits, using **very simple graphics**. The useful model is a compact
map of skills, visible prerequisite paths, repeated investment in a skill, and clear
inspection before spending a scarce point. A textured replica, copied Blizzard artwork,
or an expansion of the game's balance is outside this presentation change.

## Evidence and version boundaries

Three kinds of statements are distinguished below:

- **Verified reference:** mechanics documented by Blizzard, or pixels directly inspected
  in Blizzard's published tree images and original manual.
- **Interpretation:** a reading of why that presentation works. It is design analysis,
  not a claim that Blizzard stated that intention.
- **Project adaptation:** the concrete treatment recommended for this repository,
  constrained by existing mechanics and controller-first interaction.

The principal reference is original Diablo II / Lord of Destruction. The official
[Arreat Summit skill index](https://classic.battle.net/diablo2exp/skills/) links the classic
class trees. Its pages are an archive, not an authoritative description of every current
Resurrected balance value. The original manual predates later changes, including respecs.

D2R also has dated changes worth distinguishing. Blizzard's 2021
[console design article](https://news.blizzard.com/en-us/article/23722094/bringing-the-original-diablo-ii-experience-to-console)
describes direct activation of skills from a controller tray, with a second set giving
twelve slots. Its [Patch 2.3 preview](https://news.blizzard.com/en-us/article/23746020/diablo-ii-resurrected-patch-2-3-highlights-coming-soon)
describes optional keyboard quick casting and an additional binding bar. These describe
execution and binding, not a requirement to change the allocation graph.

The [released Patch 2.4 notes](https://news.blizzard.com/en-gb/article/23788293/diablo-ii-resurrected-patch-2-4-ladder-now-live)
document substantial skill and synergy adjustments, individualized casting delays, and
tooltip additions such as radius and previously hidden passive effects. Do not copy
archived damage tables as current D2R balance. By this research date,
[Reign of the Warlock](https://news.blizzard.com/en-us/article/24243863/rain-annihilation-in-reign-of-the-warlock)
also adds a Warlock with Demon, Eldritch, and Chaos trees and separates gameplay eras.
Consequently, references here to the seven-class roster mean the LoD reference roster,
not a claim about every current D2R product or mode.

## Verified system model

### Class disciplines and the graph

The classic expansion gives each class thirty unique skills divided between three
ten-skill tabs. The tabs group disciplines; they do not require selecting one exclusive
specialization. The names below identify the actual categories rather than invented
generic roles. [Skill basics](https://classic.battle.net/diablo2exp/skills/basics.shtml),
[official class-tree index](https://classic.battle.net/diablo2exp/skills/).

| LoD class | Three disciplines |
|---|---|
| Amazon | Javelin and Spear; Passive and Magic; Bow and Crossbow |
| Assassin | Martial Arts; Shadow Disciplines; Traps |
| Necromancer | Summoning; Poison and Bone; Curses |
| Barbarian | Warcries; Combat Masteries; Combat Skills |
| Sorceress | Cold; Lightning; Fire |
| Druid | Elemental; Shape Shifting; Summoning |
| Paladin | Defensive Auras; Offensive Auras; Combat Skills |

The individual pages expose character-level tiers at 1, 6, 12, 18, 24, and 30. A row can
contain several skills or gaps. For example, the Sorceress Fire page places Fire Bolt and
Warmth at level 1, Fire Ball at 12, Meteor at 24, and Fire Mastery and Hydra at 30. Fire
Ball requires Fire Bolt; a later skill may require several earlier skills. The graph
therefore carries real eligibility information. [Sorceress Fire Spells](https://classic.battle.net/diablo2exp/skills/sorceress-fire.shtml).

The Amazon provides a useful branching example: Exploding Arrow requires Magic Arrow,
Fire Arrow, and Multiple Shot; Ice Arrow follows Cold Arrow. Separate paths and joining
paths both matter. The diagram is not a list whose items happen to be connected.
[Amazon Bow and Crossbow Skills](https://classic.battle.net/diablo2exp/skills/amazon-bow.shtml).

### Investment, eligibility, and related bonuses

A level grants one skill point. Points can be saved. A skill accepts at most twenty
allocated points, and its character-level requirement also limits subsequent investments:
a skill first available at character level 6 cannot receive its second allocated point
until level 7. Thus spare points alone do not guarantee an upgrade is legal.
[Skills FAQ](https://classic.battle.net/diablo2exp/faq/skills.shtml).

Prerequisites require allocated points; an item-granted skill does not unlock its
descendants. Equipment and temporary effects can raise effective skill levels beyond
the allocation cap. Synergies are another relationship: allocated points in specified
skills improve another skill, while equipment bonuses do not add to those synergy
bonuses. A prerequisite arrow and a synergy bonus must not be treated as interchangeable.
[Skill basics](https://classic.battle.net/diablo2exp/skills/basics.shtml).

The original permanent-choice model was later supplemented by respecs: the official
guide records a system added in 2010, available through the Den of Evil reward and a
Token of Absolution. This repository still defers respec. A reference to early Diablo II
permanence must not be generalized into a claim that LoD never permitted resets.
[Skill basics](https://classic.battle.net/diablo2exp/skills/basics.shtml).

Blizzard's planning advice explicitly discusses concentrating points in selected skills,
spending for prerequisite access, and saving for later unlocks. **Interpretation:** the
whole tree supports planning because the player can see future destinations before
being able to buy them. Hiding locked nodes would discard this useful property.
[Skill Point Spending Strategies](https://classic.battle.net/diablo2exp/skills/skillplanning.shtml).

### Inspection and allocation

The original manual's printed pages 30-31 describe right-side discipline tabs, a remaining
point count, and a hover description containing the effect, damage, range, and mana cost.
For a learned skill, the description also explains the next-level improvement. A click
spends one available point; without available points it instead assigns the skill to the
right action icon. The manual warns that allocations are permanent in that version.
These are historical behaviors, not all behaviors to reproduce here.
[Blizzard's Diablo II manual](https://download.blizzard.com/pub/misc/Diablo%20II%20Manual.pdf).

The official character guide also directs players to inspect available skills before
allocating and identifies eligible skills with white text. This supports a distinction
between eligibility and possession, but does not establish a universal color scheme for
every icon state or every later version.
[Character Information](https://classic.battle.net/diablo2exp/basics/characters.shtml).

## What was actually inspected visually

The following are Blizzard-hosted original tree images, inspected at native resolution.
They are useful static diagrams of the UI. They omit the live allocation overlays and
hover tooltip; do not infer exact live rank-counter placement or unavailable-state colors
from their absence. The manual page was also rendered and inspected, including its small
in-game panel illustration. Reference downloads and renders stay in the system temporary
directory; none is a runtime asset.

| Reference | Observed visual evidence |
|---|---|
| [Sorceress Fire tree](https://classic.battle.net/images/battle/diablo2exp/images/sorceress/sorceress-fire.jpg) | A 321 by 432 image; approximately 48-pixel square symbol tiles; three sparse columns and six vertical tiers; dark arrow paths; a class plaque and three large category areas on the right. |
| [Amazon Bow tree](https://classic.battle.net/images/battle/diablo2exp/images/amazon/amazon-bow.jpg) | Uneven distribution of skills among columns; long vertical routes and branching or diagonal connections; deliberate empty spaces; the selected category occupies the lower right part of the frame. |
| [Paladin Combat tree](https://classic.battle.net/images/battle/diablo2exp/images/paladin/paladin-combat.jpg) | Similar dimensions and framing but a different graph; paths converge and traverse multiple rows; icon silhouettes remain the focal elements despite a stone-textured background. |

The symbols are predominantly light against dark tile faces. Narrow highlighted edges
suggest inset sockets. The backdrop and connecting paths are lower contrast than the
icons. A name and paragraph do not occupy every node. The large right-side category
shapes identify the current discipline separately from the graph. These observations are
drawn from the three linked images, not from an imagined modern reconstruction.

**Interpretation:** the recognizable structure is the relationship between small square
symbols, generous gaps, descending connections, and a separate place for explanation.
The stone texture and ornament provide atmosphere but are not necessary to communicate
the tree. In this prototype, preserve that structure with flat rectangles, lines, simple
arrowheads, and the game's existing skill symbols.

## Mapping to the actual prototype

This section describes the source as researched, not a request to change it. Recheck
[progress.zig](../src/play/progress.zig) whenever it changes. `progress.skills(class)` owns
each node's action, parent, initial flag, and logical `at` position. `State.canLearn` and
`State.learn` own whether a point may be spent. The renderer must not reconstruct a
second allocation policy. [trees.zig](../src/ui/trees.zig) draws the panels, while
[book.zig](../src/ui/book.zig) owns their navigation and direct actions.

| Concept | Diablo II reference | Current prototype treatment |
|---|---|---|
| Scope | Three discipline trees per class | One active tree per class, with 10 Archer, 11 Wizard, or 8 Knight skills |
| Investment | Repeated points in a skill | `progress.RANKS` is 3; display its actual value |
| Progression budget | Skill points earned through progression | Each level grants one active and one passive point; the pools stay distinct |
| Unlock path | Prerequisites and character-level tiers | At most one parent per active node; parent must be learned; no character-level gate |
| Starting knowledge | Version/class-specific starting abilities | Initial nodes begin at rank 1, before any earned active points |
| Categories | Discipline tabs | Existing Character tabs navigate real systems; no decorative fake discipline tabs |
| Synergy | Separate cross-skill bonus rules | None; a connection indicates only a prerequisite |
| Extra skill levels | Equipment and temporary bonuses | No separate equipment-granted rank model |
| Passives | Skills inside class disciplines | Separate shared radial graph with three class starts and six branches |
| Reset | Version-dependent respec facilities | Deferred; no reset control should appear |

The current active graphs are:

Shoot is a fixed basic attack, like bump melee. It remains the archer's bindable starting
attack and a prerequisite anchor, but cannot spend active points or gain damage from ranks.
Its node and details say Basic rather than offering rank upgrades.

| Class | Starting nodes | Connections |
|---|---|---|
| Archer | Shoot, Juke | Shoot -> Burning Arrow -> Barbed Arrow; Shoot -> Steady Aim -> Overwatch; Shoot -> Glacial Shot -> Pinning Shot, Piercing Shot; Juke -> Caltrops |
| Wizard | Spark, Blink | Spark -> Fireball -> Combustion, Fire Wall; Spark -> Chain Lightning; Blink -> Frost Nova -> Shatter, Gravity Well; Blink -> Mana Shield -> Arcane Barrier |
| Knight | Charge, Cleave | Charge -> Shield Bash -> Whirlwind; Cleave -> Guard -> Unyielding; Cleave -> Rend -> War Cry |

The active trees use up to five columns and three logical rows, each class centred on its own
column count, placing preparation and
simple defenses before reactive stances and battlefield control. Preserve `Skill.at`
rather than sorting by name, unlock state, or rank.
Independent roots should remain visibly independent. Learning a node must not cause the
other nodes to move. The tree needs no scrolling at its present size.

`State.unlocked` also recognizes innate actions: Wait, the secondary-set modifier, and
both flasks. These do not become tree nodes. Class kits and binding availability remain
the responsibility of [skillbar.zig](../src/play/skillbar.zig) and progression. Preserve
existing binding behavior after learning; displaying a tree icon does not make it a
playable hotbar button.

Rank increases currently add 20 percentage points of damage bonus and reduce base mana
cost by 10 percentage points per rank beyond the first. Costs round up to whole mana,
with a minimum of 1 for paid skills; some ranks therefore share the same displayed cost. Non-damaging skills with a
cooldown can shorten it, subject to the existing floor; damaging-skill cooldowns retain
their existing value. Treat these numbers as a dated description, not duplicated UI
constants. Obtain values from `damageBonus`, `cost`, and `cooldown`. A rank-zero skill's
base values are a learning preview, not proof that the hero can already use it.

The separate passive graph follows this project's adaptation of the sibling Soulslike
tree, not Diablo II's active-skill layout. Read [POE2_PASSIVE_TREE.md](POE2_PASSIVE_TREE.md)
for that panel's maintained reference. [passives.zig](../src/play/passives.zig) owns
its 81 nodes: three class roots, two twelve-node branches per class, and six bridges.
Each branch's six rings contain 1, 2, 3, 3, 2, and 1 nodes. The two bridges between each
pair of class regions connect branch rings 3 and 5. There is no central hub; all three
class roots are directly available. Stat, interest, and capstone are semantic node
tiers; they must remain distinct even when a capstone grants an attribute rather than
a special damage bonus.

`feeders` defines allocation direction. A branch normally grows outward from an owned
feeder; bridges can be entered from either adjoining anchor and can feed either anchor
on the far side. Drawn links and allocation checks both read `feeders`. `State.available`, `State.allocate`, and `bonusAt` remain
the transaction authority. The current class root begins owned and adds no bonus beyond
the class's base attributes. Either other class root can be purchased for one passive
point without a feeder. Every other purchased node also costs one passive point and
applies its actual primary grant and optional additional grant. Render the existing
grant values and eligibility; do not infer a new gate, class restriction, or cost from
the graph's appearance. If both panels share visual helpers, keep their different
layout and allocation semantics explicit.

## Simple visual specification for this repository

These are project adaptations. They deliberately translate the reference into the
current number of skills, existing character book, native font, and simple artwork.

### Composition and hierarchy

1. Keep the character-book shell and real tabs. Give the tree a clear class heading and
   an easily found active-point balance. The heading must not compete with skill details.
2. Use the left region as a graph canvas and the right region as a persistent inspection
   panel. This gives controller focus the same information a hover tooltip supplies.
3. Center the authored graph within its region. Reserve enough room around its edges for
   names, rank plaques, arrow bends, and the focus border. Keep the Knight's smaller graph compact.
4. Draw connections first, then sockets, then focus, then symbols, then rank plaques, so a
   plaque sits over the focus border's corner.
   Lines should end outside tiles and text; they should not run through an icon.
5. Keep explanatory text beside the graph. Compact names near tiles are acceptable, but
   full descriptions inside every tile would turn the map back into a stack of cards.

A 56-pixel square socket is an appropriate working size in the existing book. It is a
project choice, not an exact D2R measurement. Use the established skill icon renderer;
center its native symbol without smearing it. A one-pixel highlight and darker opposite
edge can suggest a shallow inset. Do not add stone bitmaps, elaborate frames, particle
glow, animated flourishes, or replacement AI-generated icons.

The rank plaque is a small attached rectangle containing `rank / maximum`, for example
`1/3`. Derive both values. Keep it readable on locked and maximum nodes. Its placement
and denominator are an adaptation for this small rank system, not a documented exact
copy of the archived diagrams. A visible numeral is more dependable than color alone.

### Connections

Each `parent` produces one unambiguous parent-to-child connection. Use a restrained line
with a small directional arrowhead at the child. Vertical routes may use a short
horizontal segment to resolve branching. A connector can brighten when its prerequisite
is satisfied; that does not mean the child is owned or that a point is available. Two
children must remain separately legible where a fork joins. Avoid ornamental connectors
to independent roots or through empty invented nodes.

Use subdued neutral borders and paths with the existing warm highlight for attention.
The map should remain readable without interpreting hue: rank numerals, a focus outline,
and the detail-panel state provide redundant cues. The maximum skill state should feel
complete rather than disabled. No flashing is needed to announce a spendable point.

### State model

Ownership, eligibility, and focus are separate facts. A learned node can be focused with
no spare points; an unlearned node can be inspected while blocked; a maximum node remains
inspectable. Render these combinations without collapsing them into one enabled flag.

| State | Node treatment | Detail/action treatment |
|---|---|---|
| Parent missing | Muted symbol and rank zero | Identify the required skill; allocation unavailable |
| Parent met, no points | Legible node, no spend accent | State that no active points remain |
| Learnable, rank zero | Clear symbol and restrained eligible accent | Offer Learn and a rank-one preview |
| Learned, below maximum | Normal symbol and actual rank | Offer Upgrade only when `canLearn` succeeds |
| Maximum rank | Normal symbol with complete rank plaque | State Maximum rank; no fictitious next upgrade |
| Focused | Additional outline independent of all above | Show this node's complete inspection information |

For conflicting blockers, choose a stable explanation order: maximum, unmet prerequisite,
then no points. This is a presentation recommendation; `canLearn` remains the authority.
Use precise, short labels. Do not tell the player to press a named key or controller
button in prose; existing input-icon rules continue to apply.

## Inspection content and interaction contract

The detail panel should answer five questions: what the skill does, what is currently
owned, what the next point changes, why spending is or is not possible, and how many
points remain. Its main title is the skill name, with rank just below. Explain its
effect before the numeric properties, then show prerequisite/state and the point budget. Follow
[DATA_PRESENTATION.md](DATA_PRESENTATION.md): the 2026-10-20 pass replaces the fixed
current/next table with labelled current/first-rank properties and a separate next-rank
section containing only changes. This leaves utility skills and maximum ranks free of
irrelevant zeroes and empty columns.

Descriptions keep the skill's specific effect and exceptions. Do not repeat core status,
resistance, damage-scaling or flask rules; the current/next rows show the actual values and changes.

Use `Act.describe` with combined equipment and passive perks for behavior (`Gear.perks` in
the tree, `Simulation.heroPerks` in the HUD). Mana and cooldown must come from the hero's
progression state through `State.writeUsage`. Show turn cost in turns, not seconds.
Where actual damage ranges are displayed, share gameplay's attribute/weapon/rank
calculation through `State.preparedBlow` (and `State.preparedHit` for its spans), passing
the hero's current Steady Aim preparation; do not label raw base
damage as the hero's final result. Show actual physical/elemental ranges before
critical hits and defenses. When a rank improves average damage but its integer
range endpoints stay unchanged, show the old/new `Rank damage bonus` explicitly.

For an unlearned skill, label the available values as the first rank's preview. For a
maximum skill, or a rank that changes nothing shown, omit the next-rank section rather than
duplicating the current numbers under a misleading upgrade heading. Basic attacks show no
reason line or action button, and a maximum skill no reason line; their rank row already says so. Unchanged values should remain calm and
readable; the one value affected by the next point should be easy to compare. Any
description wrapping must account for the action footer. Keep rank-dependent length and
duration in the property and next-rank rows instead of repeating them in behavior prose,
so the details stay above the binding action. Combine a changed mana cost with
the next-rank damage or cooldown paragraph to preserve that space.

The selected eligible skill spends one point on one deliberate confirm press. There is no secondary confirmation modal. Browsing, backing out and allocation spend no simulation turn; only a successful `State.learn` reduces the point pool. Details show the result before spending.

Controller movement should follow visible geometry via the existing directional
navigation helper, including locked nodes. A player must be able to inspect future
skills before acquiring their parents. Pointer and keyboard navigation should converge
on the same selected node and details. Focus must survive a successful allocation so
the player can immediately inspect its result. Shoulders change tabs directly and Back closes the book. The centered panel grows at half the window-fitting rate, capped at 1.25x, with 18px detail and 20px body text before scaling. Scaled text uses the mipmapped font atlas; native-size panels retain the crisp native atlases.

The separate Bind skill action carries the selected learned skill straight into the slot picker. Binding is available regardless of unspent points, and returns to Skills. The utility-skill picker remains available. This keeps learning and binding explicit while removing the hidden hold entry. Larger text and UI scaling also follow Blizzard's stated readability work.
[D2R accessibility article](https://news.blizzard.com/en-us/article/23700733/how-were-making-diablo-ii-resurrectedtm-more-accessible-to-everyone).

Clicking a skill selects its inspection details; pointer movement preserves the
selection while approaching an action. Click the visible Learn/Upgrade
action to spend one point, or Bind skill to assign it. Tabs and shoulder glyphs are
clickable, and right-click closes the book without spending a turn.

## Acceptance and future work

Before handing off a panel change, inspect actual headless captures, including all three
classes. A visual resemblance is insufficient if its state cues contradict the model.
Use the repository's build and screenshot workflow; temporary captures belong outside
the repository. The completed UI should meet these checks:

- The graph has exactly the current source nodes and prerequisite edges; independent
  roots stay independent and no connection suggests an unimplemented synergy.
- Learned, unlearned-but-available, prerequisite-blocked, no-points, maximum, and focused
  states are distinguishable, including a focused locked node.
- Rank numerals and point totals are visible, use real values, and update after a spend.
- The detail panel includes behavior and a truthful first/current/next-rank comparison.
  A maximum node does not advertise an additional rank.
- The Knight's independent Cleave and Archer branch from Shoot remain understandable without reading
  source code. The Wizard's two paths do not accidentally connect.
- Controller direction and pointer hit regions match what is drawn. No invisible old
  card-sized targets survive a change to square nodes.
- Browsing/backing out changes neither ranks nor points. One deliberate confirmation spends
  exactly one point; repeat input does not silently allocate several ranks.
- No point allocation advances foes, recovery, cooldowns, travel, or the hidden clock.
- New skills remain governed by existing bind availability. Revisiting the panel and
  save/load preserve allocations and correct details.
- Text fits at the supported screen sizes. Borders, badges, connections, and descriptions
  do not collide. Use readable native font sizes before adding decoration.
- Passive presentation, if touched, preserves its directed feeders, two-way bridges, free class
  start, separate budget, and current allocation behavior.

For later changes, begin by reading this document and the source symbols it names. If a
mechanic changes, update the mapping table and state treatment in the same work. New
skills belong in `progress.skills` and the normal skill metadata first; do not encode
them only in a renderer. Derive extents and iteration from data rather than hardcoding
six skills or two columns into a reusable helper.

If the owner later requests discipline tabs, level gates, additional ranks, synergy
bonuses, gear-granted skills, or respec, treat each as a gameplay design change. Update
eligibility, saves, previews, tooltips, and tests together. A decorative D2-like cue must
never imply a rule the simulation does not implement. Maintain this document as a
durable reference: replace stale guidance, cite any newly inspected version, and keep
temporary research artifacts out of the repository.
