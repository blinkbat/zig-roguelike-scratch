# AGENTS.md — roguelike-scratch

A grid roguelike in **Zig 0.14.1 + raylib**, built from `..\__archive\zig-grid-roguelike`'s foundation (grid, symmetric
FOV, room generator, input stepper) with every system stripped out. One archer, three foes (the rat and the tougher
slime, both melee, and Brogue's bloat, which flits and bursts into caustic gas) placed in packs by `play/pack.zig` (a `pack.Spec`: its makeups, drawn by weight, `pack.KINDS` by default; each kind's quota of `few` is filled first, from the makeups holding it; never more bodies than the pool holds once every slime has split to quarters), barrels that break for gold, no items, no stats beyond hp. Art is enlarged ASCII, replaced one PNG at a time as the owner makes them.

A blow that leaves a slime alive under half its hp splits it (`Pool.split`, `Row.splits`) into two half slimes, and
one that leaves either half under half its own splits that half into two quarters, so a slime ends as four; each is
on half what it split from had left (at least 1), the new one on a free cell beside it and acting from the next turn;
with no free cell it splits on a later blow. A slime's splits are of its `Kind.family` and count
as slimes.

Prefer no comments in code. Don't make product/design decisions — ask. Don't commit, push or branch unless asked.

## Build & verify

- `zig` is NOT on PATH. `check.cmd` (type-check, the error loop) · `build.cmd` · `run.cmd` · `test.cmd [filter]` ·
  `shot.cmd` (headless frames into `shots\lean.png`, `shots\aim.png`, `shots\torch.png`, a posed torch with rats
  under it, `shots\bind.png`, the bind screen with its picker open, and `shots\gas.png`, a room a few turns after a
  bloat burst in it, `shots\pause.png`, the pause menu over it, `shots\biome.png`, the archer arrived in `qud_salt_marsh`, `shots\dawn.png`, `noon.png`, `day.png`, `dusk.png` and `night.png`, the wilds at 7.00, 12.00, 16.30, 19.18 and 1.00, each
  world's start node rolled whole a glyph a cell into `shots\worlds\<name>.png`, and `shots\edit.png`, `shots\edit-graph.png` and
  `shots\edit-gen.png`, the editor's map, graph and a procgen node's generator on a posed three-node world, and `shots\name.png`, the hero's name being typed; built
  into `zig-out-dev` so a running game is untouched).
  `edit.cmd [path]` opens the world editor (`--edit`) on `worlds\main.world` or the `.world` named.
  `zig-out-dev\bin\roguelike.exe --bench` (after `shot.cmd` builds it) prints per-frame CPU time of a headless walk.
  The toolchain is named once, in `_zig.cmd`. From PowerShell, call them as `.\check.cmd` from this directory.
- **EVERY MODULE MUST BE NAMED IN `main.zig`'s `test {}` BLOCK** — `build.zig` panics otherwise,
  and on any `src/**/*.zig` under 512 bytes.
- Verify with tests that print the number. Do NOT launch the interactive window; the owner plays it.

## Laws

- **`core/input.zig` IS THE ONLY FILE THAT TOUCHES A DEVICE.** The controller is the primary input and the only
  one the UI names; the keyboard mirrors it. D-pad moves, LT held puts the d-pad on diagonals (`leanOf`). Skills sit
  on PoE2's controller skill bar (`play/skillbar.zig`): LB, A, X, Y, B, RB and RT are slots in a primary and a
  secondary set, the secondary set is used while the button bound to "Activate Secondary Skill Set" (LB) is held, and
  View opens the bind screen (A select or pick up, X change, Y remove, B close). Defaults: X Shoot, B Wait. The button
  that opened the reticle shoots, B cancels, A restarts after death (or, in a save slot, goes back to the title).
  Alt+Enter toggles borderless fullscreen. Menu (Esc) opens the pause menu; raylib's exit key is cleared
  (`input.claimKeys`), so Esc never closes the window. A field being typed in sets `State.typing`: the keys that type
  then type (`State.typed`, Backspace `rub`) and press no button nor walk. The editor is a desk tool: its mouse and
  keys are `input.Desk`, and it names them.
