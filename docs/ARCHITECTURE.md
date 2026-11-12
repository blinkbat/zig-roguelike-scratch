# Runtime contracts

Ordinary feature changes should stay within an owning module and its integration
contract. The simulation is authoritative; the picture follows resolved facts at
their scheduled impact. Saved field classification lives in `src/save_data.zig`; portable parsing and
conversion live in `save_format.zig` and `save_values.zig`. See [save compatibility](SAVE_FORMAT.md).

| Contract | Owner | Tests |
| --- | --- | --- |
| Actor and barrel impacts differ; misses cannot destroy barrels | `gfx/effect_state.zig`, `gfx/impact_queue.zig` | [hero](../src/game/tests/hero.zig), [picture](../src/game/tests/picture.zig) |
| Chosen attacks and reactions have distinct attribution | `play/chronicle.zig` | [hero](../src/game/tests/hero.zig) |
| Attack rules cannot update graphics or input | `game/attacks.zig`, `game/sim.zig` | [hero](../src/game/tests/hero.zig), [skills](../src/game/tests/skills.zig), [terrain](../src/game/tests/terrain.zig) |
| Each resolution is pictured at its own impact | `game/presentation.zig`, `gfx/impact_queue.zig` | [impact_queue](../src/gfx/impact_queue.zig), [picture](../src/game/tests/picture.zig), [tactics_exec](../src/game/tactics_exec.zig) |
| Sprite selection, GPU resources and appearance have separate owners | `gfx/sprite_assets.zig`, `gfx/sprites.zig`, `gfx/sprite_materials.zig`, `gfx/look.zig` | [sprite_assets](../src/gfx/sprite_assets.zig), [sprites](../src/gfx/sprites.zig) |
| Turn stages preserve causality and clean up on death | `game/combat.zig`, `game/sim.zig` | [skills](../src/game/tests/skills.zig), [hero](../src/game/tests/hero.zig) |
| Targeting is valid only while active | `game.zig`, `game/skills.zig`, `game/targeting.zig` | [skills](../src/game/tests/skills.zig), [picture](../src/game/tests/picture.zig) |
| Transients reset at their declared lifetime | `game.zig`, `game/presentation.zig` | [world](../src/game/tests/world.zig), [loot](../src/game/tests/loot.zig), [save](../src/save.zig) |
| A skill declares a checked integration contract | `play/skill_contract.zig`, `play/skillbar.zig` | [skill_contract](../src/play/skill_contract.zig), [skills](../src/game/tests/skills.zig) |
| Death and loot rules cannot update the picture or menus | `game/rewards.zig` | [rewards](../src/game/rewards.zig), [loot](../src/game/tests/loot.zig) |
| A gesture owns one history transaction | `edit/history.zig` | [edit](../src/edit/tests.zig) |
| Editor input routing needs neither the game nor drawing resources | `edit/interaction.zig` | [edit](../src/edit/tests.zig) |
| Cosmetic visibility has one owner | `gfx/light_visibility.zig` | [light_tests](../src/gfx/light_tests.zig) |
| Editor drawing cannot mutate maps or game state through widgets | `edit/widgets.zig` | [edit](../src/edit/tests.zig), [widgets](../src/edit/widgets.zig) |
| Placement and cursor previews share geometry and legality | `edit/placement.zig`, `edit/canvas.zig` | [edit](../src/edit/tests.zig) |
| Derived editor data cannot mutate the authored map | `edit/preview.zig` | [preview](../src/edit/preview.zig) |
| Graph textures have one owner and explicit invalidation | `edit/thumbnails.zig` | [thumbnails](../src/edit/thumbnails.zig), [canvas](../src/edit/canvas.zig) |
| A map's script never names past its own tables | `map/script.zig`, `play/trigger.zig`, `game/talking.zig` | [script](../src/map/script.zig), [script_text](../src/map/script_text.zig), [trigger](../src/play/trigger.zig), [talking](../src/game/talking.zig), [edit](../src/edit/tests.zig) |
| A procgen node's painted section keeps its cells through the roll, is joined round its walls, and its box takes no feature's lot | `map/section.zig`, `map/procgen.zig`, `carve.connect` | [procgen](../src/map/procgen.zig), [section](../src/map/section.zig), [atlas](../src/map/atlas.zig), [atlas_text](../src/map/atlas_text.zig), [save](../src/save.zig) |
| Gameplay does not depend on UI or rendering modules | `tools/source_rules.zig` | [source_rules](../tools/source_rules.zig), [save](../src/save.zig) |

