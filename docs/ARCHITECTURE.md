# Runtime contracts

Ordinary feature changes should stay within an owning module and its integration
contract. The simulation is authoritative; the picture follows resolved facts at
their scheduled impact. Saved field classification remains solely in `src/save.zig`.

| Contract | Owner and enforcement | Representative verification |
| --- | --- | --- |
| Actor and barrel impacts differ; misses cannot destroy barrels | `gfx/fx.zig`: tagged impacts, distinct actor IDs and slots from `play/actor.zig` | [Hero tests](../src/game/tests/hero.zig): missed reaction timing and phantom barrels; [picture tests](../src/game/tests/picture.zig): barrel removal |
| Chosen attacks and reactions have distinct attribution | `play/chronicle.zig`: attack origin carried through combat and obituary handling | [Hero tests](../src/game/tests/hero.zig): missed reactions retain the chosen deed; [epitaph tests](../src/game/epitaph.zig) |
| Attack rules cannot update graphics or input | `game/attacks.zig`: rolls and hit/status resolution accept only Simulation and return a typed outcome; `game/sim.zig` owns HP loss; Game applies input consequences, Presentation defers resources | [Hero tests](../src/game/tests/hero.zig): isolated damage/attack resolution and seeded attack/reaction/status outcomes from revision `c989855`; [skill tests](../src/game/tests/skills.zig): staggered shielding; [terrain tests](../src/game/tests/terrain.zig): resistances |
| Each resolution is pictured at its own impact | `game/presentation.zig`: semantic recording operations own snapshots, debts and recovery; bounded FX capacity | [Picture tests](../src/game/tests/picture.zig): multiple blows and split births; [tactics tests](../src/game/tactics.zig): reaction recovery |
| Turn stages preserve causality and clean up on death | `game/combat.zig`: named stages; Simulation owns consumed ticks inherited by split children | [Skill tests](../src/game/tests/skills.zig): inherited ticks, skipped actions, movement bleed and free actions; [hero tests](../src/game/tests/hero.zig): death prevents later stages and clears transients |
| Targeting is valid only while active | `game.zig`, `game/skills.zig`: cohesive mode payload and begin/end operations | [Skill tests](../src/game/tests/skills.zig): opening input, cancellation, two-point barrier; [picture tests](../src/game/tests/picture.zig): queued actions |
| Transients reset at their declared lifetime | Game coordinates new run, travel and resume; Presentation owns picture resets | [World tests](../src/game/tests/world.zig): travel; [loot tests](../src/game/tests/loot.zig): carried interactions; [save tests](../src/save.zig): in-memory round trips and fingerprint |
| A skill declares a checked integration contract | `play/skill_contract.zig`: one compile-time capability interpretation shared by dispatch and metadata through `skillbar` | [Contract diagnostics](../src/play/skill_contract.zig); [skill tests](../src/game/tests/skills.zig): legality, previews and scaling |
| Death and loot rules cannot update the picture or menus | `game/rewards.zig`: accepts Simulation; death returns dropped gold and newly frightened witnesses, coin collection returns the removed pile, and chest opening distinguishes capacity failure | [Reward tests](../src/game/rewards.zig): seeded loot, unchanged combat RNG/picture and fright refresh; [loot tests](../src/game/tests/loot.zig): reserved ground capacity and delayed drops |
| A gesture owns one history transaction | `edit/history.zig`: transaction snapshot, change, commit and cancel; Editor owns cache invalidation; text editing retains its separate persistence | [Editor tests](../src/edit/tests.zig): gesture, cancelled graph drag, no-op, undo and redo preservation |
| Editor input routing does not need the game or drawing resources | `edit/interaction.zig`: routes Desk snapshots through modal, command, viewport and panel stages using explicit canvas bounds and screen height | [Editor tests](../src/edit/tests.zig): modal/view changes consume their canvas clicks; strokes, graph drags and cancellation retain history semantics |
| Cosmetic visibility has one owner | `gfx/light_visibility.zig`: owns eased sight, memory, ground weights, blur scratch and cached fade sampling; Light reads it for terrain, bodies and effects | [Lighting tests](../src/gfx/light_tests.zig): memory edges, ground continuity, wall occlusion and sampled/baked agreement |
| Editor drawing cannot mutate maps or game state through widgets | `edit/widgets.zig`: font/screen inputs and `Controls`; Editor supplies input gating and the tooltip destination | [Editor tests](../src/edit/tests.zig): clipping, modal/popup layers, opening-frame and pending-action click suppression; [widget tests](../src/edit/widgets.zig): scrollbar bounds |
| Placement and cursor previews share geometry and legality | `edit/placement.zig`: brushes, placement, clipboard and paste preview; `edit/canvas.zig` owns cursor drawing | [Editor tests](../src/edit/tests.zig): shapes, paste clipping, blocked objects, cache invalidation and history |
| Derived editor data cannot mutate the authored map | `edit/preview.zig`: Scene owns generated terrain, preview foes, arrival, reachability and issue caches; accepts only a const Atlas | [Preview tests](../src/edit/preview.zig): node selection, reuse, reroll, reset and map immutability |
| Graph textures have one owner and explicit invalidation | `edit/thumbnails.zig`: owns generation scratch, texture lifetime and validity; canvas requests only visible images | [Thumbnail tests](../src/edit/thumbnails.zig): selective invalidation and changed node identities; [canvas tests](../src/edit/canvas.zig): offscreen clipping |
| Gameplay does not depend on UI or rendering modules | `tools/source_rules.zig`, called by every build step; wording and bounded text live in core, event history in `play/log.zig` | Boundary-checker tests reject forbidden imports and allow integration-test imports; [save tests](../src/save.zig) retain the recorded fingerprint |

