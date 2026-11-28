# Runtime contracts

Simulation owns gameplay state and RNG. Presentation records each resolved event and displays it at impact. Save field classification, versioning and migrations are documented in [save compatibility](SAVE_FORMAT.md).

| Change | Owner | Regression coverage |
| --- | --- | --- |
| Start, travel, resume, queued actions | `game.zig`, `game/sim.zig`, `game/presentation.zig` | [World](../src/game/tests/world.zig), [saves](../src/save.zig) |
| Attack rolls, chosen actions and reactions | `game/attacks.zig`, `play/chronicle.zig` | [Hero](../src/game/tests/hero.zig), [skills](../src/game/tests/skills.zig) |
| Foe ordering, targeting, allies and support | `game/foe_rules.zig`, `game/combat.zig` | [Foes](../src/game/tests/foes.zig) |
| Damage, splits, deaths and rewards | `game/combat_impacts.zig`, `game/rewards.zig` | [Picture](../src/game/tests/picture.zig), [loot](../src/game/tests/loot.zig) |
| Turn deadlines and impact delivery | `game/turn_schedule.zig`, `gfx/impact_queue.zig` | [Schedule](../src/game/turn_schedule.zig), [queue](../src/gfx/impact_queue.zig) |
| Terrain, status effects and sight | `map/grid.zig`, `map/fov.zig`, `map/lume.zig`, `play/terrain.zig` | [Terrain](../src/game/tests/terrain.zig), [lighting](../src/gfx/light_tests.zig) |
| Skill contracts and execution | `play/skill_contract.zig`, `play/skillbar.zig`, `game/skills.zig`, `game/tactics_exec.zig` | [Contracts](../src/play/skill_contract.zig), [tactics](../src/game/tactics_exec.zig) |
| Authored scripts, dialogue and quests | `map/script.zig`, `map/script_text.zig`, `play/trigger.zig`, `game/talking.zig` | [Script parser](../src/map/script_text.zig), [triggers](../src/play/trigger.zig), [dialogue](../src/game/talking.zig) |
| Editor transactions, placement and derived data | `edit/history.zig`, `edit/placement.zig`, `edit/preview.zig`, `edit/thumbnails.zig` | [Editor](../src/edit/tests.zig), [preview](../src/edit/preview.zig) |
| Procedural terrain and encounters | `map/procgen.zig`, `map/section.zig`, `map/zoo.zig` | [Procgen](../src/map/procgen.zig), [atlas](../src/map/atlas.zig), [map text](../src/map/atlas_text.zig) |

## Dependency boundaries

`tools/source_rules.zig` checks actual import tokens, exempts test bodies and enforces direct dependencies. The build checks that each source module parses, declares something and appears in the unnamed test roster in `main.zig`. [Boundary checker](../tools/source_rules.zig)

- Gameplay rules, map code, editor preview and plot-field validation depend on core, play and map data. The four game rule modules may share rules. Attack resolution can import only Simulation from that group.
- `turn_schedule` accepts explicit motion, visibility and occupancy facts. Its imports are limited to std, core and play. `combat_impacts` captures completed outcomes and calls `tactics_exec.counter` for melee reactions and `tactics_exec.landed` for split bodies. Its dependency boundary excludes `combat`, `skills` and `foe_rules`.
- Editor widgets, metadata, naming, history and thumbnails work without Game, App or Editor. Interaction receives Editor and canvas bounds. Character view, layout, cards and stats work without Book navigation.
- Sprite assets/materials, light model/GPU resources, input mappings, status marks and impact payloads stay independent of their coordinators. Device polling belongs in `core/input.zig`. Shared wording and bounded text live in core. `play/log.zig` owns saved history and `ui/journal.zig` draws it.

## Lifetimes

A new run resolves a vacant landing on the seeded floor before replacing live state. Idle frames and free actions spend no turn. Simulation resets transient turn data through `resetTransientTurn`. Presentation clears pending work on a new run and settles a loaded picture without replay. Preserve actor IDs across visits. Use `ActorId` for identity and `ActorSlot` for pool indices.

Travel carries queued commands, the mouse skill set, facing and level-up effects across node replacement. Same-node doors move followers in place. Followers without a landing keep their positions, identities and statuses. An in-flight hurl outlives its thrower and freezes with its level until a revisit.

