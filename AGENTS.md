# AGENTS.md — Cistern

Working title: **Cistern**. Grid roguelike in **Zig 0.14.1 + raylib**: archer, wizard and knight; rats, slimes, bloats and pibs;
breakable barrels, treasure chests, equipment, XP and class progression. Art starts as glyphs, replaced by the owner's PNGs.
Source paths below are relative to `src/`; scripts, docs and assets are relative to the repository root.

## Working rules

- Prefer no comments in code. Ask before making product/design decisions. Don't commit, push or branch unless asked.
- Preserve unrelated work, including existing uncommitted changes. Keep verified workflow learnings succinct;
  update existing guidance instead of appending a diary.
- **No scratch files in the repo**, including `output/` and ignored `shots/`. Put backups, previews, mocks,
  reports, timing roots and throwaway scripts in `%TEMP%` or the session scratchpad. The owner's forest-art
  backups in `assets/backup/` are the sole backup exception. Normal build/cache directories remain in use.
- Windows/PowerShell: use `login: false`, read UTF-8, preserve UTF-8 without BOM, and prefer targeted patches.

## Build and verification

- `zig` is not on PATH; `_zig.cmd` is the single toolchain definition. Run scripts from this directory:
  `./check.cmd` type-checks executable and tests without linking; `./test.cmd [filter]` runs tests;
  `./build.cmd` builds without launching. Use tests that print meaningful counts.
- Builds, checks and tests default to Debug. `./build-release.cmd` or `./build.cmd -Doptimize=ReleaseFast`
  explicitly selects ReleaseFast. With raylib cached, a measured small edit took 6.5 s in Debug versus
  25.4 s in ReleaseFast; Debug's headless update/draw averaged 1.54 ms CPU per frame.
- Finish code/art handoffs with `./build.cmd` so the owner's next run reuses it. If the normal executable is
  locked, use `./build.cmd --prefix zig-out-dev`. **Do not launch interactive play for verification.**
  `run.cmd` builds, then launches the exe directly (`zig build run` can hang after the game exits), killing an
  existing game first; `edit.cmd [path]` uses it for `--edit`
  (default `maps/main.map`). These are owner-facing entry points.
- Every `src/**/*.zig` module except the root `main.zig` must be imported in `main.zig`'s `test {}` block.
  `build.zig` checks this on every build step and rejects those modules if smaller than 512 bytes.
- `shot.cmd` builds into `zig-out-dev` but writes `shots/` under its working directory. For audits, build
  with `./build.cmd --prefix zig-out-dev`, then run the executable from a fresh `%TEMP%` directory containing
  a copy of `maps/`. This keeps generated frames outside the repo:

  ```powershell
  $projectRoot = (Get-Location).Path
  $shotRoot = Join-Path $env:TEMP ('cistern-shots-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $shotRoot | Out-Null
  Copy-Item -LiteralPath (Join-Path $projectRoot 'maps') -Destination $shotRoot -Recurse
  Push-Location $shotRoot
  try {
      & (Join-Path $projectRoot 'zig-out-dev/bin/cistern.exe') --shot
      if ($LASTEXITCODE -ne 0) { throw "Shots failed: $LASTEXITCODE" }
  } finally { Pop-Location }
  ```

- For concurrent owner play, copy the built executable into the temporary shot directory with a distinct
  basename before `--shot`; `run.cmd` kills every process named `cistern.exe`, including headless captures.
- `--shot-ui` runs only Character/HUD captures; use the same temporary-directory procedure as `--shot`.
- Inspect actual headless PNGs. `game.zig`'s `shoot` and helpers define the coverage: abilities, editor,
  maps, HUD sizes/devices/resources, day/night memory, forest, hidden/offscreen shadows and water.
  `water-reflections/00.png` through `39.png` cover four seconds of idle play; `water-mirrors-*.png`
  show day/night/torch reflections. `--shot-cinema` captures `cinema/` off/individual/all comparisons,
  checks hidden pixels, exact restoration and resized targets, and times effects on/off; use the same temporary-directory workflow.
  The same executable's `--bench`
  reports startup, headless CPU frame time, texture residency/loading/reuse and draw cost with 0/8/32 effect lights.
