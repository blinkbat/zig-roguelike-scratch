# Active skill panel

The panel follows Diablo II's compact prerequisite-tree layout, using simple
graphics and Cistern's own rules. Allocation belongs to
[`play/progress.zig`](../src/play/progress.zig), bindings to
[`play/skillbar.zig`](../src/play/skillbar.zig), drawing to
[`ui/trees.zig`](../src/ui/trees.zig), and navigation to
[`ui/book.zig`](../src/ui/book.zig). Keep balance and authored paths in source.

## Model and layout

- `progress.skills(class)` owns each action, parent, initial flag and logical
  `at` position. Preserve that geometry; learning or focusing a node never moves
  the others. Independent roots remain independent.
- `State.canLearn` and `State.learn` own eligibility and spending. Each class
  has one tree; active and passive points are separate. Initial skills start
  learned. Shoot is a fixed basic attack, not an upgradeable rank.
- Draw compact square skill symbols, parent-to-child arrows and attached
  `rank / RANKS` badges. Connections indicate prerequisites only. Do not add
  category tabs, synergies, level gates or reset controls without gameplay support.
- Center the authored graph on the left, with persistent inspection on the right
  and the active-point balance visible once. Draw paths behind sockets and labels.
  Use the existing icons, typography and muted-gold palette.
- All nodes remain inspectable, including locked and maximum-rank skills.
  Ownership, eligibility and focus are separate visual states.

| State | Inspection/action |
| --- | --- |
| Parent missing | Name the required skill; no allocation |
| Parent met, no points | State that no active points remain |
| Unlearned and eligible | Learn, with a first-rank preview |
| Learned below maximum | Actual rank; Upgrade only when `canLearn` succeeds |
| Maximum | Complete rank badge; no empty upgrade section or redundant reason |
| Basic attack | Basic label; no upgrade action or redundant reason |
| Focused | Independent outline and this node's details |

## Inspection and interaction

Follow [DATA_PRESENTATION.md](DATA_PRESENTATION.md): effect first, current or
first-rank properties together, then only the next rank's changes. Omit irrelevant
zeroes and repeated core rules. Keep descriptions and wrapped properties above
the action footer.

Use `Act.describe` with combined equipment and passive perks. Obtain mana and
cooldown through `State.writeUsage`; use `State.preparedBlow` and
`State.preparedHit` with the hero's current preparation for actual hit ranges.
Those ranges include equipment, attributes and rank, before critical hits and
defenses. When average damage improves but rounded endpoints do not, show the
old/new rank damage bonus. Utility skills have no fictitious damage line.

Directional navigation follows visible geometry and includes locked nodes.
Clicking a skill selects it; pointer movement preserves selection while approaching
an action. One deliberate Learn/Upgrade action spends one active point and keeps
focus. Browsing, backing out, learning and binding spend no simulation turn.

Bind skill passes the selected learned skill directly to the slot picker and
returns to Skills. It remains available without spare active points. Utilities
remain available through the binding picker. Page navigation and glyphs follow
[CONTROLLER.md](CONTROLLER.md); panel scaling follows
[DATA_PRESENTATION.md](DATA_PRESENTATION.md).

## Verification

Inspect all three classes with `--shot-trees` and relevant `--shot-ui` captures,
using [AGENTS.md](../AGENTS.md#verification). Check prerequisite edges, rank
badges, blocked/no-point/maximum states, truthful damage and upgrade previews,
and fitting text at the smallest supported size. Directional and pointer targets
must match drawing. One deliberate allocation spends once; navigation and cancel
change neither progression nor simulation time.