## Dependency boundaries

gfx/lens.zig owns screen-space lens blur, perspective, vignette and colour filters,
applied after the world (including its markers) and before the HUD and menus.
Blur leaves the middle sharp, softly blurs the bottom and more strongly blurs
the top. Perspective widens the foreground; game/mouse.zig uses the same
inverse mapping at the selected strength when picking cells. ui/options.zig shares
strength sliders under title Options > Visuals and Pause > Options > Visuals, including saturation,
warmth, sepia, film grain, scanlines and chromatic aberration. The lens filters
default to lens blur 10%, perspective 50%, vignette 85%, saturation 100%, warmth
10%, sepia 5%, grain 0%, scanlines 60% and chromatic aberration 30%.
Existing bloom, atmosphere and scenery focus default to 100% and also
have strength sliders; their Debug switches refer to the same enabled state.
Sliders support horizontal navigation in 5% steps, mouse dragging, per-value reset
and Reset to defaults / Set all to 0. Display (fullscreen, VSync, frame limit)
lives beside Visuals in Options. Vertical navigation and scrolling select rows. Settings last
for the application session and do not enter run saves; the HUD remains unfiltered.

Visited terrain outside current sight is darkened and strongly desaturated by
the cinema memory grade, blending back to full colour with visibility.
Visible loot bags and stocked open chests have a faint steady sprite glow and
a stronger shine sweep, fading with their pictured visibility.
Visibility transitions use short presentation-only fades. Bodies, projectiles,
NPCs, loose loot and ground hazards retain their last visible picture while fading
out; hidden movement and state never update that picture. Targeting and interaction
continue to use strict gameplay sight. Exploration feathering extends inward over
known tiles only, with overlapping edge fades rounding the inner corners; unseen
cells stay fully covered. Wall-adjacent feather widths interpolate continuously
to keep narrow corridors clear. Automatic chest/bag opening is
suppressed while a foe is visible; deliberate interaction still works.

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

Sprite asset selection and shader definitions cannot import the sprite renderer.
Effect payloads and the impact queue cannot import the particle-effects coordinator.
These helpers also cannot import Game, Presentation or the application.

## Lifetimes

`game/sim.zig` (Simulation)
- Owns run data, the seeded RNG and consumed turn ticks.
- Free actions and idle frames do not age it.
- Saved integer actor references stay stable; typed adapters change neither the legacy fingerprint nor portable save identities.
- Pool replacement keeps the initialized `var` copy of a carried actor (Zig 0.14.1).
- `resetTransientTurn` owns its scene reset.

`game/presentation.zig` (Presentation)
- Snapshot a resolution immediately, before a later blow changes that body.
- A missed reaction still owns animation time.
- New runs discard pending presentation; travel keeps only explicitly carried state; resume settles the loaded picture without replaying effects.
- Mutation APIs take `ActorId` for identity or `ActorSlot` for storage; callers convert integer identities at their boundary.
- `freshTurn` owns its scene reset.
- `stepGlide` owns a local `TurnTiming`, including the hero's pictured cell after each knockback.
- Each body's schedule runs motion/projectile timing, blows and mending, reactions, knockback, then status harm.
- `BodyTiming.impact_in` and `finishes_in` are seconds from the current frame; `starts_at` and `TurnTiming.next_at` keep the turn origin; `late` converts.
- New effects record their resolved snapshot once and join a stage; gameplay never writes the queue's landed state or timers.

`gfx/fx.zig`, `gfx/impact_queue.zig`
- `Fx.step` ages existing visuals before delivering ready events.
- The queue keeps swap-removal delivery order and picks body snapshots by simulation sequence, even when several deadlines pass in one frame.
- Every event releases its mana debt once, a superseded snapshot included.
- `Fx` renders delivered events and owns cosmetic RNG; the queue does not.

`game/attacks.zig`
- `resolve` returns null for an absent target, otherwise `.miss` or `.hit` carrying damage, statuses, culling and recovery.
- Combat consumes the outcome once: damage consequences, log, snapshot/split, death rewards, then impact and recovery.
- Hero rolls and weapon status resolution stay here; animation, input and death transitions stay in their adapters.

