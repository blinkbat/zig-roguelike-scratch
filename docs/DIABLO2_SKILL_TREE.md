# Active skill panel

Each class has a compact prerequisite tree. `progress.skills(class)` owns each skill's position, prerequisite and initial rank. Preserve authored roots and positions when focus or ownership changes. Learning spends an active point through `State.learn`. Shoot is a fixed basic attack. [Skill definitions and allocation](../src/play/progress.zig)

| Selected skill | Sidebar and action |
| --- | --- |
| Unlearned | Show its first-rank effects, then Learn or the missing prerequisite or point. |
| Learned | Show actual rank and properties, followed by the changes at the next rank. Enable Upgrade when eligible. |
| Maximum or basic | Show its rank or Basic label and omit the upgrade preview. Binding remains available. |

Draw prerequisite arrows behind square skill icons, keep the point balance visible once, and give focus its own outline. Keep all nodes inspectable. For damage previews, use the hero's equipment, attributes, rank and active preparation before critical hits and defenses. If rounded endpoints hide an improvement, show the change in rank damage bonus. Use `State.writeUsage` for mana and cooldown. [Panel rendering](../src/ui/trees.zig) · [Data presentation](DATA_PRESENTATION.md)

Directional navigation follows the diagram. Clicking selects a node and preserves selection as the pointer approaches its action. One Learn or Upgrade spends one point and retains focus. Bind skill carries the learned skill to slot selection and returns to Skills. Browsing, allocation and binding take no game turn. [Book input](../src/ui/book.zig) · [Binding rules](../src/play/skillbar.zig) · [Controls](CONTROLLER.md)

Use the three class-tree captures in `--shot-ui` to check arrows, badges, locked and maximum-rank states and the smallest supported layout. Test directional and pointer selection against the drawn nodes and confirm a single allocation spends once. [Capture instructions](../AGENTS.md#verification)
