# Passive tree reference: Path of Exile 2 and the local adaptation

Research date: **2026-10-19**. Read this document before changing the Passives panel,
its graph, node presentation, inspection, or navigation. It is a design reference,
not a second balance table. The authored graph and grants remain in
[`passives.zig`](../src/play/passives.zig), point allocation in
[`progress.zig`](../src/play/progress.zig), derived attributes in
[`attrs.zig`](../src/play/attrs.zig), and the broader progression contract in
[`PROGRESSION.md`](PROGRESSION.md).

The intended result is a legible network of meaningful choices with very simple
graphics. PoE2 supplies the reference for reading a large passive graph. The owner's
[`zig-soulslike/passivetree.zig`](../../zig-soulslike/src/play/passivetree.zig)
supplies the more directly applicable three-arm structure, stat nodes, interest
nodes, capstones, and bridges. These are distinct sources: neither makes the other
game's combat rules applicable here.

## Evidence and version boundaries

The following sources were read during this study. The two linked screenshots were
downloaded to a temporary directory and visually inspected. They are historical
captures, not proof of the current live client's precise controls.

| Source | What it establishes |
|---|---|
| [GGG developer data documentation](https://www.pathofexile.com/developer/docs/data) | Identifies GGG's separate, official PoE2 passive-tree export; do not substitute the PoE1 export |
| [Pinned PoE2 data export](https://github.com/grindinggear/poe2-skilltree-export/blob/bd87e6512c92b868542eddfb1ba4ea8b6dc2da36/data.json) | Machine-readable graph, node categories, class-related data and attribute choices; inspected commit is labelled `0.5.5`, dated 2026-09-04 |
| [GGG's PoE2 product description](https://store.steampowered.com/app/2694490/Path_of_Exile_2/) | Shared progression orientation, flexible class development, active/support gems, and dual specialisation |
| [GGG 0.1.0e notes](https://www.pathofexile.com/forum/view-thread/3645467) | Historical confirmation of gold-based passive refunds and changes to their cost curve |
| [GGG's upcoming 0.2.1 plans](https://www.pathofexile.com/forum/view-thread/3783548/filter-account-type/staff) | Search navigation and match emphasis described by the developer on 2025-05-21 |
| [GGG 0.4.0 notes](https://www.pathofexile.com/forum/view-thread/3883495/page/1) | Examples of clusters, class-region changes, moved nodes and forced refunds after graph changes |
| [Player's original forum post](https://www.pathofexile.com/forum/view-thread/3647932), [passive screenshot](https://i.imgur.com/bc4xq58.png), [Ascendancy screenshot](https://i.imgur.com/Ca4NbEi.png) | Firsthand visual evidence of an in-game December 2024 layout, rather than developer statements about its rules |

The export version is a reproducible research snapshot, **not a declaration of the
latest live game version**. Marketing counts and early-access patch behavior can
change. The [official browser tree](https://pathofexile2.com/game/passive-skill-tree)
was located, but its interactive application was unavailable in this research
environment. No live-client pan, zoom, allocation, or refund interaction was tested.

In the sections below, **verified reference** means a claim supported by these
sources; **design interpretation** means a conclusion drawn for this project.
Local source inspection establishes what our games actually implement. Recheck a
source before turning a historical feature or proposed behavior into a new rule.

## The PoE2 system to understand

### Shared geography and routes

**Verified reference.** PoE2 presents classes as starting orientations within a
shared passive system, associated with Strength, Dexterity, Intelligence and their
combinations. Class identity does not prohibit building toward other specialties.
Its active skill and support gem systems are separate from this passive graph.
[GGG product description](https://store.steampowered.com/app/2694490/Path_of_Exile_2/).

**Design interpretation.** A shared graph gives geography a cost. A desirable
destination is evaluated together with the connecting purchases, neighboring
alternatives, and what those purchases enable next. The interface must communicate
this route structure before it asks the player to compare individual bonuses.
Disconnected-looking cards obscure that decision. Conversely, drawing a line that
does not represent a legal connection promises a route the rules cannot honor.

Class starts should be stable landmarks. Regional identity helps a player remember
where to look, but should not look like a hard class lock when crossing is legal.
Likewise, a nearby node is not necessarily reachable: topology, not screen distance,
decides allocation. Exceptions to ordinary pathing need explicit mechanics and
explanation; they should not be inferred from visual proximity or borrowed lore.

### Attributes and node categories

**Verified reference.** The inspected export distinguishes generic attribute nodes,
Notables, Keystones, jewel sockets, class starts and Ascendancy-related nodes. It
contains selectable attribute alternatives, class-dependent overrides, and separate
group positions and graph connections. Thus a shared tree need not make every
class's immediate starting details identical.
[Pinned GGG export](https://github.com/grindinggear/poe2-skilltree-export/blob/bd87e6512c92b868542eddfb1ba4ea8b6dc2da36/data.json).

Use this conceptual vocabulary carefully:

| Concept | Useful design meaning | Consequence for our adaptation |
|---|---|---|
| Small passive | A modest benefit that also participates in a route | Small, simple mark; full values belong in inspection |
| Attribute node | Attribute investment can also serve traversal | Our stat nodes grant their authored attribute; no choice picker is implied |
| Notable | A named destination worth noticing within a specialty | Our interest nodes can provide intermediate landmarks, without claiming exact PoE2 equivalence |
| Keystone | A substantial rule change, sometimes involving a tradeoff | Do not give this label to an ordinary larger numerical reward |
| Jewel socket | A place for item-driven customization | No empty socket, insertion action, or jewel inventory until implemented |
| Class start | An origin and orientation landmark | Distinguish the selected class's free start from a purchasable reward |
| Ascendancy | A separate class specialization concept | Our active skill ranks are not Ascendancies |

For example, the export's Blood Magic changes the mana/cost relationship, while
jewel sockets are separately marked nodes. The presence of a `isMastery` field
alone does not establish a PoE1-style selectable mastery menu in PoE2.
[Pinned GGG export](https://github.com/grindinggear/poe2-skilltree-export/blob/bd87e6512c92b868542eddfb1ba4ea8b6dc2da36/data.json).

The distinction matters more than copied terminology. Size should tell the truth
about a node's role. A capstone is the culmination of a local branch; it need not
change the game's rules. An interest node is a local authoring category for a named
benefit, potentially with a stat rider. Neither automatically becomes a PoE2
Notable or Keystone because it is drawn larger.

### Weapon sets, refunds and search

**Verified reference.** GGG describes dual specialisation as assigning some passive
points differently for different weapon configurations, with the appropriate
configuration engaged as the relevant skills or weapons are used. This supports
specializing more than one combat approach within a character; it is not evidence
for two unrelated, unrestricted full trees.
[GGG product description](https://store.steampowered.com/app/2694490/Path_of_Exile_2/).

The December 2024 0.1.0e notes changed gold refund costs, especially at higher levels.
That confirms a historical gold respec system; it does not establish today's prices,
NPC flow, or every refund restriction. The December 2025 0.4.0 notes demonstrate
that tree geography and special class interactions can change between versions,
including refunding affected allocations.
[0.1.0e notes](https://www.pathofexile.com/forum/view-thread/3645467),
[0.4.0 notes](https://www.pathofexile.com/forum/view-thread/3883495/page/1).

GGG's May 2025 announcement described searching by text, moving to a match, cycling
through multiple matches, and darkening nonmatches. This is a verified developer
description of planned 0.2.1 behavior, not a hands-on verification of the current
client. Its useful principle is that search supports spatial discovery while
retaining graph context.
[Upcoming 0.2.1 plans](https://www.pathofexile.com/forum/view-thread/3783548/filter-account-type/staff).

Our panel should expose none of these systems speculatively. There are no passive
weapon-set allocations, jewels, respec economy, or Ascendancies in this adaptation.
Search can be considered if the tree becomes difficult to browse, but a decorative
search box with no working navigation is not parity. Exact PoE2 point limits,
campaign awards, weapon-set restrictions and present-day refund details remain
outside the verified scope of this document.

## What the actual reference images show

The inspected passive screenshot has a very dark canvas, tiny circular nodes,
muted unallocated links, and brighter warm routes through allocated nodes. Groups
form irregular loops, arcs and connecting paths. Empty space separates groups;
every node is not accompanied by its full name and stat text. Compact counters and
search sit at the edge of the canvas. The separate Ascendancy capture uses a much
smaller composition with stronger size differences and substantial illustration.
These are observations of those captures only.
[Passive capture](https://i.imgur.com/bc4xq58.png),
[Ascendancy capture](https://i.imgur.com/Ca4NbEi.png),
[original post and date](https://www.pathofexile.com/forum/view-thread/3647932).

**Design interpretation.** The transferable quality is hierarchy and route clarity.
The eye first finds the player's invested route, then its next choices, then remote
destinations. A uniform bright web reverses this hierarchy. Large empty regions
are useful when they separate choices, but unnecessary decorative emptiness makes
a small tree harder to use.

Clusters serve three jobs: they group related rewards, provide recognizable shapes,
and separate local decisions from travel between specialties. Loops offer visible
alternatives. Narrow connections communicate commitment. A broad branch should
visually split where a player has a choice and converge where its capstone is a
shared destination. The drawing should follow those relationships rather than
arranging arbitrary nodes into attractive constellations.

The project's graphics should remain simpler than either reference image. Flat
fills, restrained lines, circles, a few basic symbols and readable text can carry
all necessary information. No new portrait painting, elaborate frame, animated
energy cloud, parchment texture, or copied game artwork is necessary.

## The sibling implementation to lift

The owner explicitly chose the existing
[`zig-soulslike` passive implementation](../../zig-soulslike/src/play/passivetree.zig)
as the structural model. This replaces the earlier radius-four, 61-node hexagonal
lattice as the design target. The old lattice had regional stat bonuses and true
adjacency, but no authored branches, interest hierarchy, or capstone destinations.
Do not retain its visual uniformity as a requirement for the new tree.

### Authored topology

The sibling defines three arms and two branches per arm. Each branch has six
successive layers with widths **1, 2, 3, 3, 2, 1**, giving twelve branch nodes. An
arm has one origin plus twenty-four branch nodes. Six additional nodes connect the
three seams, yielding **81 nodes: 3 x (1 + 2 x 12) + 6**. Each of the six final
branch nodes is a capstone.

Local reward and name tables are keyed by their branch, arm or seam enum. Node
counts derive from the ring widths and enum sizes; preserve node order when
changing the authoring code so saved allocations keep the same meaning.

| Sibling arm | Branches | Structural intent to retain |
|---|---|---|
| Warrior | Life and berserk | A durable route and an offensive route |
| Rogue | Evasion and ranged | A defensive route and a ranged route |
| Wizard | Well and casting | A resource route and a magical offense route |

Our class names are Knight, Archer and Wizard. The adapted branch names are
Fortitude, Might, Agility, Finesse, Reserves and Sorcery. Branch effects must
suit our existing systems; the sibling's branch themes are not permission to invent
stamina, real-time movement speed, poise, or new combat triggers.

Within a branch, `feeders` derives links from overlap between adjacent layer slots.
This creates widening alternatives and subsequent convergence without a hand-kept
list of edges. At layers three and five, bridge nodes connect the facing outer
slots of neighboring arms. A bridge is usable from either side and provides access
to the far anchor; the two depths offer different crossing routes. The inspected
source includes tests for these relationships and for reaching every node.
[Sibling topology and tests](../../zig-soulslike/src/play/passivetree.zig).

This is stronger structural borrowing than merely copying circular nodes. Retain
the branch silhouettes, shared destinations and real lateral routes. Derive both
the picture and allocation rules from the same relationships. Branch prerequisites
advance outward: owning a later node does not satisfy an earlier node's inward
prerequisites. Bridge-to-anchor access works in both directions, allowing entry at
that depth and further outward progression. Small arrowheads on branch links should
communicate that difference; bridge links must not promise unrestricted backtracking.
Unrelated geometric neighbors must not become connected because they nearly touch.

### Node hierarchy and stat riders

The sibling distinguishes pure attribute grants, other interesting grants, bridge
nodes and terminal `key` nodes. Its radii are respectively 0.15, 0.21, 0.23 and 0.30
in graph units. These ratios are useful evidence for hierarchy, not mandated pixel
sizes. Its `Bump` is an additional attribute grant applied to the actual character
sheet. It is not decorative subtitle text.
[Sibling node model and rendering](../../zig-soulslike/src/play/passivetree.zig).

The local adaptation uses explicit **stat, interest and capstone** roles in
[`passives.zig`](../src/play/passives.zig). A seam additionally identifies a bridge.
An interest node may combine a supported
benefit with an attribute rider; inspection must show both, and runtime evaluation
must apply both. Bridge rewards may represent both connected regions. Avoid
splitting the same attribute into two redundant lines just to imitate a rider.

The source's capstones range from stronger numerical benefits to special effects.
Our capstones are supported end-of-branch packages, without implied rule-changing
tradeoffs. Call them capstones. Their larger shape marks their place and authored
importance; it must not promise an absent special mechanic.

### Rules that stay local

The sibling buys nodes with souls and couples purchases to its level economy.
Cistern instead keeps XP progression, separate passive and active point
pools, and its selected class's free starting allocation. Copying the graph does
not copy the sibling economy or all its grants.

Supported reward vocabulary comes from the local implementation: Strength,
Dexterity, Intelligence, life, mana, armour, and the existing damage-by-style bonus.
Heavy weapon damage scales with Strength and light weapon damage with Dexterity;
either group can contain melee and ranged weapons. The Might and Finesse damage
grants follow those groups, so crossbows can benefit from Strength and daggers
from Dexterity. Spell damage retains Intelligence scaling.
Values, stacking and descriptions must come from source. Do not translate a
real-time sibling bonus into a turn-based one by guesswork. No life allocation
heals current HP merely because the maximum rises.
[Authored grants](../src/play/passives.zig), [local progression](../src/play/progress.zig), [attributes](../src/play/attrs.zig),
[progression rules](PROGRESSION.md).

The selected class's origin starts allocated and contributes no additional grant;
its base attributes already establish the starting character. Both other origins
are immediately available as purchases, each costing one passive point and granting
two points of its arm's attribute. This deliberately retains the sibling's open
origin choices. A bridge is a shortcut into a deeper branch, not the sole way to
enter another arm. All non-origin nodes require at least one allocated feeder;
allocation also requires a passive point. The visual distinction between reachable
and affordable must survive when the budget reaches zero. These rules are local
choices, not a claim that PoE2 has the same root or prerequisite rules.

Changing the former graph also changes the meaning and number of saved allocation
bits. Preserve the existing strict save fingerprint mechanism and reject
incompatible layouts; never reinterpret old node indices as new rewards. A future
migration needs its own deliberate mapping and verification.
[Save layout contract](../src/save.zig), [project instructions](../AGENTS.md).

## Simple graphics specification

### Composition and primitives

Give the graph the majority of the panel, with a persistent inspection area on the
right. Keep the page title and available points compact. The graph should read as
one connected landscape, not a collection of large buttons. All node centers,
edges, hit targets and focus motion must use the same layout transformation.
The shared character panel grows at half the window-fitting rate, capped at 1.25x;
the graph's own pan and zoom stay independent of this restrained outer scale.

Use a near-black flat canvas. Draw distant edges first in a low-contrast neutral
or restrained arm tint, then emphasize invested routes. Place filled circles over
edge endpoints so lines do not cut through symbols. A single border around the
canvas and a quiet divider before details are sufficient framing.

Use three modest sizes for stat, interest and capstone nodes. Bridges can use an
intermediate size and a paired rim or another small, consistent mark. The current
class origin needs an identifiable center or rim. Branch labels may orient the
overview, but should not overlap routes or become competing headings for every
layer. Do not display every reward sentence directly on the graph.

Stat symbols should be elementary and consistent. Interest symbols may identify
life, mana, armour or damage, using the project's existing basic visual language.
The capstone's size and rim supply hierarchy; there is no need for a unique painting.
Limit accent colors so arm identity does not overwhelm allocation status. Check
that fill, rim and size still distinguish important states without relying solely
on hue.

### Node and edge states

Focus is independent of ownership. The player must be able to inspect a remote
capstone, an already allocated stat, and an unaffordable next step without making
them look allocated.

| State | Visual treatment | Inspection meaning |
|---|---|---|
| Allocated | Solid or strongly lit center, definite warm rim | Already contributes its actual grant |
| Reachable and affordable | Dark center with clearly readable rim | One deliberate press allocates one point |
| Reachable, no points | Recognizable frontier with subdued availability emphasis | Connected, but needs a passive point |
| Unreached | Muted center and rim, still visible and inspectable | Requires a connecting allocation |
| Focused | Separate outer ring or small brackets | Current inspection target, regardless of other state |
| Current class origin | Stable origin mark | Starting allocation; explain any special reward handling |

An invested edge joins invested nodes and should read as part of the established
route. A frontier edge indicates a legal next connection in its permitted direction.
Other edges remain faint
enough for the invested route to dominate. Derive these treatments from actual
allocation and feeder rules; do not light a whole branch because its first node is
owned. Draw each visual connection once where possible, with small outward
arrowheads for branch prerequisites and a consistent two-way treatment for bridges.

Neither focus nor availability needs constant animation. Static marks are easier
to inspect in a dense graph and are sufficient for this design. If animation is
later introduced, it must not obscure status or alter game state.

### Inspection hierarchy

The 2026-10-20 presentation pass follows [DATA_PRESENTATION.md](DATA_PRESENTATION.md).
Grants read as complete modifier phrases, with their amount and units beside the
benefit. Armour grants explicitly say physical damage reduction; attribute grants
say what they add to. Keep the supported mechanics and allocation rules unchanged.

The details area should answer, in order: what is this, what does it grant, and what
can be done with it now? Show the node name first, then its role and branch when
useful, then every grant including any rider. Present status and the allocation
action together. The point counter should remain visible when a node is blocked.

Use exact descriptions generated from real grants. A stat node names the attribute
and amount. An interest node explains its supported benefit before its rider.
A capstone lists the complete package; its impressive name is not a substitute for
mechanics. A bridge's identity can explain the connection without pretending that
its topology is itself an additional numerical reward.

If current/after comparisons are shown, derive them through the same aggregation
and scaling used by gameplay. Flat attributes, percentage damage and armour must
not share misleading units. Do not claim that maximum-life gains restore current
health. Unknown or unsupported effects must be removed from the authored grant,
not described as though they work.

Keep action text short. Disabled actions need a specific reason such as no points,
an unconnected path, or already allocated. Use the direct allocation action
and cancellation behavior. Keep key and button names out of panel prose, following
the project's input presentation rules.

## Navigation, zoom and inspection

The PoE2 reference suggests a large spatial canvas that can retain an overview while
supporting close inspection. Its exact current keyboard, mouse and controller
gestures were not tested here. Do not claim to reproduce those bindings.

The sibling provides a concrete local navigation model: geometric directional
selection, a centered overview, bounded pan and zoom, and focus-aware framing.
Its tests check directional consistency and access to all selectable locations.
The local tree now follows its left-stick selection, right-stick pan and D-pad
zoom arrangement. Keyboard navigation also supports shifted pan, zoom and an
overview reset; exact bindings live in [CONTROLLER.md](CONTROLLER.md).
[Sibling navigation](../../zig-soulslike/src/play/passivetree.zig).

For this adaptation, prioritize complete visibility and useful node sizes at the
supported window dimensions. Keep controller navigation spatial and mouse hit
testing consistent with the drawn nodes. Inspection must reach every node, including
locked nodes; allocation legality must not filter navigation. A direction should
move toward a nearby candidate in that direction rather than jumping by array
index across the canvas.

The tree opens zoomed in at the class origin. Its initial magnification and limits
live in `ui/trees.zig`; the complete overview remains available through a reset and
minimum zoom. Pan and zoom affect presentation only, preserve selection, share the
hit-test transform and clip to the graph canvas. Directional selection recenters
the view so newly focused nodes remain visible; manual pan may inspect away from
the selection. Camera state belongs to unsaved navigation, not progression.
Control hints always use device glyphs, including keyboard keycaps, rather than
spelling controls in prose. Mouse wheel and on-screen zoom controls remain usable.

Search, if later justified, should highlight real matches, allow inspection of each,
and retain enough surrounding routes to orient the player. It must not allocate
nodes or infer a desired build. A planned route preview would similarly need a
distinct appearance from invested nodes and an explicit cost calculation; no such
planner is implied by the current visual redesign.

## Acceptance checks and ongoing use

Before handing off a change, inspect actual headless captures and verify the rules
appropriate to the edit. Keep generated images and temporary analysis outside the
repository, following [`AGENTS.md`](../AGENTS.md).

- The three arms, six branches, six capstones and two bridge depths are recognizable.
- Every visible connection corresponds to the authoritative graph; crossing a seam
  works from either side where the model promises it.
- Stat, interest, bridge and capstone roles are visually distinct without ornate art.
- Focus remains distinguishable on allocated, available and distant nodes.
- Zero points does not make a connected node appear geographically disconnected.
- Every class begins at its own correct origin, with no duplicate free reward;
  both alternate origins remain purchasable for one point.
- Branches require outward prerequisites; a bridge opens the far anchor without
  silently opening earlier unallocated layers.
- Every grant and rider shown in details contributes through the real runtime path.
- Capstone descriptions contain no unimplemented special effect or implied tradeoff.
- Controller directions and mouse targeting can inspect every node.
- The graph, details and action footer fit the smallest supported capture size.
- Branch names, longer node names and multiple grants do not overlap or truncate
  critical information.
- Allocation consumes the proper point pool once; cancel consumes nothing and
  browsing advances no turn.
- A changed graph is covered by the save compatibility fingerprint.
- Existing active skill prerequisites and ranks remain their own system, even when
  their page shares the new visual language.

For future work, first identify whether the request changes presentation, topology,
or gameplay. Read this document, then inspect the current local model and renderer.
Confirm which reference concepts are relevant before editing. Preserve an actual
rule-to-picture correspondence: adding a node category requires authored meaning;
adding a grant requires runtime integration; adding a bridge requires connectivity;
adding a control requires a working action.

Refresh external claims when they affect a decision, recording the research date
and a stable source or export revision. Keep historical observations labelled as
such. Update this document when the adaptation changes, especially its economy,
supported reward vocabulary, graph structure or navigation. Keep exact balance
values in code so this reference remains a guide to decisions rather than a stale
copy of the implementation.