`game/rewards.zig`
- `defeat` resolves XP, drops, flask refills, gas, steam and witness fright from Simulation alone; Presentation holds dropped gold and schedules speech from its `Death`.
- Already frightened witnesses refresh their timer without another speech.
- Chest capacity failure leaves the chest and RNG untouched; the game adapter supplies the message.

`game.zig`, `game/targeting.zig`
- `Game.mode.aim` owns an `Aim`: opening creates all its fields together, `skills.closeAim` discards them, switching mode drops it.
- Barrier targeting distinguishes choosing its start from its end.
- Confirmation copies the target before closing and passes that value to execution.
- `TravelCarry` keeps queued commands (Interact included), the mouse skill set, facing and the level-up effect across node replacement.

`game/combat.zig`
- Turn order: recovery/cooldowns, hero post-action harm, gas spread, foe clocks, firebolts in flight, each foe's action then its harm, waiting newborn harm, final ward/sight.
- A braced foe (`Actor.braced`) acts down its locked line on its next action; any skipped action drops the brace. A firebolt (`Actor.bolt`) flies on after its thrower dies and freezes with its level when the hero leaves; `Presentation.bolts` is rebuilt from it.
- Consumed ticks and displacement clear even when hero death interrupts the turn.
- Split children inherit consumed ticks, so they cannot repeat their parent's harm that turn.

## Adding a skill

Follow the runtime path in `game/skills.zig`: `useSkill` checks presentation timing,
then calls `useUnaimed` or `openTargeting`. Targeted actions resolve through
`confirmAim`. Projectile execution goes through `loose`, `resolveProjectileHit`
and `hitProjectileActor`; rush execution goes through `rushTo`. Each helper names
one decision. Compile-time specialization stays at the calls that need a skill's
module type; ordinary capability queries read the checked contract table.

Start with [pinning](../src/play/pinning.zig) for a simple projectile,
[nova](../src/play/nova.zig) for an area skill, or `Overwatch` in
[tactics](../src/play/tactics.zig) plus its [execution](../src/game/tactics_exec.zig)
for a reaction. Add the action and registry definition in
[skillbar](../src/play/skillbar.zig), declaring attack delivery explicitly.
[skill_contract](../src/play/skill_contract.zig) interprets the module once and
validates its targeting, damage, status and special execution requirements. Registry
errors identify the skill; the `invalid` diagnostic path is also tested with incomplete
sample modules. Specialized tactical execution stays explicit in `game/tactics_exec.zig`.

Wire the class kit and defaults in skillbar, ranks/costs in
[progress](../src/play/progress.zig), the icon in
[line_icons](../src/gfx/line_icons.zig), and a behavior test in
[skills tests](../src/game/tests/skills.zig) or `game/tactics_exec.zig`. Preview and
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
| Contextual bindings and Desk shortcuts | `core/input_bindings.zig`: tables and checked captions, with no device polling |
| Input glyph naming | `core/input_names.zig`: device labels and marked captions |
| Light sampling and baking | `gfx/light.zig`: source state and bake orchestration; `light_model.zig` owns shading math and source types |
| Light drawing and resources | `gfx/light_gpu.zig`: shader/texture lifetime, uploads and draw operations |
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

Dialogue layout and pagination live in `ui/talk.zig`; `game/talking.zig` owns the
unsaved reading position and separates Continue from actual script choices.
The editor previews the same layout. Long-form writing limits, independent editor
scrolling and the source text concern tree are documented in [TEXT_EDITOR.md](TEXT_EDITOR.md).
`core/wire.zig` traverses aggregate save values by reference, so large authored
dialogue buffers do not create recursive stack copies during encoding.

Run `check.cmd` and affected test filters for each migration, then the full suite
after combat, scheduling or lifecycle changes. Preserve seeded outcomes and the
legacy reader fingerprint and portable save identities. Tests use in-memory saves and maps. Run actual headless
captures for presentation/editor changes, inspect PNGs, benchmark, and finish with
`build.cmd`. All generated captures, timing logs and temporary scripts live in `%TEMP%`.
The full test command also runs the source-boundary checker's own tests. The
Windows CI workflow runs the same check/test/build scripts and packaging tests;
[README.md](../README.md) describes setup on a fresh machine.
