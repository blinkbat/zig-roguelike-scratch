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
| Enemy ordering, targeting and support rules cannot schedule presentation | `game/foe_rules.zig` | [foe_rules](../src/game/foe_rules.zig), [foes](../src/game/tests/foes.zig) |
| Projectile motion keeps impact times and never tracks hidden positions in its fading picture | `game/projectile_motion.zig` | [projectile_motion](../src/game/projectile_motion.zig), [picture](../src/game/tests/picture.zig) |
| Status marks draw from time and explicit drawing inputs without access to the effects queue | `gfx/status_marks.zig` | [source_rules](../tools/source_rules.zig), headless effect captures |
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
| Plot field lookup and name validation depend only on script data | `edit/plot_fields.zig` | [plot_fields](../src/edit/plot_fields.zig), [plot](../src/edit/plot.zig) |
| A procgen node's painted section keeps its cells through the roll, is joined round its walls, and its box takes no feature's lot | `map/section.zig`, `map/procgen.zig`, `carve.connect` | [procgen](../src/map/procgen.zig), [section](../src/map/section.zig), [atlas](../src/map/atlas.zig), [atlas_text](../src/map/atlas_text.zig), [save](../src/save.zig) |
| Gameplay does not depend on UI or rendering modules | `tools/source_rules.zig` | [source_rules](../tools/source_rules.zig), [save](../src/save.zig) |

## Dependency boundaries

`gfx/lens.zig` owns screen-space filters after the world and before HUD/menus.
`game/mouse.zig` uses its inverse perspective mapping for cell picking.
Actor inspection uses that inverse mapping for picking and projected bounds for
focus, navigation and tooltip placement; HUD targets stay in screen coordinates.
`ui/options.zig` owns Visuals controls; Display settings live beside them.
Settings last for the application session and do not enter run saves.

Visited terrain outside current sight is darkened and strongly desaturated by
the cinema memory grade, blending back to full colour with visibility.
Water highlights, bloom and atmosphere use the same smooth visibility field across
known terrain, including the fade into memory; gameplay sight still gates dynamic
emissive sources. Unexplored terrain does not populate the atmospheric field.
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

Body lighting, including rim sheen, is capped at the authored sprite colour so
nearby torches cannot bleach its highlights. Emission and hit flashes remain separate.
Shadow casters sample light independently of fog; receiver visibility fades the
landed mask. Culling includes silhouettes and blur beyond the camera, and actor
birth/death timing follows presentation. Bind the receiver shader's light-map
sampler after changing blend mode: raylib flushes auxiliary texture bindings on
a blend change. Water reflections separate live bodies/effects from remembered
scenery, preserve source visibility and compensate for the terrain lighting pass.

Runtime imports in `play/`, `map/`, `game/sim.zig`, `game/attacks.zig`,
`game/rewards.zig`, `game/foe_rules.zig`, `edit/plot_fields.zig` and `edit/preview.zig` are limited to core, play and map modules. The game rule
modules may also depend on each other, except `attacks.zig` can import only
`sim.zig` from that group: rewards and foe-turn coordination remain outside attack
resolution. They cannot import raylib, UI, rendering,
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
input types. Every rostered module must parse and contain a declaration; there is
no byte minimum. Syntax and empty-module validation catch incomplete source without
requiring padding in small modules; the compiler checks references and types.

Sprite asset selection and shader definitions cannot import the sprite renderer.
Effect payloads and the impact queue cannot import the particle-effects coordinator.
These helpers also cannot import Game, Presentation or the application.
`gfx/status_marks.zig` cannot import the effects coordinator; its renderer reads
only elapsed cosmetic time and explicit mark inputs. `game/projectile_motion.zig`
cannot import Game or Presentation. Presentation supplies visibility to its motion
view, which retains the last visible position during a fade.
## Lifetimes

`ui/keywords.zig` owns underlined keyword text, screen-space hit regions and one
definition layer. Hosts call `resized` then `step` before handling input, `beginFrame` before
drawing, register terms through `text` with the actual `menu.Surface`, then draw
the definition last. Term strings come from stable definitions. Game menus and
title menus share this routing; HUD cards retain their source while the pointer
crosses into the card or definition. Keyword state is unsaved and clears with
screen, window-size and run/turn resets. Gameplay rules never read it.

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
- `chosenBlow` rolls armour and status before damage, preserving opportunity bonuses and split inheritance.
- `strikeHero` returns blocked, dodged, or a hit with resolved damage and applied
  statuses. It rolls block before hit/damage, applies guard/bide and consumes shock
  through `foeBlow`, then resolves health/mana damage before bleed, stun and chill in that
  order. Lethal or fully absorbed hits roll no statuses. It cannot award deaths or
  schedule presentation.