`Game.mode.aim` owns the whole targeting session. A barrier has separate start and endpoint stages. Snapshot the confirmed target before closing aim. Preview uses only information available to the hero. Confirmation checks the live level before movement, placement or spending. [Terrain and targeting](TERRAIN.md)

Screen-space inspection shares the inverse lens projection for world picking and uses projected body bounds for focus and tooltips. HUD targets use screen coordinates. `ui/keywords.zig` takes input before its host, records terms with their drawing surface and draws definitions last. Clear its unsaved state on screen, size or run transitions. [Presentation](DATA_PRESENTATION.md)

### Rendering and visibility

Strict gameplay sight controls interaction and dynamic emitters. A fading body, projectile, NPC, hazard or loot pile retains its last visible picture. Clip hook chains to visible cells and cosmetic bursts to pictured cells. Motion, health changes or drops out of sight must not update the remembered picture.

`gfx/light_visibility.zig` supplies the smooth visibility field for lighting, water and weather. Exploration feathering stays inside known terrain. Memory grading darkens and desaturates explored ground. Reflections distinguish remembered scenery from live bodies and effects. Shadow casters sample light independently of fog and receiver visibility fades the mask. Bind the receiver light-map sampler **after** changing blend mode because raylib flushes auxiliary texture bindings.

Cap sprite illumination at the authored colour. Emission and impact flashes are separate. Slime bodies, reflections and shadows share translucency. Cosmetic light from slimes and bloats follows presented visibility.

A node can override weather with map lines such as `location forest beams` and `location coast coastal`. On entry, climate identifies edge-connected coastal sand and water (including bridges and temporary ice), then forest within two tiles of trees. Coast takes priority. Save the derived field with the level. Rules read the occupied cell. Rendering blends neighboring locations and samples the hero's drawn position for the sky. Beam weather uses the eased clock for the 08:00–10:00 and 16:00–18:00 transitions. Bloom samples the viewport. Atmospheric shafts also read nearby off-screen terrain. Composite atmosphere over world objects before grading and UI.

## Resolution and picture ordering

Keep combat RNG, loot RNG and cosmetic RNG separate. Capture each resolution before the next can alter its actors. `passTurn` advances recovery and cooldowns, hero post-action harm, gas, foe clocks and in-flight hurls, then each foe's action and harm, newborn harm and final ward/sight. `finishTurn` clears consumed ticks and displacement even when death interrupts the turn.

| Event | Required order |
| --- | --- |
| Chosen hit | Resolve hit, armour/elements, statuses and damage. Capture health, split and attribution before death rewards or the next blow. A barrel and an actor have different impacts. A miss leaves a barrel intact. |
| Incoming strike | Resolve sweep victims, then block, hit, damage and guard/bide/shock. On a surviving, unabsorbed hit, roll bleed, stun and chill in order. Capture the hero before thorns, death or counter. A thorn-killed attacker can still knock back. |
| Death | Capture affected neighbors before rewards. Resolve XP, drops, recovery, burst terrain and fright once. Reveal drops, speech and burst consequences at their pictured impacts. Refreshing fright does not repeat speech. Chest capacity failure preserves the chest and RNG. |
| Chain, sweep or reaction | Capture target identities before the first hit so splits are not struck twice. Resolve each target in sequence. Roll the counter chance before its attack. Missed reactions still take animation time. |
| Status harm | Visit gas, steam, healing gas, ground fire, burn and bleed in order. Mark consumed ticks before damage so split children inherit them. Schedule newborn harm after reveal. |
| Interrupted turn | Hero post-action death stops gas and clocks. A lethal projectile stops foe actions. A lethal foe attack skips that foe's remaining harm. Deliver already-recorded impacts and delay the pictured death veil until its scheduled point. |

`Presentation.stepGlide` schedules motion/projectiles, blows and mending, reactions, knockback, then status harm. `starts_at` and `Turn.next_at` use the turn origin. `impact_in` and `finishes_in` use seconds from the current frame. `late` converts between them. Track the hero's pictured cell after knockback. Age existing effects before delivering newly ready events. If several deadlines pass together, snapshot sequence decides pictured state and each event releases its mana debt once.

