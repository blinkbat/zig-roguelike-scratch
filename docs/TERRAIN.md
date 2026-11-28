# Terrain and character inspection

## Combat modifiers

`Simulation.combatStats` combines actor stats, innate resistance and temporary buildup with the occupied tile and local outdoor rain. All occupants use this rule, including flying bodies. Compute modifiers at use so movement, displacement and travel take effect immediately. The terrain table supplies neutral defaults and inspection text. Add new terrain effects there. [Modifier table](../src/play/terrain.zig) · [Simulation resolver](../src/game/sim.zig)

Hit chance and dodge roll separately. A missed direct attack applies no damage, status or buildup. Environmental impacts still resolve, including water conducting lightning to grounded occupants. Elemental resistance modifies damage, including burn ticks. Positive status resistance can prevent an application, and negative resistance increases its proc chance up to 100%. Both resistance types clamp to −100% through +100%. Only a successful application builds resistance. Moving off a tile leaves an existing status and its duration intact. [Attack resolution](../src/game/attacks.zig) · [Status rules](../src/play/resilience.zig)

## Visibility and targeting

Burning reeds and crops lose cover while alight. Dousing surviving foliage restores it. Sight, light and projectiles share terrain opacity. Smoke affects only rendering. Arcane Barrier blocks movement and projectiles while preserving sight. [Grid](../src/map/grid.zig) · [Lighting](../src/map/lume.zig) · [Wall placement](../src/play/tactics.zig)

Projectile suggestions require a visible enemy on the preview flight. Free aim allows an in-range empty, dark or wall cell in line of sight. Previews hide unseen interceptors and their burst areas. Resolution stops a nonpiercing projectile at its first collision, including a missed attack. Combustion and Shatter strike an afflicted visible foe in deep water once even when its cell falls outside the walkable splash. [Projectile geometry](../src/play/bow.zig) · [Skill resolution](../src/game/tactics_exec.zig)

## Character inspection

Inspection targets visible, pictured characters and costs no turn. The card shows the hero's name or foe title, pictured HP, and the tile beneath the pictured body. List signed terrain effects, or “No Effects.” Express status modifiers as application chances. Outdoors, show the local rain category and its stepped fire and burn resistance when they contribute. Long cards scroll by page controls or wheel. [Card implementation](../src/game/overlay.zig) · [Controls](CONTROLLER.md)