`game/foe_rules.zig`
- Owns enemy turn ordering, target queries, path-distance caching and ranged reposition selection from Simulation alone.
- Net throws return flight, facing and whether the throw landed; a resisted net still lands and consumes its cooldown. Healing returns the healed slot, or a successful rouse with no slot.
- Combat records the returned outcome immediately, before another actor changes the body. Rules cannot access presentation, input or application modes.

`game/rewards.zig`
- `defeat` resolves XP, drops, flask refills, gas, steam and witness fright from Simulation alone; Presentation holds dropped gold and schedules speech from its `Death`.
- Already frightened witnesses refresh their timer without another speech.
- Chest capacity failure leaves the chest and RNG untouched; the game adapter supplies the message.

`game.zig`, `game/targeting.zig`
- `Game.mode.aim` owns an `Aim`: opening creates all its fields together, `skills.closeAim` discards them, switching mode drops it.
- Barrier targeting distinguishes choosing its start from its end.
- Confirmation copies the target before closing and passes that value to execution.
- `TravelCarry` keeps queued commands (Interact included), the mouse skill set, facing and the level-up effect across node replacement.
- Same-node doors move followers in place; followers without a destination cell stay alive where they were, retaining identity and statuses.

`game/combat.zig`
- Turn order: recovery/cooldowns, hero post-action harm, gas spread, foe clocks, firebolts in flight, each foe's action then its harm, waiting newborn harm, final ward/sight.
- A braced foe (`Actor.braced`) acts down its locked line on its next action; any skipped action drops the brace. A firebolt (`Actor.bolt`) flies on after its thrower dies and freezes with its level when the hero leaves; `Presentation.bolts` is rebuilt from it.
- Consumed ticks and displacement clear even when hero death interrupts the turn.
- Split children inherit consumed ticks, so they cannot repeat their parent's harm that turn.

## Resolution and picture ordering

The adapter must finish recording one resolution before beginning another. Actor
identities (`ActorId`, persisted as integers) name bodies; `ActorSlot` names pool
storage. Neither snapshot sequencing nor a picture deadline may consume simulation
RNG. Combat rolls use `Simulation.rng`; drops use `loot_rng`; particles use cosmetic
RNG in `Fx`.

| Flow | State and RNG order | Snapshot and picture order | Regression coverage |
| --- | --- | --- | --- |
| Hero hit | `attacks.resolve`: hit check, armour/elements, statuses, `Simulation.resolveDamage`, recovery roll | `combat.woundAt`: damage debt/log, `afterBlow` split and snapshot, then recovery and `recordAttack` | `hero`: attack resolution isolation and recorded chosen/reaction/status outcomes; `picture`: each bite and arrow HP at impact |
| Incoming strike | `combat.reach` resolves any sweep victims first, then `attacks.strikeHero` owns block, hit, damage and surviving-hit statuses | `reach` records damage debt/logs and the hero snapshot before melee thorns, then death or counter, then surviving knockback. A thorn-killed attacker still knocks back; a blocked/dodged melee still permits a counter | `hero`: recorded incoming-strike RNG and isolated rule outcomes; `foes`: thorns, status rates and thorn-killed shieldbearer knockback |
| Killing hit | Damage removes the living body; `rewards.defeat` then applies XP, loot RNG, flask/mana recovery, burst terrain and fright | `landBlow` captures the dead body before `fell`; `beforeDeath` captures affected surroundings before rewards; `recordDeath` holds drops and burst effects until impact | `hero`: kill flask refill; `picture`: arrow death; `foes`: mimic loot and pyre neighbours at impact |
| Chain or reaction | `chainHit` captures target identities before any hit; each target resolves in sequence. `tactics_exec.counter` rolls its chance before the reaction's attack rolls | Every `woundAt` captures its result before the next hit. Chain delays accumulate per jump; a missed reaction still occupies its animation time | `hero`: missed reaction attribution and projectile timing; `skills`: chain and area attacks; `tactics_exec`: reaction timing |
| Status damage and splitting | `harmAfter` visits gas, steam, healing gas, ground fire, burn, bleed. Consumed ticks are marked before damage; split children inherit them before entry effects run | Each `harmTick` captures its own body/split before death rewards and the next tick. `Presentation.scheduleHarm` follows that body's action and reactions; newborn harm waits for its reveal | `picture`: burning/gassed halves and quarters; `foes`: sweep stun paid once by both halves |
| Interrupted turn | `passTurn` always defers `Simulation.finishTurn`. Hero post-action death stops gas/clocks; a killing projectile stops foe actions; a killing foe stops even its own post-action harm | Already recorded impacts remain queued; death mode and epitaph are immediate, while the body and death veil wait for the pictured impact/turn | `hero`: post-action death clears turn tracking; `picture`: killer spared gas and only the lethal bite kills |

