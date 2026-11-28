# Passive tree

The radial graph has three class origins, two branches per arm and bridges between neighboring arms. Keep topology, values, grants and roles in the source table. `feeders` defines both the drawn edges and the prerequisites. Branches unlock outward. A bridge accepts either anchor and opens the opposite anchor for onward progression. [Graph and feeders](../src/play/passives.zig)

The chosen origin starts owned with its attributes already included in the class base. Other origins cost one passive point and need no feeder. Each additional node costs one point and requires an owned feeder. Apply every grant on a node, including its rider. Allocation takes no game turn, and maximum-life gains preserve current HP. Portable saves identify nodes by `(arm, branch, seam, ring, slot)`. Preserve those identities or migrate them and refund removed nodes. [Allocation](../src/play/progress.zig) · [Save format](SAVE_FORMAT.md)

## Inspection and navigation

Draw each edge once behind the nodes. Emphasize allocated routes, distinguish reachable edges even at zero points, and keep distant nodes inspectable. Show origins with class initials, bridges with a consistent mark and capstones with double rings. Focus has a separate outline. The sidebar shows the selected node's grants, any exception and its action or blocker. The free origin reads “Starting point.” [Panel rendering](../src/ui/trees.zig) · [Data presentation](DATA_PRESENTATION.md)

The panel opens zoomed at the class origin. Drawing, hit testing and directional navigation share the graph geometry. Directional selection recenters the view. Middle-drag or controller pan moves the view while retaining selection. Wheel and panel controls change zoom. Overview restores minimum zoom and recenters. Pan and zoom belong to the view and are unsaved. Clicking a node selects it. Allocation needs a separate deliberate action. [Book input](../src/ui/book.zig) · [Controls](CONTROLLER.md)

When changing topology, verify outward prerequisites, bridge access from both anchors, one-point allocation and portable save identities. Inspect `--shot-ui` captures for focus, both bridge depths, zero-point frontiers, multi-grant text and small-window clipping. [Capture instructions](../AGENTS.md#verification)