- Tests must not write save or map files. No interactive window is needed for unit tests. The full Debug
  suite exercises thousands of generated maps and can take several minutes; check CPU activity before
  treating it as stalled. `build.zig` runs the test artifact directly with inherited output: raylib image
  logs write to stdout and corrupt Zig 0.14.1's `--listen=-` test protocol, causing a deadlock.
- When `game.enter` replaces an actor pool, copy the carried actor into an initialized `var` before
  replacing storage. A conditional `const` copy of `h.*` aliased the replaced pool on Zig 0.14.1;
  door/save tests caught it. Preserve this workaround.

## Input, UI and application

- **`core/input.zig` alone reads input devices.** Controller is primary; keyboard mirrors every action.
  `docs/CONTROLLER.md` describes the scheme; current mappings/defaults live in `input`, `skillbar.Bar.of` and `progress.State.bar`.
  Keep skill lists and balance values in their source modules instead of duplicating them here.
- Always show input controls as glyphs, never as key/button names in prose. Use `look.Prompt`,
  following the last device (`State.device`, `input.padOf`), including tree hints. The desk editor uses
  keyboard/mouse glyphs through `gfx/prompt_text.zig`; `input.Desk` owns its marked shortcut captions.
- `play/skillbar.zig` owns primary/secondary sets, the bindable secondary modifier and class kits.
  `input.SLOT_ORDER` numbers keyboard slots while skipping the modifier, which uses Ctrl. Menu keys are
  inactive in play; targeting uses menu confirm/back keys (`State.context`). Typing (`State.typing`) must not activate slots or movement. Character toggles on a press, never on a hidden hold.
- Reticles use standard confirm/back controls; on the keyboard alone the aimed slot's number also confirms
  (`State.aimed`), while a pad's skill button never does. B always cancels targeting,
  including a skill opened with B; the opening press never confirms or cancels the new reticle.
  Esc backs out one layer at a time and opens pause only from play. Clear raylib's exit key with
  `input.claimKeys`; Esc must never close the window. Menu does not open pause over death.
  Pause's Debug submenu contains Restart Map, Reveal Map, Composed Lighting, Bloom, Atmosphere and Depth Of Field.
  Reveal shows terrain and minimap without changing gameplay sight or saved exploration; turning it off restores
  the normal view. The four cosmetic effects default on. Debug settings are not saved.
- Inspect (`Mode.inspect`, R3 or I) is the HUD's tooltips: the stick/d-pad walks the orbs, slots, shown
  statuses and the event log (`game.spotsOf`, nearest along the way pushed), `hud.tooltip` names and describes the one it is
  on, without naming any input. Any back-out or the same button again closes it; it spends no turn.
  In play/aim the same tooltip shows for the part under the mouse (`State.pointer`, `game.hovered`).
