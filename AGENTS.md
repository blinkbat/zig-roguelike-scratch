# AGENTS.md — Cistern

Working title: **Cistern**. Grid roguelike in **Zig 0.14.1 + raylib**: archer, wizard and knight; rats, slimes, bloats, pyre bloats, frost wisps, pibs, beefy pibs, pib shamans,
bandit crossbowmen, netters and shieldbearers, bog leeches and mimics; breakable barrels, treasure chests, equipment, XP and class progression.
Art starts as glyphs, replaced by the owner's PNGs; a body without art draws its letter cell-high and bright over a drop shadow (`look.body`).
Source paths below are relative to `src/`; scripts, docs and assets are relative to the repository root.

## Working rules

- Prefer no comments in code. Ask before making product/design decisions. Don't commit, push or branch unless asked.
- `docs/ARCHITECTURE.md` maps runtime contracts to owners and representative tests, including skill and editor contribution recipes.
- Preserve unrelated work, including existing uncommitted changes. Keep verified workflow learnings succinct;
  update existing guidance instead of appending a diary.
- **No scratch files in the repo**, including `output/` and ignored `shots/`. Put backups, previews, mocks,
  reports, timing roots and throwaway scripts in `%TEMP%` or the session scratchpad. The owner's forest-art
  backups in `assets/backup/` are the sole backup exception. Normal build/cache directories remain in use.
- Windows/PowerShell: use `login: false`, read UTF-8, preserve UTF-8 without BOM, and prefer targeted patches.

## Build and verification

- `_zig.cmd` selects Zig 0.14.1 from `ZIG`, the existing sibling toolchain, or PATH, and checks its version.
  See `README.md` for fresh-machine setup. Run scripts from this directory:
  `./check.cmd` type-checks executable and tests without linking; `./test.cmd [filter]` runs tests;
  `./build.cmd` builds without launching. Use tests that print meaningful counts.
- `./build-linux.cmd` and `./build-macos.cmd` use Python 3.9+ to cross-check/build Linux x86-64 and macOS
  Apple Silicon/Intel, then package maps in `zig-out/releases/`. Linux dependencies cache outside the repo
  under `../.zigtoolchain/cistern-release/`; the pinned macOS SDK uses Zig's package cache.
  See `docs/RELEASE_BUILDS.md`; builds do not imply runtime verification. Never launch interactive play to test them.
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
  `tools/source_rules.zig` also checks runtime import boundaries: gameplay/map rules cannot depend on UI/rendering,
  and standalone editor helpers cannot depend on Editor/Game. Integration-test bodies may cross those boundaries.
  `core/wording.zig` owns display names, `core/text.zig` bounded text, and `play/log.zig` the event history drawn by `ui/journal.zig`.