## Dependency boundaries

Runtime imports in `play/`, `map/`, `game/sim.zig`, `game/attacks.zig`,
`game/rewards.zig` and `edit/preview.zig` are limited to core, play and map modules. The game rule
modules may also depend on each other. They cannot import raylib, UI, rendering,
editor coordination or the application. Use `core/wording.zig` for display names,
`core/text.zig` for bounded text and `play/log.zig` for event history;
`ui/journal.zig` only renders that history.

Editor widgets, thumbnails, tool metadata and naming fields cannot import Editor,
Game or the application. Character view, layout, card and stats modules cannot
import Book navigation, Editor, Game or the application.
Editor interaction may import Editor, but cannot import Game or the application.
The build checks actual Zig import tokens and normalizes relative paths. Test
bodies may import other layers to verify integration contracts. These are direct
source dependency checks; `core/input.zig` still owns device access and its shared
input types.

## Lifetimes

Simulation owns run data, including the seeded RNG and consumed turn ticks.
The saved integer actor references remain stable; typed transient adapters do not
change the recorded save fingerprint. Pool replacement must retain the initialized
`var` copy of a carried actor required by Zig 0.14.1.

Presentation snapshots must be captured immediately after a resolution, before a
later blow changes that body. A missed reaction still owns animation time. New runs
discard pending presentation; travel preserves only explicitly carried state; resume
settles the loaded picture without replaying effects. Free actions and idle frames
do not age simulation state.

`attacks.resolve` returns null for an absent target, otherwise a miss or a hit carrying
damage, applied statuses, culling and recovery. Combat consumes that outcome once:
apply Game's damage consequences, record the log, snapshot/split, handle death rewards,
then schedule the impact and recovery. Hero damage rolls and weapon status resolution stay in attacks;
animation, input and death transitions stay in their owning adapters.

`rewards.defeat` resolves XP, drops, flask refills, gas and witness fright using
Simulation alone. Presentation consumes its `Death` result to hold dropped gold
and schedule speech against the fallen actor's impact. Already frightened witnesses
refresh their simulation timer without scheduling another speech. Chest capacity
failure leaves the chest and RNG untouched; the game adapter supplies the menu message.

`Game.mode.aim` owns an `Aim` from `game/targeting.zig`. Opening creates all of its
fields together; `skills.closeAim` discards them. Barrier targeting distinguishes
choosing its start from choosing its end. Confirmation copies the target before
closing it and passes that value to execution. Switching to another mode also drops
the payload. `TravelCarry` explicitly preserves queued commands (including Interact),
the mouse skill set, facing and the ongoing level-up effect across node replacement.
`Simulation.resetTransientTurn` and `Presentation.freshTurn` own their scene resets.

Turn order is recovery/cooldowns, hero post-action harm, gas spread, foe clocks,
ordered foe action then its harm, waiting newborn harm, and final ward/sight handling.
Consumed ticks and displacement are cleared even when hero death interrupts this
sequence. Split children inherit consumed ticks so they cannot repeat their parent's
harm in the same turn.

## Adding a skill

Follow the runtime path in `game/skills.zig`: `useSkill` checks presentation timing,
then calls `useUnaimed` or `openTargeting`. Targeted actions resolve through
`confirmAim`. Projectile execution goes through `loose`, `resolveProjectileHit`
and `hitProjectileActor`; rush execution goes through `rushTo`. Each helper names
one decision. Compile-time specialization stays at the calls that need a skill's
module type; ordinary capability queries read the checked contract table.