- Start / Menu / Options opens Character directly; Select / View opens the game menu. Keyboard Tab / Esc mirror them. Character opens equipment, the inventory list, stats, passives and class skills in `ui/book.zig`.
  Player-facing hand slots are Main hand (viewer-left) and Offhand (viewer-right).
  Two-handers identify the occupied offhand. Menu accents share `look.UI_GOLD/UI_FOCUS`:
  muted gold, never bright yellow.
  Character/binding panels share `menu.Surface`: half-rate growth, capped at 1.25x,
  with 16px detail and 20px body text before scaling. Keep panels centered with margins.
  `play/items.zig` owns slot/requirement transactions; `play/progress.zig` owns XP, point pools and skill ranks;
  `play/passives.zig` owns the radial passive graph and grants; `ui/trees.zig` draws both tree panels.
  Before changing either panel, read its maintained reference: `docs/DIABLO2_SKILL_TREE.md` for skills,
  `docs/POE2_PASSIVE_TREE.md` for passives. Keep those documents aligned with subsequent changes.
  Passives open zoomed in. The left stick browses on its actual bearing, the right stick pans, and
  D-pad up/down zooms. Keyboard navigation, shifted pan, zoom and overview mirror those actions;
  keep device reads in `input` and the control reference in `docs/CONTROLLER.md`.
  Passives lift the Soulslike three-arm, six-branch layout: small stat nodes, larger interest nodes,
  paired-stat bridges and six double-ring capstones. Use very simple graphics. All three origins open
  from the central hub; the class origin is free and grants no bonus. Branches follow outward feeders;
  bridges work both ways. The same feeders must govern eligibility and drawn links.
  `Game.character` holds only unsaved navigation state; item/point actions are commands resolved by the game.
  Item actions and point allocation execute on one press; item changes spend one turn and keep Character open.
  Shoulders / Q and E change tabs; Back closes Character directly. Skills owns binding. Point allocation is free.
  Interact directly handles a sole object, or lists multiple underfoot and adjacent visible objects; a press while busy waits for `quiet` (`Queued.interact`)
  instead of queuing its button's skill. Item commands wait out door travel. Gold collects automatically on movement.
  See `docs/PROGRESSION.md` for rules and the inspected D2/PoE2 paperdoll references.
- `app.zig` owns title/game/editor transitions; the game requests `Game.exit`, and `Game.back` identifies
  its caller. New reads `atlas.START` (`maps/start.map`) fresh, falling back to a generated floor only
  when that default file is missing. Reject malformed maps and starts without open floor.
- New runs select class and name, then use a free save slot; refuse when all slots are occupied.
  Saved-run death deletes the slot and returns to title on restart input; unsaved play can restart.
  Editor play-tests use the archer and no save slot. `Game.unkillable` is a debug option, never saved.
  Use the hero's name in the log/death screen, never "you".
- `Game.screen` controls layout; fullscreen can change it at runtime. `ui/hud.zig` follows
  `docs/HUD_LAYOUT.md`: a centered 640px assembly, life/mana orbs, skill icons, cooldowns, an experience bar and ailments;
  minimap at top right. The map continues behind it, with `hud.COVER` allowing bottom rows to clear it.
  No live name label, counters, clock display or permanent control instructions. The persistent event log
  occupies the bottom-left gutter without a heading; newest entries append at the bottom, with text,
  background and border fading out toward the top. Follow `docs/DATA_PRESENTATION.md` for item cards,
  comparisons and stat wording: relevant properties only, explicit units, and effects before metrics.
- `gfx/font.zig` draws small Balthazar text from native-size, point-filtered atlases; larger text and
  symbols use the mipmapped atlas. It falls back to raylib's font in tests/load failure.
  Drawn strings are ASCII except tile symbols baked through `look.TILE_CODEPOINTS`; those use
  their ASCII fallback without the atlas.

## Map, editor and saves

- `map/atlas.zig` owns the map: bespoke/procgen nodes and reciprocal door links. Procgen nodes store
  settings, features, packs and climate, not seeds; `game.rollOf` derives each roll from the run seed and
  node. Keep visited nodes as left. Travel waits for the turn's presentation, preserves the hero's state,
  and uses `atlas.landing` when the destination is occupied. Map text is parsed strictly and saved by
  writing beside the original and renaming over it.
- `edit/editor.zig` edits the map; gameplay must not depend on editor state. Preview uses the same
  terrain drawing and pack placement as play, but procgen rolls afresh for a run. One gesture is one undo:
  `gesture` then `bank` on the first change; graph drags bank on release (`keepDrag`). Cancel (`drop`)
  restores the drag without consuming undo or losing redo. `Editor.request` guards leaving, quitting,
  opening and New when dirty, including window close. F5/F6 play-test unsaved; `HELP` stays checked against
  `Desk` captions. Keep Things/issues, object-viewer metadata and cursor previews consistent with the map.
