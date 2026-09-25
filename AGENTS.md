# AGENTS.md — roguelike-scratch

A grid roguelike in **Zig 0.14.1 + raylib**, built from `..\zig-grid-roguelike`'s foundation (grid, symmetric
FOV, room generator, input stepper) with every system stripped out. One archer, one foe (the rat), no items, no
stats beyond hp. Art is enlarged ASCII, replaced one PNG at a time as the owner makes them.

Prefer no comments in code. Don't make product/design decisions — ask. Don't commit, push or branch unless asked.

## Build & verify

- `zig` is NOT on PATH. `check.cmd` (type-check, the error loop) · `build.cmd` · `run.cmd` · `test.cmd [filter]` ·
  `shot.cmd` (headless frames into `shots\lean.png`, `shots\aim.png` and `shots\torch.png`, a posed torch with rats
  under it; built into `zig-out-dev` so a running game is untouched).
  `zig-out-dev\bin\roguelike.exe --bench` (after `shot.cmd` builds it) prints per-frame CPU time of a headless walk.
  The toolchain is named once, in `_zig.cmd`. From PowerShell, call them as `.\check.cmd` from this directory.
- **EVERY MODULE CARRYING TESTS MUST BE NAMED IN `main.zig`'s `test {}` BLOCK** — `build.zig` panics otherwise,
  and on any `src/**/*.zig` under 512 bytes.
- Verify with tests that print the number. Do NOT launch the interactive window; the owner plays it.

## Laws

- **`core/input.zig` IS THE ONLY FILE THAT TOUCHES A DEVICE.** The controller is the primary input and the only
  one the UI names; the keyboard mirrors it. D-pad moves, LB held puts the d-pad on diagonals (`leanOf`), X aims
  and X again shoots, B waits or cancels, A restarts after death. Alt+Enter toggles borderless fullscreen.
- **NOTHING IS SPENT UNTIL THE SHOT IS CONFIRMED.** `bow.aimable` is both the reticle's legal cells and the
  shot's legality — one call, so the highlight cannot disagree with the resolver.
- **THE LAYOUT READS `Game.screen`, NEVER A WINDOW CONSTANT**, because fullscreen changes it at runtime.
- **`gfx/look.zig` IS EVERY PICTURE.** A thing with a texture in `Sprites` draws it; the rest draw their glyph.
- **`gfx/light.zig` IS EVERY LIGHT, AND THE FOG IS PART OF IT.** Terrain draws at full brightness; one pass of the
  light map (2x modulate, so it can brighten) lights it, and nothing else tints terrain. Floors go down first, then
  body shadows, then walls, so a wall covers any shadow that reaches it. Bodies are lit per pixel by their own
  shader from normals bevelled off their silhouette at load; torch flames and their glow draw over it all. The map
  composes the archer's carried light (after Brogue's miner's light), each torch (occluded by its own `fov.cast`)
  and the fog: sight and memory ease per cell, and memory fades to black exactly at the edge of what was ever seen,
  so no unseen cell is ever drawn. It is cosmetic: nothing in the simulation reads it, and it decides no visibility.
- **ART LIVES IN `assets/` AND IS EMBEDDED** (`build.zig` embeds every PNG there under its file name, read with
  `@embedFile`), so the exe runs from any directory. A body's PNG is a file in `assets/` and its entry in
  `look.BODY_PNGS`; a tile's is a file, a field in `Sprites` that `load` and `unload` name, and its arm in
  `Sprites.tileAt`. Sprites are authored at `look.SPRITE_PX` (64), facing right; `Game.facing` mirrors a body
  whose last step, strike or aim went leftward, and straight up or down keeps it.
- **A WALL'S SHAPE IS DECIDED BY THE GENERATOR** at the end of `gen.build` and stored in `Level.shape`:
  the four sides, the four outer corners, the four block corners, post, solid. Nothing recomputes it, and nothing about what has
  been revealed touches it (owner's call). `shapeWalls` classes every wall from the floor round it, then
  `outlineRoom` stamps each room's four corners over that — rooms here are ringed by corridors one cell out, so
  the neighbour rule alone reads a room's corners as straight walls. A corner with a doorway beside it or floor below
  it keeps the neighbour rule's shape. A wall draws a brick face exactly when floor lies below it: `top`, the bottom
  block corners and `post`; every other shape is ceiling only. A corner is named for where it sits on the room, so
  `corner_tl` has its floor to the south-east. `Sprites.wall` holds one texture per shape, cut from `walls.png`'s 64 px cells by `WALL_CELLS`; one with none draws `#`.
  The generator also hangs the torches (`Level.torch`), one on the `top` wall of most rooms, after every layout roll
  so a seed's floor is unchanged by them.
- **raylib's built-in font is 10 px; draw it only at whole multiples** (`GLYPH` 60 in a 64 px `CELL`, `TEXT`
  20) or it resamples.
- **`CELL` IS A WHOLE MULTIPLE OF 64**, the sprites' authored size; they draw at `CELL / 64`, never fractional.
- **THE GRID IS y-DOWN** and **Chebyshev is the only metric**. **A diagonal may not cut a corner** (`passOk`).
- **`fov.cast` IS THE ONLY VISIBILITY COMPUTATION.** A rat sees the archer exactly when the archer's pass lit the
  rat's cell. A body is drawn only where it is lit; terrain is remembered.
- **`Pool.damage` IS THE ONLY PLACE HP GOES DOWN.**
- **THE PICTURE LAGS THE MECHANIC.** The camera eases, bodies glide (`Glide`, one walk repeat long), the fog eases
  and the arrow flies after the hit has already resolved; nothing in the simulation reads the view.
- **EVERY DRAWN STRING IS ASCII.**