- **`app.zig` IS THE WAY BETWEEN THE TITLE, THE GAME AND THE EDITOR.** The title (`ui/menu.zig`, as the pause menu
  is): New picks a world, one of the `.world` files in `worlds\` (`atlas.Listing`, a long list scrolling with
  `menu.window`; one generated floor when there are none), then a hero's class (`play/hero.zig`; the archer alone so far) and has it named on a grid of keys the
  d-pad walks and the keyboard types into (`ui/naming.zig`), then plays the world read fresh from disk in
  the first free save slot (refused when all are taken); Load plays or deletes (Y, twice) a slot; Options toggles
  fullscreen and opens Debug (Unkillable: the hero keeps 1 hp whatever strikes it, `Game.unkillable`, never saved); Editor opens the editor; Quit quits. The hero's name is said in the log, the hud and the death screen,
  and nowhere "you". The pause menu resumes, restarts,
  goes back where the game came from (`Game.back`: the title, or the editor that play-tested it) or quits; the game
  only names the way out (`Game.exit`) and the app takes it. The window's close button closes the app, but for an
  editor with unsaved changes, which asks first.
- **A SAVE (`save.zig`) FREEZES THE WHOLE RUN**: the world it is played in, every node visited as it was left, the
  one being played as it stands, the rng, the log, the skill bar and the hour, as their bytes under a fingerprint of their
  types (`core/store.zig`), so a build whose types changed refuses it, and it is measured whole before any of it
  reaches the game. `save.SLOTS` (3) slots in `saves\`. A slot's run is written once a turn has changed it and the
  last write is `save.GAP_S` old (never mid-door), copied on the frame and written off it on a thread
  (`Autosave`), and once more as the run is left. Death ends it: the slot is deleted as the hero dies. A play-test
  has no slot. Tests never write a save file.
- **THE WORLD IS `world/atlas.zig`**: nodes, each bespoke (authored floor, walls, torches, barrels and foes) or
  procgen (a base biome and the features laid over it, `world/procgen.zig`), each with doors. A procgen node
  holds no seed, but holds its base's settings (`procgen.Floor`), its features' (`procgen.Feature`, `MAX_FEATURES`)
  and its foes' `pack.Spec` (packs,
  a few of each kind, makeups, reach, gap from the arrival, apart from each other); its floor is rolled round its doors each run, from the run's seed and the node (`game.rollOf`), so a world plays differently
  every time. A door links both ways to one door on any node (`Atlas.link`). `Node.stamp` builds a node's `Level`:
  procgen generates round its doors, tunnelling each into the floor; bespoke opens each door's cell. The world New picks is played when it loads, one
  generated floor when `worlds\` holds none, and New refuses one that will not parse or whose start has no open floor. Stepping onto a linked door takes the archer, once the turn is drawn, to the door it leads to
  (`atlas.landing` when that is taken), hp carried; a node left is kept as it was for the run, and death restarts
  the world. The file is text (`Atlas.write` / `parse`), strict, saved beside itself and renamed over. A node also
  keeps a name and its box's place on the editor's graph. Tests never write a world file.
- **THE EDITOR (`edit/editor.zig`) EDITS THE WORLD AND NOTHING ELSE READS IT.** A map of one node, a bespoke one drawn
  as it will play and a procgen one as its doors alone (`Node.sketch`; its floor is only rolled in play, from the
  settings on the panel's Generator tab), or a graph
  of every node, its floor, its doors and their links, the boxes
  dragged where the owner wants them. Every press is a gesture, and all a gesture changes is one undo
  (`Editor.gesture` then `bank` on its first change; whole-world snapshots, `UNDO_CAP` of them). Leaving, quitting,
  opening and New ask first when there are unsaved changes (`Editor.request`). Esc backs out one step at a time,
  the last out to the title. F5 plays the world from its start and F6 from the cursor, unsaved; F5, F6 or the
  pause menu comes back. The status line's crib names every key and gesture, and a button's tip shows as it is hovered.
- **NOTHING IS SPENT UNTIL THE SHOT IS CONFIRMED.** `bow.aimable` is both the reticle's legal cells and the
  shot's legality — one call, so the highlight cannot disagree with the resolver. Every cell the arrow crosses to a
  legal mark is in sight: a line slips past a wall's corner where sight does not.
- **THE LAYOUT READS `Game.screen`, NEVER A WINDOW CONSTANT**, because fullscreen changes it at runtime.
- **`gfx/look.zig` IS EVERY PICTURE.** A thing with a texture in `Sprites` draws it; the rest draw their glyph.
- **`gfx/light.zig` IS EVERY LIGHT, AND THE FOG IS PART OF IT.** Terrain draws at full brightness; one pass of the
  light map (2x modulate, so it can brighten) lights it, and nothing else tints terrain. Open ground, and the ground under
  anything solid, goes down first, then body shadows, then the solid tiles, so a wall covers any shadow that reaches it. Bodies are lit per pixel by their own
  shader from normals bevelled off their silhouette at load, faded as the ground under them is; torch flames and their
  glow draw over it all. The map
  composes the archer's carried light (after Brogue's miner's light), each torch (occluded by its own `fov.cast`)
  and the fog: sight and memory ease per cell, and memory fades to black exactly at the edge of what was ever seen,
  so no unseen cell is ever drawn. Ground in sight is never dimmed by a cell never seen (a side door the symmetric FOV
  skips): there the fade is only a rim, and sight blurs over seen cells alone. It is cosmetic: nothing in the
  simulation reads it, and it decides no visibility.
- **`world/day.zig` IS THE HOUR, AND IT IS SIMULATION**: `Game.clock`, whole minutes, moved on 6 a turn in `endTurn`
  (a day is 240 turns), on every node, saved with the run, starting at 8.30. No hud shows it. It decides how far the
  archer sees out of doors (`world/lume.zig`).
- **`gfx/sky.zig` IS THE DAY'S LIGHT**, zig-soulslike's `daynight.zig` seen from above, drawn from `Game.hour_shown`,
  which eases after the clock so the light never steps. The sun rises east, stands south at noon and sets west; the
  moon is its opposite, and the one light that casts (`sky.keyDir`) changes hands over the top in the dark, its
  altitude floored at 25 degrees so a shadow never outruns its caster by much. On the map its north-south lean is
  squashed (`sky.NORTH_SOUTH`), so shadows run mostly across the screen, and it stands no steeper than 50 degrees, so
  even at noon everything throws a shadow past its edge. Its sunrise and sunset keys are warmed to gold. Only a node
  open to the sky (`Node.outdoor`: the outdoor bases; bespoke and rooms nodes are under a roof) gets it: there
  `Light.sky` replaces the dark's ambient with the hour's, lights ground, wall tops and south faces by the key,
  shadows them by a march toward it over what stands in its way (`light.CASTERS`: walls, rock, fences and the rest),
  drifts soft cloud shadows over them in real time (`light.clouded`, off the light's own seconds), lights bodies from
  its side and dims the carried light out by day. A shadow is soft and takes 55% of the sky's light at most. Bodies,
  barrels and the standing tiles (`look.STANDING`: shrubs, tiny shrubs, boulders) cast from their own place as every
  light does: a silhouette, but a tree's (`look.canopied`) is its canopy's soft pool (`Light.drawCanopy`). Everything
  that blocks a step but a liquid casts one way or the other (asserted). Nothing in the simulation reads the light.
- **`gfx/fx.zig` IS EVERY BLOW'S AFTERMATH**, after zig-soulslike's and fainter: the struck body flashes toward
  `light.FLASH_RGB` (drawn by the body shader), a pinprick of light marks the contact, and the body's matter
  (`fx.matterOf`: blood, ooze, a bloat's purple ichor, a barrel's splinters) sprays along the blow and lies a moment as a stain. Motes draw
  before the light map, so it lights and fogs them. A blow lands when the picture reaches it: an arrow's as it
  arrives, a melee blow (a kick, a bite or slam, a bloat's burst) at the height of its bump, the striker lurching a
  third of a cell toward what it strikes and back (`Glide.bump`, `BUMP_S`), a foe's from its place in the stagger
  (`Game.bit`). Nothing in the simulation reads it.
- **`gfx/vignette.zig` IS THE ARCHER'S DANGER**: the view's edge reddens as a blow on the archer lands (its flash
  rising, so a bite and the gas's sting alike) and glows, throbbing, while its hp is under a third. Drawn over the
  world, under the minimap and hud. Nothing in the simulation reads it.
- **ART LIVES IN `assets/` AND IS EMBEDDED** (`build.zig` embeds every PNG and TTF there under its file name, read with
  `@embedFile`), so the exe runs from any directory. A body's PNG is a file in `assets/` and its entry in
  `look.BODY_PNGS`; a tile's is a file and its entry in `look.TILE_PNGS` (a wall's are cut from `walls.png`); the barrel's is a `Sprites` field in `Sprites.figures`, the sprites the body shader lights.
  Sprites are authored at `look.SPRITE_PX` (64), facing right; `Game.facing` mirrors a body
  whose last step, strike or aim went leftward, and straight up or down keeps it.
- **PROCGEN IS A BASE AND ITS FEATURES** (`world/procgen.zig`, after Qud's builder stacks): `roll` lays the base
  (`gen.around`'s rooms, or a `world/biome/*.zig` module's `shape`, its doors opened so features see them), then each
  feature (`world/feature/*.zig`'s `apply`) in order, on a stream salted apart so adding one leaves the base as it
  was; then seals the edge, opens the doors again, opens a clearing at the middle if no ground is open, joins every
  stretch of ground to the biggest by bending trails that bridge water, lava and chasms (`carve.connect`), and
  `settle`s (walls shaped afresh but a rooms' corner nothing changed round, a barrel or torch that no longer fits
  dropped, and any barrel that parts the ground, `carve.unbar`), all as the base's `carve.Palette` says. Rooms bare keep `gen.around` whole. Bases: rooms, open, wilds, caves, cavern (ADOM),
  strata (Qud's NoiseMap), labyrinth, hall (ADOM's Big Room, grove, graveyard), maze (Diablo II's DrlgMaze),
  topology (Path of Exile's graphs), terrain (Dwarf Fortress's fields and biome checks), keep, town, dunes, site
  (Qud's segmented WFC). Features: river (any band: water, lava, chasm, a rock cliff, with fords), lake (any blob),
  road, scatter (any tile on any tile, alone or clumped), border, buildings (decay makes ruins), farms, setpiece.
  `carve.zig` is their shared toolkit. Each `worlds\<game>_<place>.world` is one touchstone's example, written as
  text. A knob is a field of a base's or feature's `Params`: whole numbers, or an enum written by name. The outdoor
  bases (open, wilds, topology, terrain) strew lone tiny shrubs and boulders over their grass (`carve.Litter`, the
  `litter` knob), each where it closes no way.
- **A TILE IS ITS ROW IN `grid.TERRAIN`** (solid, blind, what lies under it, liquid), its letter in a world file or set piece `Tile.letter`, its picture its row in `look.TILES`
  (a symbol, its ASCII stand-in, colours, minimap). A shrub, boulder or fungus blocks sight and step, a grave or tiny
  shrub a step alone;
  each is lit as the ground and draws its ground under it; water, lava, a chasm and a fence
  block a step but not sight or an arrow; reeds and crop block sight but not a step. Only `.wall` is shaped.
- **A WALL'S SHAPE IS DECIDED BY THE GENERATOR** in `gen.around`, before the torches and barrels, or by `Node.stamp` for a bespoke node
  (`shapeWalls` alone), and stored in `Level.shape`:
  the four sides, the four outer corners, the four block corners, post, solid. Nothing recomputes it, and nothing about what has
  been revealed touches it (owner's call). `shapeWalls` classes every wall from the floor round it, then
  `outlineRoom` stamps each room's four corners over that — rooms here are ringed by corridors one cell out, so
  the neighbour rule alone reads a room's corners as straight walls. A corner with a doorway beside it or floor below
  it keeps the neighbour rule's shape. A wall draws a brick face exactly when floor lies below it: `top`, the bottom
  block corners and `post`; every other shape is ceiling only. A corner is named for where it sits on the room, so
  `corner_tl` has its floor to the south-east. `Sprites.wall` holds one texture per shape, cut from `walls.png`'s 64 px cells by `WALL_CELLS`; one with none draws `#`.
  The generator also hangs the torches (`Level.torch`), one on the `top` wall of `Params.torches` percent of rooms, after every layout roll
  so a seed's floor is unchanged by them, and then the barrels (`Level.barrel`): up to `Params.barrels` per room on its edge
  cells, never beside a way in, so no barrel seals a path. A barrel blocks a step and stops an arrow; one hit, shot
  or kicked, breaks it for gold. It has no hp. `bow.pick` aims at a barrel only when no foe is in reach. A seen
  barrel is drawn, lit as memory is when out of sight.
- **TEXT IS BALTHAZAR** (`assets/Balthazar-Regular.ttf`, OFL), drawn by `gfx/font.zig` from one mipmapped 96 px
  atlas as `zig-soulslike` draws it, so any size reads clean; hud text sits on a drop shadow. raylib's built-in font
  stands in only when the atlas fails to load, which is every test.
- **`CELL` IS A WHOLE MULTIPLE OF 64**, the sprites' authored size; they draw at `CELL / 64`, never fractional.
- **THE GRID IS y-DOWN** and **Chebyshev is the only metric**. **A diagonal may not cut a corner** (`passOk`).
- **`fov.cast` IS THE ONLY LINE OF SIGHT, AND `world/lume.zig` THE ONLY LIGHT THAT DECIDES WHAT IS SEEN.** The archer's
  pass (`lume.see`, from `Game.castSight`) keeps its line of sight, as far as its eyes reach (`Row.sight`), in
  `Level.los`, and of that leaves lit (`Level.lit`, and seen) only what is light enough: within the sky's reach
  (`lume.skyReach`: none under a roof or from an hour and a half past sunset to as long before sunrise, the archer's
  whole sight by day, `day.daylight` between), in a torch's pool (`lume.TORCH_REACH`, cast from the floor below its
  flame) or in the pool of a light a body carries (`Row.light`: the archer's 5; a foe's or a bonfire's alike). So
  underground and at midnight the archer sees what its own light and the torches show, and the bow reaches no
  further, for a mark and every cell to it must be lit. A foe sees the archer exactly when the archer's line of
  sight reaches the foe's cell and the archer is within the foe's sight: the archer carries a light. A body is drawn
  only where it is lit, judged at its middle as drawn; terrain is remembered. The picture's light (`gfx/light.zig`)
  matches it: the torch's reach is `lume.TORCH_REACH` and the drawn lantern fades out a cell past the archer's.
- **`Pool.damage` IS THE ONLY PLACE HP GOES DOWN**, but for `Pool.split` sharing a slime's hp
  between its halves and the archer carrying its hp through a door.
- **`world/gas.zig` IS EVERY GAS**, after Brogue CE's `updateVolumetricMedia` for one gas: `Level.gas` is Brogue's
  volume, spread twice a turn by each cell holding `gas.GASSED_UP` or more sharing it evenly over itself and its open
  neighbours (a thinner cell keeps its own), and a cell that held gas loses a unit on `gas.DISSIPATE` of passes, so gas
  shut in a room lingers and gas in the open clears sooner. A
  bloat (`Blow.burst`, Brogue's kamikaze) dies instead of striking and bursts into `gas.BURST` however it dies; a third
  of its moves go a random way (`actor.flit`). Brogue's turn order: the archer acts and the gas eats at it, the gas
  spreads, then each foe acts and the gas eats at it, a fifteenth of full hp. No foe steps from clean air into gas.
  `gfx/cloud.zig` draws it as Brogue tints it (30% plus a point a unit, 90% at most), eased in sight and remembered
  out of it, before the light map, through a shader that frays and churns it with drifting noise, and a burst's cloud
  from when the burst lands; its harm flashes a body (`fx.sting`) as the body arrives at its place in the stagger, or
  once the archer's step, kick or arrow is drawn for a body with none.
- **THE PICTURE LAGS THE MECHANIC.** The camera eases, bodies glide and hop (one walk repeat long), or slide a little past the cell and settle back (twice that), by
  their `look.gait` (`Glide`), the fog eases and the arrow flies after the hit has already resolved; nothing in the
  simulation reads the view. Foes act nearest the archer first (`Game.order`), and a turn is drawn in that order: the
  archer's step, kick or arrow, then each foe in sight, or stepping out of it, a `STAGGER_S` behind the one before, the
  first a `STAGGER_S` after the kick or arrow lands (`Game.lead`); a foe is drawn turning at its place. A body a blow
  kills, or a barrel, stands until the blow lands, its flash is gone and its last step is drawn. A body as drawn
  (`Game.pictured`: its kind, and its hp in bars, hud and vignette) takes each blow on it as that blow lands
  (`fx.After`, in the order they were dealt), and a slime split off one is drawn from when the blow that split it
  lands, sliding out of it. Each frame moves on what earlier frames set going before it deals anything new. A
  turn takes as long as its slowest glide, arrow or flash (`Game.busy`); a walk due before then waits for it, the latest
  standing in for any before.
- **EVERY DRAWN STRING IS ASCII**, but a tile's symbol: any codepoint Balthazar holds, baked into the font atlas by
  `look.TILE_CODEPOINTS`, its ASCII `ch` drawn instead where the font has no atlas.