- Objects > select a foe > Fight launches `map/spar.zig`'s arena using the app's separate map, with the
  normal editor-test archer and no save slot. Returning preserves the editor map, modal and undo history;
  death retry and Debug > Restart Map recreate the selected opponent. `--shot` includes the arena and character pages.
- `save.zig` freezes the whole run: map, visited/current nodes, actors, class/name, resources/statuses,
  RNG, log, skill bar, time, gold, inventory, progression and each node's ground drops. `core/store.zig`
  fingerprints types, plus the passive tree's layout (`save.TREE`); reject incompatible or incomplete
  saves before mutating the game. Autosave snapshots on the frame and writes on a thread, only while
  quiet and outside door travel; flush again on departure. Atomic completion gates reuse of the buffer.
  Failed writes rearm dirty state even while idle and retry on `GAP_S`; death ends the save.
- `map/procgen.zig` rolls a base, then ordered features on a separately salted RNG stream, so adding
  features leaves the base roll unchanged. Preserve bare rooms' `gen.around` path. Seal edges, reopen
  doors, supply a clearing if needed, connect open regions, then remove invalid/path-blocking props and
  reshape walls. `map/carve.zig` is the shared toolkit; biome/feature `Params` own generator settings.
  `Floor.outdoor` decides sky exposure, independently of decoration.
- `grid.TERRAIN` owns tile solidity, sight blocking, underlay and liquid properties; `Tile.letter` owns
  serialization; `look.TILES` owns appearance. Keep these distinct. The grid is y-down and gameplay
  ranges use Chebyshev distance. Diagonals pass between blocked side cells, even if both are blocked:
  movement checks its destination; sight, projectiles and effects also pass through the tight gap.
- Walls/forests use stored eight-neighbour masks, with corners joined only when both adjacent sides
  join: 47 shapes. `procgen.reshape`/`Node.stamp` produce them; revelation never changes them.
  Brick walls join walls, forests join shrubs. `Level.wallShape` is brick-only; `tileShape` handles both.
  Missing forest masks are restored on save resume. Torch/barrel placement must preserve routes;
  barrels stop movement/arrows and break for gold in one hit, with no HP.
  Chests spawn closed, open when stepped toward or through Interact for more gold than barrels and an item,
  and stay empty and walkable afterward. Attacks never open them. Wilds' `loops` reconnects side paths;
  `rewards chests` rewards substantial branches, fills sparse maps with spaced chests in sheltered alcoves,
  and scatters barrels as minor gold rewards. The Strand enables both; rewards must preserve routes.
  Its swamp trees (`assets/swamp-tree.png`, standalone `swamp_tree` tiles) scatter on dirt
  within three cells of water/shallows. Scatter's `water_range = 0` leaves other maps unrestricted.

## Combat and simulation

- `play/attrs.zig` owns Strength/Dexterity/Intelligence and what they derive: life, mana, heavy/light/spell
  damage, crit and dodge. Strength scales heavy weapons; Dexterity scales light weapons, regardless of range.
  `skillbar.Act.attack` selects melee/ranged/spell delivery; `items.Gear.scaling` selects the matching
  weapon's scaling for both live damage and previews. Wands and staves have no innate attack damage.
  Offhands include tomes, orbs, bucklers, shields and totems; two-handed weapons clear that slot.
  Class bases feed passive allocations and equipped modifiers;
  `game.heroAttrs` is the runtime source. Armour reduces physical bites before mana shield; elemental/status
  damage keeps its separate rules. Equipped weapons and skill ranks affect hero damage and its previews.
  Every hero blow goes through `game.scaled` (via `heroRoll`/`heroScaled`), which draws the crit after the
  damage roll, then rounds each part up as often as its fraction. Skill rolls are `damage.Base` (`Act.bases`); an area
  blow rolls its base once and scales, crits and rounds per foe. Skill tooltips show the scaled non-critical range.