`Presentation.stepGlide` schedules motion, blows/mending, reactions, knockback,
then status harm. Its `starts_at`/`next_at` are relative to the turn origin;
`impact_in`/`finishes_in` are remaining seconds from the current frame. `late`
converts between them. When one frame crosses several deadlines, the impact queue
uses snapshot sequence to prevent old health/status from replacing newer state,
and releases every event's mana debt once. This is covered by the queue's overdue
impact test and `hero`'s multiple incoming impacts in one frame.

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

## Monster zoos

`map/zoo.zig` owns a reusable encounter; either kind of atlas node can hold one
optional `zoo`. `game/jail.zig` adapts its door interaction to turns,
logging and presentation. The local gate blocks movement and sight and is separate
from atlas travel doors. Opening it spends a turn and wakes the surviving room
occupants; it stays open for retreat. A locked gate consumes one carried Small Key.
Trying a locked gate without one spends no turn. Keys from any compatible source
work; `game/rewards.zig` puts one in the encounter's outside chest.

Author an encounter in that node's map text:

```text
zoo 40 18 8 6 w
zoo_key 32 28
zoo_foe 4 rat
zoo_foe 3 goblin
zoo_foe 2 pib
zoo_foe 1 bandit_netter
```

The first line is x, y, outer width, outer height and entrance side (`n/e/s/w`).
`zoo_key` positions the Small Key chest; omitting it leaves the closed door unlocked.
Each `zoo_foe` supplies a positive
relative weight and a stocked enemy kind; the pool is independent of ordinary
packs. Dimensions are 5–10 cells, with one clear inner threshold and two chests
against the far wall. Every remaining inner cell gets a weighted enemy while actor
capacity permits, including reserves for slime splitting. Swimmers receive shallow
water under their cells; mimics reveal and restore their ground when released.

The room is stamped after terrain generation, with a walkable perimeter and
short connections for its approach and key chest that stay outside its walls. Unrelated
sealed rooms remain sealed. The chest is outside the perimeter and is
connected before the door is sealed. Ordinary packs and derived NPC placements
avoid the encounter. Authored foes, travel doors and fixed painted sections cannot
overlap it; roaming painted sections cannot share its node. The editor previews
the encounter and counts its interior as reachable through the unlockable door.
Placement and pool editing currently use map text.
Editor door, foe and start placement preserves these encounter reservations,
including the replacement start chosen when its node is removed.

The Caravan node places this 21-monster room east of the northbound route, with
the key chest to its southwest. `--shot-zoo` captures the chest, key loot, closed gate, release and
packed interior using the real map. Tests cover generation, visibility, all enemy
kinds, input, map parsing, portable saves and revisits.

## Verification

Dialogue layout lives in `ui/talk.zig` and never paginates; authored `then` lines are
the only page breaks. `game/talking.zig` drives the conversation.
The editor previews the same layout. Long-form writing limits, independent editor
scrolling and the source text concern tree are documented in [TEXT_EDITOR.md](TEXT_EDITOR.md).
`core/wire.zig` traverses aggregate save values by reference, so large authored
dialogue buffers do not create recursive stack copies during encoding.

Run `check.cmd` and affected test filters for each change, then the full suite
after combat, scheduling or lifecycle changes. Preserve seeded outcomes and the
legacy reader fingerprint and portable save identities. Tests use in-memory saves and maps. Run actual headless
captures for presentation/editor changes, inspect PNGs, benchmark, and finish with
`build.cmd`. All generated captures, timing logs and temporary scripts live in `%TEMP%`.
The full test command also runs the source-boundary checker's own tests. The
Windows CI workflow runs the same check/test/build scripts and packaging tests;
[README.md](../README.md) describes setup on a fresh machine.