- `game.zig` holds `Game`, the run/door/turn flow and `update`; `Game` coordinates input, `g.sim` and `g.pic`.
  `game/sim.zig`'s `Simulation` owns the authoritative run (level, pool, RNG, resources, progression, nodes, log) and hero queries;
  `game/presentation.zig`'s `Presentation` owns the picture (glides, facing, pictured bodies, owed blows, shots, `fx`, shown
  resources) and its scheduler, which reads `*const Simulation`. Graphics resources stay on `Game`. `save_data.zig` maps each saved
  field to its owner; `save_format.zig` and `save_values.zig` own portable parsing/conversion. `RECORDED_FINGERPRINT` pins the legacy reader. `src/game/` splits off `combat`
  (impact orchestration, harm ticks, foe turns), `attacks` (simulation-only rolls, hit/status resolution and outcomes),
  `rewards` (simulation-only death, loot, experience and witness fright, returning facts for presentation),
  `skills` (aiming, leaps, rushes, spells, flasks), `binds` (the skill picker),
  `glide` (body motion), `scene` (map drawing), `overlay` (skill bar, binds, orbs, inspect, tooltips),
  `character` (pause, Character, Nearby), `debug` (Pause > Debug, diagnostics, `Perf`), `shots` (headless captures, bench), `harness` (scripted play shared by
  tests and shots) and `tests/` (the game's integration tests by domain: skills, foes, world, loot, picture, menus, hero).
  `app.zig` opens the window around a `Game` (`withGame`) and owns the headless flags; `core/window.zig` owns fullscreen.
- `gfx/look.zig` keeps tile/body appearance and `Sprites`; `raster` holds raylib rect/blit/render-target helpers,
  `shaders` shader loading/uniforms/GLSL heads, `prompt_icon` input glyphs, `line_icons` skill, item and direction line art.
  `gfx/light.zig` coordinates light state and baking; `light_model` owns shading math and source types;
  `light_visibility` owns eased sight, memory and visibility sampling;
  `shadow` casts shadows, `light_gpu` owns shaders, textures, uploads and drawing, `light_tests` its tests.
  `map/atlas.zig` keeps the map graph; `atlas_text` reads/writes map files and their knobs, `listing` browses the maps folder.
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
- `--shot-ui` runs Character/HUD, loot and day/night level-up captures; use the same temporary-directory procedure as `--shot`.
- `--shot-editor` captures editor workspaces and text/modal states at 720p, 1080p and 1440p; use the same temporary-directory procedure.
- `--shot-debug` captures each Debug submenu at 720p and loot states, and verifies that the six additional
  lighting/water/weather switches change pixels and restore the exact frame when re-enabled.
- `--shot-trees` captures two-cell tree height, wall adjacency, smooth hero occlusion and front/behind depth;
  use the same temporary-directory procedure. Tall trees occupy only their bottom cell; unsaved fading
  uses a soft aperture around whichever drawn body (hero first, then visible foes) stands behind it, shared by scenery and gas, preserving the lower trunk.
  Dense sight-blocking grass (`reeds`) uses that same occlusion and depth ordering within its walkable cell; these captures cover it too.
- Inspect actual headless PNGs. Recursive map overviews use `shots/maps/<relative.map>/overview.png`, preserving folder and filename identity.
  `game/shots.zig`'s `shoot` and helpers define the coverage: abilities, editor,
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
  `input_bindings` owns contextual mappings and Desk shortcuts; `input_names` owns glyph names and marked captions.
  `core/input_repeat.zig` owns pure movement repeat and stick hysteresis; `State.update` names each polling stage.
  Mouse motion/buttons/wheel select keyboard/mouse hints; a stationary cursor never overrides controller navigation.
  `game/mouse.zig` owns map click routing and unsaved click-to-move state; UI panels consume map clicks.
  `docs/CONTROLLER.md` describes the scheme; current mappings/defaults live in `input`, `skillbar.Bar.of` and `progress.State.bar`.
  Keep skill lists and balance values in their source modules instead of duplicating them here.
- Always show input controls as glyphs, never as key/button names in prose. Use `prompt_icon.Prompt`,
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
  Pause's Debug menu groups Gameplay, Lighting, Effects, Display and Diagnostics in `game/debug.zig`.
  It exposes cosmetic lighting/shadow/water/weather switches, fullscreen, VSync/frame limits and active OpenGL
  renderer/build/framebuffer information. CPU timing excludes frame pacing and is not GPU timing.
  Smart aim retains a legal visible foe by unsaved `Game.target` identity, otherwise selects the nearest legal
  visible foe. Projectile directions move cell by cell; melee and rush directions suggest legal enemies with
  free-cell fallback. Leaps remain free-cell targeting.
  Automatic selection spends nothing; confirmation and explicit enemy clicks retain normal attack legality.
  Reveal shows terrain and minimap without changing gameplay sight or saved exploration; turning it off restores
  the normal view. Cosmetic effects default on. Debug settings are not saved.
- Inspect (`Mode.inspect`, R3 or I) walks visible, onscreen characters as well as the orbs, slots, shown
  statuses and event log (`overlay.spotsOf`, nearest along the way pushed). Every unit card shows only a name
  (title-case for foes, the hero's own name), pictured HP, then a divider and the presented tile with signed effects;
  hidden, unborn and departed bodies are excluded.
  Long cards scroll with page controls or the mouse wheel. Any back-out or the same button closes it; it spends no turn.
  In play/aim the same tooltip shows for the part under the mouse (`State.pointer`, `overlay.hovered`).
- Start / Menu / Options opens Character directly; Select / View opens the game menu. Keyboard Tab / Esc mirror them. Character opens equipment, the inventory list, stats, passives and class skills in `ui/book.zig`.
  Player-facing hand slots are Main hand (viewer-left) and Offhand (viewer-right).
  Life and mana flasks are items worn in their own Equipment slots, as PoE2's: a new run wears both, they never roll as loot,
  and only a worn flask drinks or refills; its charges stay in `Simulation.flasks` while it is off. Two-handers identify the occupied offhand. Menu accents share `look.UI_GOLD/UI_FOCUS`:
  muted gold, never bright yellow.
  Character/binding panels share `menu.Surface`: half-rate growth, capped at 1.25x,
  with 18px detail and 20px body text before scaling. Keep panels centered with margins.
  `play/items.zig` owns slot/requirement transactions; `play/progress.zig` owns XP, point pools and skill ranks;
  `ui/book.zig` owns navigation, `character_view` its read-only inputs/commands, `character_layout` shared
  geometry, `item_card` card rendering and `character_stats` the main/advanced sheets.
  `play/passives.zig` owns the radial passive graph and grants; `ui/trees.zig` draws both tree panels.
  Before changing either panel, read its maintained reference: `docs/DIABLO2_SKILL_TREE.md` for skills,
  `docs/POE2_PASSIVE_TREE.md` for passives. Keep those documents aligned with subsequent changes.
  Passives open zoomed in. The left stick browses on its actual bearing, the right stick pans, and
  D-pad up/down zooms. Keyboard navigation, shifted pan, zoom and overview mirror those actions;
  keep device reads in `input` and the control reference in `docs/CONTROLLER.md`.
  Passives lift the Soulslike three-arm, six-branch layout: small stat nodes, larger interest nodes,
  paired-stat bridges and six double-ring capstones. Use simple circles and lines, with no central hub,
  per-node labels or legends; selected grants appear in the sidebar. All three origins are available
  directly; the class origin is free and grants no bonus. Branches follow outward feeders;
  bridges work both ways. The same feeders must govern eligibility and drawn links.
  `Game.character` holds only unsaved navigation state; item/point actions are commands resolved by the game.
  Item actions and point allocation execute on one press; item changes spend one turn and keep Character open.
  Shoulders / Q and E change tabs; F1–F5 directly toggle Equipment, Inventory, Stats, Passives and Skills.
  Keyboard tab headers show their shortcut glyphs. Back closes Character directly. Skills owns binding. Point allocation is free.
  Bumping or interacting with a closed chest opens it for one turn, revealing its loot without a modal.
  Stepping onto a loose bag or stocked open chest opens its loot modal and spends the movement turn; bags remain walkable.
  Interact opens a sole bag/open chest's loot modal directly, or lists nearby containers/doors first when there is a choice (a door always lists).
  Ground gold without items is a coin drop, automatically collected when the hero steps onto it without an extra turn or modal. Gold with items shares one item bag; loot shows only the selected cell, with Take item, Take gold and Take all. Pickups in one loot visit are one action: `Game.looted` defers the turn to the loot's close (`character.settleLoot`);
  Take all collects gold and as many items as fit, leaving the rest. Gold needs no inventory space. Empty loot closes. A press while busy waits for `quiet` (`Queued.interact`)
  instead of queuing its button's skill. Item commands wait out door travel. Movement and browsing never collect gold from bags or chests.
  Foes roll gold more often than items; plain white items have no rolled modifiers and are more common than magic blues.
  `items.foeLoot`/`items.roll` own the rates and rolls; bags and gold appear when the foe's death is presented.
  See `docs/PROGRESSION.md` for rules and the inspected D2/PoE2 paperdoll references.
- `app.zig` owns title/game/editor transitions; the game requests `Game.exit`, and `Game.back` identifies
  its caller. New reads `atlas.START` (`maps/start.map`) fresh, falling back to a generated floor only
  when that default file is missing. Reject malformed maps and starts without open floor.
- New runs select class and name, then use a free save slot; refuse when all slots are occupied.
  Saved-run death deletes the slot and returns to title on restart input; unsaved play can restart.
  Editor play-tests use the archer and no save slot. `Simulation.unkillable` is a debug option, never saved.
  Use the hero's name in the log/death screen, never "you".
- `Game.screen` controls layout; fullscreen can change it at runtime. `ui/hud.zig` follows
  `docs/HUD_LAYOUT.md`: a centered 640px assembly, life/mana orbs, skill icons, cooldowns, an experience bar and ailments;
  minimap at top right, with a sun/moon time-of-day line under it. The map continues behind it, with `hud.COVER`
  allowing bottom rows to clear it. No live name label, counters, numeric clock or permanent control instructions. The persistent event log
  occupies the bottom-left gutter without a heading; newest entries append at the bottom, with text,
  background and border fading to 10% of their base opacity at the top. Follow `docs/DATA_PRESENTATION.md` for item cards,
  comparisons and stat wording: relevant properties only, explicit units, and effects before metrics.
- **HUD and UI never restate.** No stat, mechanic or fact the player can already see elsewhere or infer from
  context (no attribute/resistance dumps on tooltips, no "In the bag" on a bag's own panel, no reason line repeating
  a label), and no flavor text on items, skills or anywhere else.
- `gfx/font.zig` uses Source Sans 3 for compact text at 18px (`font.SMALL`) and below, Balthazar for display text and symbols.
  Native sizes use point-filtered atlases; scaled panels use the corresponding mipmapped face. It falls back to raylib's font in tests/load failure.
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
  `editor.zig` holds `Editor` and lifecycle; `interaction` routes Desk input, modal commands and canvas gestures
  with explicit viewport bounds and no Game access; `placement` owns brushes, placement legality, clipboard and paste preview.
  `preview.Scene` owns the derived level, preview foes and reachability/issues, reading a const map;
  `thumbnails.Thumbnails` owns graph texture generation, invalidation and lifetime. Notify them through editor change/history operations.
  `widgets` takes explicit `Controls`, font and screen values, with no `Editor` or `Game` access;
  `tool_catalog` owns tool/shape descriptions and checked help; `name_field` owns bounded naming/paste input.
  `panel` (node list, tools, palette, things,
  status), `knobs` (generator rows), `canvas` (map, cursor/paste ghost, graph), `modals` (modals, help, object
  viewer) and `tests` sit beside it in `src/edit/`.
- Objects > select a foe > Fight launches `map/spar.zig`'s arena using the app's separate map, with the
  normal editor-test archer and no save slot. Returning preserves the editor map, modal and undo history;
  death retry and Debug > Gameplay > Restart Map recreate the selected opponent. `--shot` includes the arena and character pages.
- Editor > Text uses `edit/text_catalog.zig` and `edit/text_panel.zig` to browse source wording, rewrite literals
  by feature, owner and field purpose, and assign separate author tags. Editor workspaces use 24px primary text,
  20px details and scrollable Tools/Nodes/Things/Generator panels. Source and tag conflict checks protect external edits; wording applies after rebuilding.
  Display aliases live in `assets/player-labels.txt`, attribution in root `text-tags.json`; enum/save identities stay fixed.
  Map names are references here and use the existing node Rename action. See `docs/TEXT_EDITOR.md`.
- `save.zig` freezes the whole run: map, visited/current nodes, actors, class/name, resources/statuses,
  RNG, log, skill bar, time, gold, inventory, progression and each node's ground drops. `core/wire.zig`
  encodes named fields and enum keys; `core/store.zig` owns versioned checksummed envelopes and atomic replacement.
  Convert on parse with safe defaults, preserving recoverable state; validate detached snapshots before mutating the game.
  Compatible raw saves migrate through `core/store_legacy.zig`; see `docs/SAVE_FORMAT.md` for required fields and evolution rules.
  Autosave snapshots on the frame and writes on a thread, only while
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
  Chests spawn closed; the first bump or Interact reveals their items and gold.
  Open chests remain walkable, showing `chest-item-bag.png` while items or gold remain and `chest-open.png` once empty;
  ground cells with items show one `item-bag.png`, including any gold in that cell; gold alone uses `small-coins.png` or `large-coins.png`, with no coin lights. Seen coins, bags, closed or stocked chests and barrels
  catch a very subtle diagonal shine (`look.shineSweep`), each cell at its own time. Attacks never open chests. Wilds' `loops` reconnects side paths;
  `rewards chests` rewards substantial branches, fills sparse maps with spaced chests in sheltered alcoves,
  and scatters barrels as minor gold rewards. The Strand enables both; rewards must preserve routes.
  Its swamp trees (`assets/swamp-tree.png`, standalone `swamp_tree` tiles) scatter on dirt
  within three cells of water/shallows. Scatter's `water_range = 0` leaves other maps unrestricted.
  A few glow plants (`glow_plant`, a pale blue `&` glyph and light) scatter on its grass as natural torches. Stepping into one
  (`Move.burst`, a spent turn) bursts it into healing gas (`gas.burst`, Brogue's bloodwort pod) and leaves its grass; `Light.uproot` drops its light.

## Combat and simulation

- `play/attrs.zig` owns Strength/Dexterity/Intelligence and what they derive: life, mana, heavy/light/spell
  damage, crit and dodge. Strength scales heavy weapons; Dexterity scales light weapons, regardless of range.
  `skillbar.Act.attack` selects melee/ranged/spell delivery; `items.Gear.scaling` selects the matching
  weapon's scaling for both live damage and previews. Wands and staves have no innate attack damage.
  Offhands include tomes, orbs, bucklers, shields and totems; two-handed weapons clear that slot.
  Item bases have fixed neutral innates, with rolled modifiers separate in magic blue or rare yellow. Every base rolls in all three rarities.
  Class bases feed passive allocations and equipped modifiers;
  `Simulation.heroAttrs` is the runtime source; `Simulation.heroPerks` combines equipment and passive recovery effects.
  Foe `Row.armour` reduces physical hits; crossbow penetration subtracts percentage points. Armour reduces physical bites before mana shield; elemental/status
  damage keeps its separate rules. Equipped weapons and skill ranks affect hero damage and its previews.
  Every hero blow goes through `attacks.scaled` (via `heroRoll`/`heroScaled`), which draws the crit after the
  damage roll, then rounds each part up as often as its fraction. Skill rolls are `damage.Base` (`Act.bases`); an area
  blow rolls its base once and scales, crits and rounds per foe. Skill tooltips show the scaled non-critical range.
- `play/hero.zig` maps class to body; `skillbar.kit` restricts bindings and `Bar.of` supplies defaults, both
  narrowed to learned skills by `progress.State.kit/bar`. `skillbar.Act` derives base costs, cooldowns,
  descriptions and targeting from each skill module; `progress.State.cost/cooldown` apply rank. Module
  descriptions say only what a skill does: `overlay.describe` appends mana, turn and cooldown at the hero's rank.
  Mana checks, spending, slot dimming, tooltips and descriptions must agree. Preserve resources/statuses across doors and saves.
- **Target previews and resolution share legality.** Projectile aiming accepts empty, dark and wall cells
  within range and geometric line of sight (`bow.aimable`, plus `Level.inLos` for the player's reticle).
  Visible targets are suggestions; projectile directions move freely by cell, and aiming opens without a target.
  `bow.fly` stops at the first collision even when the intercepted attack misses. Previews must not reveal
  hidden collisions. Spend nothing before confirmation.
  Area previews/damage/effects share geometry (each module's `burst`/`around`, `glacial.spread`, `cleave.arc`); use `fov.castInto` for
  terrain occlusion without changing sight or memory. Capture area targets before damage so newborn
  slime halves inherit statuses without being hit twice by that burst.
- Juke is the free leap (`juke.FREE`); Blink spends a turn. Leap cursors may cross invalid cells but
  confirm only visible vacant landings. Idle frames advance no simulation, mana recovery or cooldowns.
  Every consumable spends a turn. A flask drink recovers its first tick on that turn, before foes act, then on the next two spent turns.
  Bandage, Smelling salts and Frost vial (`play/consumable.zig`) are skill acts declaring `SUPPLY`: carried as `Inventory.stacks`,
  lying as `Ground.supplies` beside item drops, listed above bag items in Inventory and bindable like flasks.
  Drinking again restarts recovery; kills refill charges. Mana uses small whole numbers; natural recovery
  accumulates over spent turns in saved mana_recovery, never idle frames or free actions.
- `skillbar.SKILLS` owns each action's module, reticle and explicit attack delivery. `play/skill_contract.zig`
  interprets and validates capabilities once; `Act` metadata, execution and previews use that contract.
  A pin (`pinning.Pin`) holds a body to its cell on its
  turns, counting down like chill; it can still attack within its normal range and cannot be knocked back.
  A mana shield (`ward.Ward`) takes the hero's harm from mana first, in `Simulation.resolveDamage`; `Game.hurt`
  handles input consequences and Presentation defers the result. The orb shows that
  mana through `Presentation.mana_held` until the blow lands, as `flasks_shown` holds a kill's refill.
- **`Pool.damage` is the only HP-loss path**, apart from splitting a slime's remaining HP, restoring
  carried state and clamping to a lowered maximum (`syncStats`). Elemental resistance applies separately per element, rounding down, clamped to
  -100..100; physical damage bypasses elemental resistance (`play/damage.zig`) and uses armour separately.
- `Row.splits` splits a surviving slime below half HP, down to quarters. Each half gets half the remaining
  HP (minimum 1), with inherited statuses/clock; the new half acts next turn. If no adjacent cell is free,
  retry on a later blow. Pack quotas/makeups (`play/pack.zig`) and bespoke placement must reserve capacity
  for all eventual halves via `actor.roomFor`. `Kind.family` keeps their counts together.
- `Row.movement` and `Row.foe_type` describe every kind and appear in the object viewer; heroes have no
  foe type. Bloats fly; ground-only water footsteps must not be added to flying bodies.
- Bandit crossbowmen spawn with rats, retreat when crowded and use `bow.aimable`/`bow.fly` plus the
  player's base arrow damage/range. `Presentation.foe_shots` draws each arrow; its harm lands on arrival.
- `actor.dwells` is each kind's ground for packs, bespoke spawns and the editor (`Node.foeFits`); a pack whose lead has none
  is skipped. Bog leeches swim only in water (`actor.swim`), stay `submerged` beyond the hero's reach and are struck there.
  Mimics stand as a real chest tile (`under` keeps the ground) until opened (`Actor.unmask`), then drop chest loot.
  That chest draws `mimic-closed.png` (`Presentation.mimicAt`); the body is `mimic-open.png`.
  `Actor.veiled`/`seenIn` hide both from drawing, aiming (`bow.previewAmong`), inspection and targeting.
  Netters (`Row.net`) pin the hero: steps struggle in place, leaps and rushes are blocked. Shieldbearers knock the hero back
  (`Presentation.knocked_from`/`Owed.knock` draw it as the blow lands). Frost wisps' touch chills the hero; every third chilled
  action costs its next turn. Pyre bloats' burst (`rewards.pyre`) burns the bodies beside it. Pib shamans (`Row.mends`) heal
  the most hurt pib in reach or wake sleepers, keeping `Row.keeps` cells off the hero.
- Preserve Brogue's turn order: hero action and its harm, gas spread, then foes nearest the hero first,
  each followed by gas, healing gas, burn and bleed. Bloats burst however killed; foes do not enter gas or Fire Wall flames from outside them (`actor.shuns`).
  `map/gas.zig` alone advances gas; it spreads through open cells, including liquids. Caustic (`Level.gas`) and healing (`Level.healing`)
  gas are separate volumes (`grid.Gas`), spread alike; healing gas mends every hurt body a fifteenth of its life a turn, as caustic gas eats at it.
  `gfx/cloud.zig` draws both in one premultiplied texture; gas harm and heals shed `fx.Puff` wisps of their gas's colour as they land.
- `play/resilience.zig` owns separate stun/burn/bleed/chill/pin buildup for every body. Successful applications
  add resistance until expiry on spent turns; failed applications and free actions never extend or age it.
  `Simulation.takeStatus/procStatus` combine innate resistance, buildup and terrain before gating combat applications.
  Preserve buildup and bleed strength across splits, travel and saves; present resistance with the blow.
- `play/shock.zig`, `sunder.zig`, `blind.zig` and `confusion.zig` own afflictions that nothing applies yet. Each wears
  a turn on its body's own turn (`combat.wearTurn`; the hero's right after its action). Shock spends itself on the next
  damaging hit (`attacks.resolve`, foe bites and sweeps) for half again, rounded up. Sunder stacks lower armour in
  `Simulation.combatStatsAt`, which every armour read uses. Blindness limits sight to adjacent cells; a blinded foe acts
  only beside the hero. Confusion sends half of moves a random way that also spends the move (`actor.stumble`, `game.astray`).
- `play/terrain.zig` owns typed tile modifiers for hit, dodge, elemental and status resistance.
  `Simulation.combatStats/combatStatsAt` resolve them from base stats without mutating or saving bonuses.
  Combat, Character and inspection share this resolver; see `docs/TERRAIN.md`. Shoot is a fixed basic attack:
  it stays bindable and anchors the archer tree, but cannot consume points or gain rank scaling.
- Burn/bleed begin next turn; refreshing does not stack or postpone a due tick. Bleed doubles on movement,
  including hero leaps. Chill advances on enemy turns, preserving its act/act/skip cadence on refresh.
  A skipped action still takes gas/burn/bleed; waiting newborn halves process inherited status ticks
  without duplicating the parent's already-applied ticks.
- `play/clock.zig` is the one hidden action clock: `clock.TURN` ticks per turn, `Row.pace >= TURN` because
  presentation supports at most one action per foe per turn. Check chill before the stalled-action return.
  Use `Clock.delay`/`Clock.stun` for delays/stun, with no separate stun status or visible clock. A stunned hero
  loses its next turn on its own once the stunning turn is drawn (`stunnedTurn`, in play or Character).
  A foe's sweep (`Row.sweep_every`) strikes every body and barrel round it; its victims land with its blow on the hero (`Owed.swept`).
- A pib witnessing a nearby foe death wakes and flees (`FRIGHT_REACH`, `FLEE_TURNS`); subsequent deaths
  refresh it. Cornered beside the hero, it attacks. Fright speech waits for the death's presented impact
  and uses cosmetic RNG. This is the Frightened status (`Actor.fright`, resilience `.fright`); witness fright
  needs no roll, while War Cry rolls it against `Row.fright_resist` and buildup.
- `map/day.zig`'s `Simulation.clock` is simulation: saved whole minutes, advanced by spent turns on every
  node. `map/lume.zig` uses it for outdoor sight; `Presentation.hour_shown` only eases the rendered lighting and the minimap's sun/moon line.
- `map/fov.zig` owns line of sight; `map/lume.zig` owns visibility from light. `Level.los` is geometric
  sight; `Level.lit` additionally requires sky, torch or carried light. A `Tile.glows` tile lights a torch's
  pool from its own cell; `gfx/light.zig` hangs it as a plant-mounted `Torch`. Terrain is remembered; bodies are
  shown only where lit at their presented center. Rendering never decides visibility.

## Folk, triggers and dialog

- `map/script.zig` is the map's script (`Atlas.script`): named flags, counters and timers, folk (node, cell,
  name, dialog), dialogs of lines and choices, and StarCraft-style triggers. References are indices the script's
  own removals renumber or retire (`dropNode`, `dropFolk`, `dropDialog`, `dropLine`); a name or dialog still in
  use cannot go. `Script.valid` guards map parsing and portable loads. `map/script_text.zig` writes it after the
  nodes: names are tokens, prose is the rest of its line, references resolve once the whole file is read.
- Folk stand on open bespoke floor no foe, barrel or door holds (`Atlas.folkFits`); painting under one prunes it.
  `Atlas.stampFolk` marks them on `Level.folk` on entry and resume. They block steps and landings (`vacant`,
  `stepOk`) but are no target (`taken`): attacks, arrows and areas pass them by.
- `play/trigger.zig`'s `Runtime` (`Simulation.plot`) is looked at after each spent turn, on arrival and when a
  conversation closes, never on idle frames; a kept trigger runs at most once a turn. Every condition must hold;
  none never fires. Timers, `wait` and `elapsed` count spent turns; `deaths`/`alive` count a whole foe family.
- A `dialog` action holds its own list until that conversation is heard out; one at a time, opened once the turn
  is drawn (`talking.due`). Bumping a folk or Interact beside one opens its dialog without a turn, ahead of
  containers. No back-out: a conversation ends only through an ending, so `talked` means heard; a dialog no way
  through ends (`Dialog.ends`) never opens, and the editor lists it under Problems. A gate hides a
  choice; line actions land on arrival, choice actions on the pick. The HUD hides behind `ui/talk.zig`'s panel.
- Editor: the Folk tool places and removes folk and opens Dialog on one; Dialog edits folk, dialogs, lines and
  choices, Script the triggers and name tables. Words are typed into the map, one undo step per click; a
  condition or action kind that would name nothing is skipped or coins a name.

## Rendering contracts

- **The picture lags the mechanic.** Simulation never reads presentation. `Presentation.pictured`/`fx.After`
  apply each visible blow when it lands; HUD life and vignette use presented HP. Deaths, barrel removal,
  slime births, status markers and speech follow that timing. Event-log lines said while a turn resolves stay
  hidden (`Log.held`) until it is `quiet`. Foes turn/move at their stagger position.
  Level gains start a brief gold shaft, rising glints, a soft character glow with nearby golden light,
  and floating "Level up!" text when progression is presented;
  loading a run does not replay them. Update ongoing effects before starting new ones. `Presentation.busy` covers the slowest glide/projectile/flash;
  movement, skills and interactions pressed while busy are queued (`Game.pending`, the latest wins, but a repeating
  held walk never displaces a skill or interaction). Queued interactions survive door travel and open nearby after arrival.
  Skill activation/confirmation (including Wait/Shoot) requires `quiet`.
- `gfx/look.zig` owns pictures and `look.Assets` map residency. Load required textures before drawing,
  including later slime forms and delayed deaths; retain common textures/normals and unload unused map
  assets. `Game.art` records stale/play/editor residency intent; scene changes and title assets invalidate it,
  and each renderer prepares its set once. Title loads only the font; play graphics load lazily.
  HUD and bind picker share `line_icons.drawSkill`. Character rows and paperdoll cells draw `line_icons.drawItem`
  (a supply uses its skill's glyph); every `items.Kind` needs an `ITEM_LINES` entry.
- `gfx/ground.zig` owns real ground layers. `ground.bedAt` chooses the neighbours' majority underlay,
  lowest rank on ties, then `look.under`; rock covers its cell. Grounds without sheets draw below those
  with sheets, each group retaining rank order. `Corners.mask` includes higher layers; `Corners.under`
  fills beneath their receding edges. Preserve transparency and underlays; never substitute opaque
  cell fills beneath artwork. Play omits unseen cells and clips ground overhang to the map boundary;
  editor shows all.
- `gfx/light.zig` owns cosmetic light and fog. Draw ground/underlays, shadow mask, then standing tiles,
  so walls cover shadows. Terrain gets one 2x-modulate light-map pass, then only the additive fog pass.
  Body normals shade per pixel; motes/ground gas draw before lighting, flames/glow afterward.
  Gas also veils prop/body artwork at half its ground opacity (45% maximum), respecting sprite alpha
  and presented positions; brick and rock walls stay clear. This overlay does not change gas spread.
- Shadows/contact pools combine by channelwise `GL_MIN`, never stacking darker than the darkest source.
  `Light.onCaster` ignores fog: unseen/offscreen casters still cast when lit. Receiver visibility in the
  light-map alpha fades shadows, keeping unseen/remembered ground unchanged. Keep the `CAST_MARGIN` culling
  margin (from `shadow.CAST_REACH`) and presented actor position/birth/death. Bind the receiver light-map sampler after blend-mode
  changes, which flush raylib's auxiliary texture bindings.
- Floor ambient at memory RGB before adding lights, preventing a dark ring around the lantern. Memory
  fades into `look.FOG` dark gray at the unseen boundary; the minimap's panel is that gray at 70% (`look.MINI_BG`).
  Blur sight only over seen cells, and open-ground sight only over
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
  Source art/editor preview remain static. `Presentation.splashSteps`/`Fx.splash` follows visible ground
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
  (`deepen_water.lua`); both retain `Water extensions`. `port_bridge.lua` re-cuts the bridge planks into
  every cell of `Bridge extensions`, its `Draw here` kept but hidden, so only the extension exports.
- Forest source is `assets/source/forest-tree-walls.aseprite`; preserve `Draw here`/`Forest extensions` in
  the Desktop source. `export_forest.lua` exports the art layers. Isolated shrubs mix `shrub.png` and forest
  cell 01 by stable position hash. `tone_forest.lua` records the darker foliage/grass palette; inspect
  existing tone and `assets/backup/` before applying it again.
- `build.zig` embeds top-level PNG/TTF/TXT files in `assets/` by filename (`@embedFile`,
  `@import("assets").names`), including controller mappings. Maps/saves still use the working directory.
  Register body/tile PNGs in `look.BODY_PNGS`/`TILE_PNGS`. Sprites are 64px wide; tall scenery retains its native height. Bodies face right; `Presentation.facing`
  mirrors leftward movement/strikes/aim and retains facing for vertical motion. `CELL` must be a whole
  multiple of 64, never fractional sprite scaling. Rebuild after installing assets.
