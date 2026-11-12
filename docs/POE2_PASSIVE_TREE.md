# Passive tree

The passive panel uses a sparse radial graph: simple circles, quiet connections
and a persistent inspection sidebar. Path of Exile 2 informed the visual hierarchy;
the owner's Soulslike tree supplied the three-arm structure. Cistern's source
owns all topology, grants and allocation rules.

| Responsibility | Owner |
| --- | --- |
| Graph, stable identities, feeders, grants and roles | [`play/passives.zig`](../src/play/passives.zig) |
| Point budget and allocation | [`play/progress.zig`](../src/play/progress.zig) |
| Derived attributes | [`play/attrs.zig`](../src/play/attrs.zig) |
| Layout, drawing and view transform | [`ui/trees.zig`](../src/ui/trees.zig) |
| Navigation and commands | [`ui/book.zig`](../src/ui/book.zig) |
| Persistence and migration | [SAVE_FORMAT.md](SAVE_FORMAT.md) |

## Graph and allocation

The graph has three class origins, two branches per class and six bridges.
Each branch has six rings with widths 1, 2, 3, 3, 2, 1: 81 nodes overall,
including six terminal capstones. Knight branches are Fortitude/Might;
Archer branches Agility/Finesse; Wizard branches Reserves/Sorcery.
Bridges join neighboring arms at rings three and five. There is no central hub.

`feeders` supplies both drawn links and allocation prerequisites. Branches
advance outward; owning a later node does not unlock earlier layers. A bridge
can be entered from either anchor and feeds the far anchor, allowing outward
progression there. Geometric proximity alone never creates a connection.

The chosen class origin starts owned and adds no reward beyond the class's base
attributes. Other origins are immediately purchasable. Each purchase costs one
passive point; non-origin nodes also require an allocated feeder.
`State.available`, `State.canAllocate`, `State.allocate` and `bonusAt` are authoritative.
XP supplies separate active and passive point pools. Allocation takes no turn,
and maximum-life gains do not heal current life.

Stat, interest and capstone are semantic roles. Interest nodes and bridges may
have an additional grant; both grants must appear in inspection and apply through
runtime aggregation. Capstones describe their actual package without implying
unsupported rule changes. Values and stacking belong in source.

Portable saves identify nodes by `(arm, branch, seam, ring, slot)`, not array
position. Preserve those meanings; changed meanings require migration. Removed
identities refund points. Unknown legacy raw layouts remain incompatible.

## Drawing and inspection

Give the graph most of the panel, with details on the right and the point balance
shown once. All centers, edges, hit targets and focus movement share one transform.
Keep the near-black canvas sparse: no central spokes, node text plates, category
legends, branch labels or arrowheads.

Use modest size differences for stat, interest and capstone nodes, double rings
for capstones, a consistent bridge mark and class initials at origins.
Draw each connection once behind nodes. Allocated routes dominate; frontier
connections reflect actual feeder direction, and remote paths stay faint.

| State | Treatment |
| --- | --- |
| Allocated | Solid muted arm color and warm rim |
| Reachable and affordable | Dark fill, clear rim and allocation action |
| Reachable without points | Still visibly connected; explain missing point |
| Unreached | Muted but inspectable; explain missing connection |
| Focused | Separate ring regardless of ownership or eligibility |
| Free class origin | Class name and “Starting point” |

The sidebar shows a small name, every grant and rider, any essential exception,
and one allocation action or blocker. Use complete modifier phrases and explicit
units; omit repeated core rules and redundant role/status headings. Follow
[DATA_PRESENTATION.md](DATA_PRESENTATION.md). Derive any current/after comparison
through gameplay aggregation.

## Navigation and verification

The tree opens zoomed at the class origin. Initial zoom and bounds live in
`ui/trees.zig`. Directional navigation follows geometry and can reach every node,
regardless of eligibility; it recenters newly focused nodes. Manual pan may move
away from selection. Pan/zoom preserve selection, clip to the canvas and remain
unsaved navigation state. Overview resets pan and zoom.

Clicking a node selects it; pointer motion preserves selection. The visible
allocation action spends one point. Middle-drag starts inside the canvas and
ends on release; wheel and on-screen controls zoom. Exact controller/keyboard
bindings live in [CONTROLLER.md](CONTROLLER.md).

Use `--shot-ui` and [AGENTS.md](../AGENTS.md#verification) for visual changes.
Check all origins, branch silhouettes, both bridge depths, focus in every state,
zero-point frontier visibility, multi-grant text and small-window clipping.
Verify outward prerequisites, two-way bridge access, one-point transactions and
save identity preservation when changing the graph. Browsing and cancellation
must not allocate or advance a turn.