- `play/hero.zig` maps class to body; `skillbar.kit` restricts bindings and `Bar.of` supplies defaults, both
  narrowed to learned skills by `progress.State.kit/bar`. `skillbar.Act` derives base costs, cooldowns,
  descriptions and targeting from each skill module; `progress.State.cost/cooldown` apply rank. Module
  descriptions say only what a skill does: `game.describe` appends mana, turn and cooldown at the hero's rank.
  Mana checks, spending, slot dimming, tooltips and descriptions must agree. Preserve resources/statuses across doors and saves.
- **Target previews and resolution share legality.** `bow.aimable` requires the mark and every traversed
  cell to be lit; geometric line clearance alone is insufficient. Spend nothing before confirmation.
  Area previews/damage/effects share geometry (each module's `burst`/`around`, `glacial.spread`, `cleave.arc`); use `fov.castInto` for
  terrain occlusion without changing sight or memory. Capture area targets before damage so newborn
  slime halves inherit statuses without being hit twice by that burst.
- Juke is the free leap (`juke.FREE`); Blink spends a turn. Leap cursors may cross invalid cells but
  confirm only visible vacant landings. Idle frames advance no simulation, mana recovery or cooldowns.
  Flasks take a turn, recover from that turn's end, and restart recovery when drunk again; kills refill them.
- `skillbar.SKILLS` owns each action's module, reticle and attack type; damaging actions must declare one.
  Skills dispatch by module declarations (`afflict`, `burst`, `JUMPS`, `around`, `Ward`, `knocked`).
  A pin (`pinning.Pin`) holds a body to its cell on its
  turns, counting down like chill; it still strikes the hero beside it and cannot be knocked back.
  A mana shield (`ward.Ward`) takes the hero's harm from mana first, in `game.hurt`; the orb shows that
  mana through `Game.mana_held` until the blow lands, as `flasks_shown` holds a kill's refill.
- **`Pool.damage` is the only HP-loss path**, apart from splitting a slime's remaining HP and restoring
  carried state. Elemental resistance applies separately per element, rounding down, clamped to
  -100..100; physical damage is unresisted (`play/damage.zig`).
- `Row.splits` splits a surviving slime below half HP, down to quarters. Each half gets half the remaining
  HP (minimum 1), with inherited statuses/clock; the new half acts next turn. If no adjacent cell is free,
  retry on a later blow. Pack quotas/makeups (`play/pack.zig`) and bespoke placement must reserve capacity
  for all eventual halves via `actor.roomFor`. `Kind.family` keeps their counts together.
- `Row.movement` and `Row.foe_type` describe every kind and appear in the object viewer; heroes have no
  foe type. Bloats fly; ground-only water footsteps must not be added to flying bodies.
- Preserve Brogue's turn order: hero action and its harm, gas spread, then foes nearest the hero first,
  each followed by gas, burn and bleed. Bloats burst however killed; foes do not enter gas from clean air.
  `map/gas.zig` alone advances gas; it spreads through open cells, including liquids.
- Burn/bleed begin next turn; refreshing does not stack or postpone a due tick. Bleed doubles on movement,
  including hero leaps. Chill advances on enemy turns, preserving its act/act/skip cadence on refresh.
  A skipped action still takes gas/burn/bleed; waiting newborn halves process inherited status ticks
  without duplicating the parent's already-applied ticks.
- `play/clock.zig` is the one hidden action clock: `clock.TURN` ticks per turn, `Row.pace >= TURN` because
  presentation supports at most one action per foe per turn. Check chill before the stalled-action return.
  Use `Clock.delay`/`Clock.stun` for delays/stun, with no separate stun status or visible clock.
- A pib witnessing a nearby foe death wakes and flees (`FRIGHT_REACH`, `FLEE_TURNS`); subsequent deaths
  refresh it. Cornered beside the hero, it attacks. Fright speech waits for the death's presented impact
  and uses cosmetic RNG.
- `map/day.zig`'s `Game.clock` is simulation: saved whole minutes, advanced by spent turns on every
  node. `map/lume.zig` uses it for outdoor sight; `Game.hour_shown` only eases the rendered lighting.
- `map/fov.zig` owns line of sight; `map/lume.zig` owns visibility from light. `Level.los` is geometric
  sight; `Level.lit` additionally requires sky, torch or carried light. Terrain is remembered; bodies are
  shown only where lit at their presented center. Rendering never decides visibility.

## Rendering contracts

- **The picture lags the mechanic.** Simulation never reads presentation. `Game.pictured`/`fx.After`
  apply each visible blow when it lands; HUD life and vignette use presented HP. Deaths, barrel removal,
  slime births, status markers and speech follow that timing. Event-log lines said while a turn resolves stay
  hidden (`Log.held`) until it is `quiet`; gold taken on a step stays drawn while the hero glides there. Foes turn/move at their stagger position.
  Update ongoing effects before starting new ones. `Game.busy` covers the slowest glide/projectile/flash;
  movement, skills and interactions pressed while busy are queued (`Game.pending`, the latest wins, but a repeating
  held walk never displaces a skill or interaction). Queued interactions survive door travel and open nearby after arrival.
  Skill activation/confirmation (including Wait/Shoot) requires `quiet`.
- `gfx/look.zig` owns pictures and `look.Assets` map residency. Load required textures before drawing,
  including later slime forms and delayed deaths; retain common textures/normals and unload unused map
  assets. Title loads only the font; play graphics load lazily. HUD and bind picker share `look.drawSkill`.
- `gfx/ground.zig` owns real ground layers. `ground.bedAt` chooses the neighbours' majority underlay,
  lowest rank on ties, then `look.under`; rock covers its cell. Grounds without sheets draw below those
  with sheets, each group retaining rank order. `Corners.mask` includes higher layers; `Corners.under`
  fills beneath their receding edges. Preserve transparency and underlays; never substitute opaque
  cell fills beneath artwork. Play omits unseen cells and clips ground overhang to the map boundary;
  editor shows all.
- `gfx/light.zig` owns cosmetic light and fog. Draw ground/underlays, shadow mask, then standing tiles,
  so walls cover shadows. Terrain gets one 2x-modulate light-map pass, with no extra terrain tint.
  Body normals shade per pixel; motes/ground gas draw before lighting, flames/glow afterward.
  Gas also veils prop/body artwork at half its ground opacity (45% maximum), respecting sprite alpha
  and presented positions; brick and rock walls stay clear. This overlay does not change gas spread.
- Shadows/contact pools combine by channelwise `GL_MIN`, never stacking darker than the darkest source.
  `Light.onCaster` ignores fog: unseen/offscreen casters still cast when lit. Receiver visibility in the
  light-map alpha fades shadows, keeping unseen/remembered ground unchanged. Keep the `CAST_MARGIN` culling
  margin (from `light.CAST_REACH`) and presented actor position/birth/death. Bind the receiver light-map sampler after blend-mode
  changes, which flush raylib's auxiliary texture bindings.
- Floor ambient at memory RGB before adding lights, preventing a dark ring around the lantern. Memory
  reaches black at the unseen boundary. Blur sight only over seen cells, and open-ground sight only over
  open ground, so unseen cells do not dim visible ground and walls do not leak sight behind them.
- `gfx/sky.zig` lights outdoor nodes only; `sky.keyDir` chooses sun/moon and limits shadow length.
  Sun shadows remove at most 45% of sky light; moon shadows also darken carried light. Forest shadows
  keep joined footprints continuous; canopy pools and near-horizontal streaks remain soft. Torch shadows
  fade beneath the source. Every step-blocking non-liquid tile casts. Climate changes appearance, not sight.
- `gfx/cinema.zig` owns subtle bloom, water mist/canopy shafts/dust, and scenery-only depth of field;
  `gfx/light.zig` applies the composed daylight profile to terrain, bodies and glints together.
  Bloom uses bright visible light sources and actual water glints; atmosphere is outdoor and live-visible only.
  Composite before bars, reticle outlines, speech and HUD. Copy scene RGB without applying its lighting alpha again.
  Depth of field affects only foliage/decorative sprites beyond the hero's sharp band, never ground, bodies or interactables.
- Weather, water reflections, FX and vignette are cosmetic. Weather stays fixed to map coordinates and visible
  lit outdoor cells. Water stays smooth: fixed art/UVs, subtle light glints and undistorted mirrored scenery,
  bodies and flames, clipped by the authored water alpha and dry ground layers. Static scenery reflections
  persist in explored fog under memory lighting; bodies, animated flames and glints require live visibility.
  Mirrors follow presented feet/facing/lift, fade out toward their reflected tops, and exclude unexplored
  sources; glints obey light occlusion.
  Source art/editor preview remain static. `game.splashSteps`/`Fx.splash` follows visible ground
  footsteps in water, excluding idle bodies and melee bumps. Vignette draws under minimap/HUD.
- `gfx/pixel.zig` draws crisp FX shapes with smooth map motion. Missiles arrive at the existing impact
  time; electrical arcs, trails and light use cosmetic state. `Light.emit` lights terrain and body normals
  through a bounded, wall-occluded pool, never revealing memory or changing visibility. Night's darkest
  point is `day.DEAD_OF_NIGHT`, derived from the midpoint of sunset to sunrise; sky colours retain climate.

## Art workflow

- Follow `docs/TILE_ART_WORKFLOW.md` and maintain `docs/ART_PROVENANCE.md`: distinguish owner originals,
  assistant extensions, procedural placeholders and unverified legacy assets. Keep icons very basic.
  Preserve the owner's actual pixels, uneven outlines, native scale
  and authored layers; update canonical Aseprite sources and inspect connected tiles in game. Inspect later
  owner edits before regenerating extensions. Palette matching alone is not a faithful port.
- Regular walls use Desktop `regular-walls.aseprite`, `Layer 1`; cave/forest art is separate.
  `tools/tile_art/port_walls.lua` updates extensions; `export_walls.lua` writes the 47-cell runtime atlas
  (`assets/source/walls.aseprite`, `assets/walls.png`). Keep `look.WALL_MASKS` and `WALL_FACE_PX` aligned.
- Ground sources live on Desktop and in `assets/source/`; preserve `Draw here` and the material's named
  extensions layer. `port_ground.lua` records crops; `export_ground.lua` produces 16 dual-grid masks in
  64px cells. `name=shallows` reads `water.aseprite` into `shallows-ground.png`; `name=water` reads
  `deep-water.aseprite` into `water-ground.png`. The deep copy uses 60% RGB with identical shapes/alpha
  (`deepen_water.lua`); both retain `Water extensions`.
- Forest source is `assets/source/forest-tree-walls.aseprite`; preserve `Draw here`/`Forest extensions` in
  the Desktop source. `export_forest.lua` exports the art layers. Isolated shrubs mix `shrub.png` and forest
  cell 01 by stable position hash. `tone_forest.lua` records the darker foliage/grass palette; inspect
  existing tone and `assets/backup/` before applying it again.
- `build.zig` embeds top-level PNG/TTF/TXT files in `assets/` by filename (`@embedFile`,
  `@import("assets").names`), including controller mappings. Maps/saves still use the working directory.
  Register body/tile PNGs in `look.BODY_PNGS`/`TILE_PNGS`. Sprites are 64px, facing right; `Game.facing`
  mirrors leftward movement/strikes/aim and retains facing for vertical motion. `CELL` must be a whole
  multiple of 64, never fractional sprite scaling. Rebuild after installing assets.