`foe_rules` owns turn order, path-distance caching, support and ranged repositioning. Resisted nets still land and consume cooldown. Slow hurls share the actor's bolt record and cooldown, and careful throwers wait for a clear lane. Shamans prioritize waking or mending kin. Netters can quickstep during recovery unless pinned or confused. A braced foe attacks along its locked line on its next action and drops its brace if that action is skipped.

## Adding a skill

1. Define mechanics and geometry in `play/`. Examples include [Pinning Shot](../src/play/pinning.zig), [Nova](../src/play/nova.zig) and [Overwatch](../src/play/tactics.zig).
2. Register the action and delivery in `play/skillbar.zig`. Its checked contract supplies targeting, damage, status and special-execution requirements. Use the same `AfflictionChance` for display and rolls.
3. Wire class kit, ranks and costs through skillbar and progression. Add the icon in `gfx/line_icons.zig`. Route targeting through `openTargeting` and `confirmAim`. Keep specialized tactical resolution in `game/tactics_exec.zig`.
4. Test preview and execution against the same geometry, costs and scaling. Cover hidden targets, split bodies and pictured impact timing where applicable. [Skills tests](../src/game/tests/skills.zig)

## Adding an editor tool

Start a gesture through `Editor.gesture`. Send terrain changes through `changed` and record link or metadata edits through `bank`. Brushes, paste and previews share placement geometry. `interaction.zig` routes modal, rename and view changes before canvas input. Pass current `ed.controls()` and font to widgets so a new modal takes effect immediately.

The first real change records the gesture. A no-op preserves redo. Graph drags use `previewNode`, then `commitPreview` or `cancelPreview`. Focus loss cancels unfinished shapes, links and graph drags, and ends freehand painting at the last applied cell. Prepare undo/redo storage before mutating anything. Retained history copies active nodes and script entries, including unfinished authoring data.

Invalidate derived scenes on selection, edits and rerolls. Call `preview` before reading them. Invalidate only affected thumbnails unless node identities change. Thumbnails show stamped terrain before creature placement. `Game.art` owns graphics readiness for play and editor. Text-view source edits and attribution are separate from map undo. [Text editor](TEXT_EDITOR.md)

## Landscape shapes and niches

Caravan uses `map/biome/tee.zig` for forest bends, roads and river. Goblin Camp's `encampment` topology links unequal clearings. Use `feature setpiece` with `piece chest_niche`, `light_niche` or `moat_camp`. Niches rotate, take the biome palette and open onto existing ground. Preserve props, painted sections and reserved lots. Connectivity bridges the moat. Caravan's `goods`, `bedrolls` and `tents` dress the camp. An NPC spot `on <tile>` chooses a free matching cell near its center. Inspect these with `--shot-landscapes`.

## Monster zoos

Either kind of node can have one zoo. Author its outer box, entrance side, optional key chest and weighted inhabitants in the map text.

```text
zoo 40 18 8 6 w
zoo_key 32 28
zoo_foe 4 rat
zoo_foe 3 goblin
zoo_foe 2 pib
zoo_foe 1 bandit_netter
```

Dimensions are 5–10 cells and sides are `n/e/s/w`. Without a key chest, the gate is unlocked. Reserve one inner threshold and two far-wall chests. Fill other interior cells by positive foe weights while reserving actor capacity for slime splits. Swimmers receive shallows and mimics restore their ground on release.

Stamp the room after terrain generation. Connect its perimeter and exterior chest to the arriving hero's floor component. Editor previews and thumbnails use the map start on its node, otherwise the first travel door or, if there are no doors, the grid centre. Stamping without an entrance uses the largest floor component. Preserve unrelated sealed areas. Route around painted walls, chests, glow plants and authored swimmers where possible. Cross a swimmer's cell with shallows if necessary.

The editor keeps new barrels, doors and foes out of reserved cells and prevents starts inside the room or on its key chest. Fixed painted sections cannot overlap the room and a roaming section cannot share the node. Derived NPCs and ordinary packs avoid the encounter. Reachability checks treat its gate as unlockable.

`game/jail.zig` opens the gate for a turn and wakes survivors. A locked gate uses one interchangeable Small Key. A failed attempt spends no turn. The gate stays open. `--shot-zoo` covers the Caravan encounter from key chest through release.

## Verification

Run the repository checks and headless captures listed in [AGENTS.md](../AGENTS.md#verification). Combat, scheduling and lifecycle changes require the full suite. Use in-memory saves and maps for tests.