Start with [pinning](../src/play/pinning.zig) for a simple projectile,
[nova](../src/play/nova.zig) for an area skill, or `Overwatch` in
[tactics](../src/play/tactics.zig) plus its [execution](../src/game/tactics.zig)
for a reaction. Add the action and registry definition in
[skillbar](../src/play/skillbar.zig), declaring attack delivery explicitly.
[skill_contract](../src/play/skill_contract.zig) interprets the module once and
validates its targeting, damage, status and special execution requirements. Registry
errors identify the skill; the `invalid` diagnostic path is also tested with incomplete
sample modules. Specialized tactical execution stays explicit in `game/tactics.zig`.

Wire the class kit and defaults in skillbar, ranks/costs in
[progress](../src/play/progress.zig), the icon in
[line_icons](../src/gfx/line_icons.zig), and a behavior test in
[skills tests](../src/game/tests/skills.zig) or `game/tactics.zig`. Preview and
execution both use `Act` accessors backed by the same contract. Keep area geometry
in the skill module and capture targets before damage so splits are not hit twice.

## Adding an editor tool

Begin a gesture with `Editor.gesture`. Report actual map changes through `changed`
(terrain and thumbnail invalidation), `relinked` (door issues), or `bank` for metadata.
Brushes, placement, clipboard and paste previews live in `edit/placement.zig`.
Shared drawing and layout live in `edit/widgets.zig`; pass `ed.controls()` and
the font directly. Construct controls at each call so a newly opened modal takes
effect immediately. Widgets have no access to Editor or Game.
`edit/interaction.zig` handles keyboard commands and canvas gestures before drawing.
It takes canvas bounds and screen height directly, preserving modal, rename and
view-change priority before a click can paint or begin a graph drag.
`Editor.scene` owns the derived level, preview actors and issues. Call `preview`
before reading it; selection, edits and rerolls invalidate it through its owner.
Scene generation takes a const map and cannot modify history or navigation.
`Editor.thumbnails` owns graph texture lifetime and selective invalidation. Canvas
passes the map, derived scene and clipping rectangles without changing the map.
`Game.art` tracks stale, play and editor graphics as one state. Scene changes and
title assets invalidate it; the matching renderer prepares its required textures
once. Editor does not keep a second graphics-stale flag.

History records the starting map on the first actual change and keeps later changes
in that same step. A no-op gesture does not truncate redo. Graph movement uses
`Transaction.previewNode`, then `commitPreview` or `cancelPreview`: cancellation
restores the starting map without modifying the history ring or saved position.
Undo/redo swaps invalidate only affected thumbnails, or all thumbnails when node
identity changes. Source wording and attribution remain separate transactions in
`text_catalog.zig` and `text_panel.zig`; map undo never rewrites source files.

## Finding input, editor and character UI behavior

| Change | Owner |
| --- | --- |
| Device polling and input context | `core/input.zig`: `State.update` orders pointer, button, text, tree and movement reads; all device reads remain here |
| Movement repeat and stick hysteresis | `core/input_repeat.zig`: `Stepper`, `RadialStepper` and their pure repeat tests |
| Editor tools, shapes, descriptions and help | `edit/tool_catalog.zig`; it does not access Editor or Game |
| Editor naming and paste validation | `edit/name_field.zig`: bounded naming fields fed by Desk snapshots |
| Character navigation and commands | `ui/book.zig`: `Book.step`, selection and panel drawing |
| Character read-only inputs and command types | `ui/character_view.zig`: `View`, `Nearby`, `Page` and `Command` |
| Shared character geometry | `ui/character_layout.zig`: panel, tab, list and equipment bounds shared by drawing and hit testing |
| Item-card rows and typography | `ui/item_card.zig`: card drawing, height and typography verification |
| Main and advanced character statistics | `ui/character_stats.zig`: columns, status chances and typography verification |

The existing `input.Stepper`, `editor.Tool`, `book.View` and related exports remain
entry points for callers. The extracted character renderers read a `View` without
access to Book navigation, Game or editor state. Tests stay with their owning
logic; integration tests continue to exercise the public entry points.

## Verification

Run `check.cmd` and affected test filters for each migration, then the full suite
after combat, scheduling or lifecycle changes. Preserve seeded outcomes and the
recorded save fingerprint. Tests use in-memory saves and maps. Run actual headless
captures for presentation/editor changes, inspect PNGs, benchmark, and finish with
`build.cmd`. All generated captures, timing logs and temporary scripts live in `%TEMP%`.
The full test command also runs the source-boundary checker's own tests. The
Windows CI workflow runs the same check/test/build scripts and packaging tests;
[README.md](../README.md) describes setup on a fresh machine.
