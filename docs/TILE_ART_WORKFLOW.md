# Wall and repeating tile artwork

Extend the owner's pixel art by copying and manipulating the actual painted pieces. Preserve the uneven contours, pixel clusters, stroke thickness, palette and lighting. Apply this process to walls and other repeating terrain, recording each material's connection rules separately.

## Start from the editable source

1. Locate the file the owner is actually editing and inspect its layers. Do not assume the layer named "Draw here" contains the drawing.
2. Save a dated backup to `%TEMP%\wall-mocks\` (Aseprite's `app.fs.tempPath`) before changing it, never into the repository; forest art is the owner's one exception (`assets/backup/`, below).
3. Export the painted layers alone and inspect them at native resolution and an integer zoom. Record the cell size, source rectangles and layer names.
4. Preserve the original painted layer and its position exactly. Put extensions on a separate editable layer. Update the original working Aseprite file so the owner sees the changes there.

For regular walls, the working file is `C:/Users/DavidBennett/Desktop/regular-walls.aseprite`. The original painting is on `Layer 1`; the first three cells contain the reference artwork. The canvas is 512 by 448 pixels, with a 64-pixel header and 64 by 64 cells.

Keep paper, faint underdrawing, labels and grid on separate layers. The grid belongs above the reference artwork; a drawing layer belongs above the grid. These aids must never enter a game export. Keep optional references faint or hidden once finished art replaces them.

## Copy before drawing

Prefer whole pieces, then cap patches, outline strips, corner patches and face strips. Copy at native pixel size and translate by whole pixels. Repeat or splice a strip to extend it; do not stretch it.

The slight bends in the owner's outlines are part of the artwork. Preserve where an edge steps by a pixel, how long each run lasts, and how highlights follow it. A sampled colour applied to a newly drawn straight line does not preserve that line.

Keep hand repairs local to a join that cannot be made from existing pixels, and record them. Do not introduce image generation, smoothing, antialiasing, palette conversion or rescaling to extrapolate this art. Nearest-neighbour enlargement is for inspection only.

Do not rotate or mirror a complete tile blindly. A wall's brick face stays south-facing and its highlights retain their lighting direction. Select the correctly oriented source edge before considering a transformed copy.

## Plan the connections

Write down what joins across each edge and what happens at each diagonal. A joined edge must reach its neighbour without a floor slit, doubled outline, stray endcap or internal front face. An exposed edge may retain intentional irregular transparency.

For an eight-neighbour blob set, use N=1, E=2, S=4, W=8, NE=16, SE=32, SW=64 and NW=128. A diagonal matters only when both adjacent cardinal neighbours exist. This yields 47 distinct connection masks. Give each mask one labelled cell; mark unused layout cells with an X. Similar-looking cells can encode different diagonal connections, so deduplicate by connection meaning as well as appearance.

Lay out connected examples as well as isolated tiles: long horizontal and vertical runs, convex and concave corners, ends, T junctions, crosses, solid blocks and one-cell passages. Check the seams at native scale.

For other terrain, establish its rules first: a ground texture may wrap on all four sides; a fence may use only cardinal connections; a shoreline may need diagonal transitions. Do not impose the wall template on every material.

## Regular wall source regions

Coordinates below are zero-based pixels in the original full sheet, including its header. Width and height describe a crop, not a scaling target. Recheck these regions if the owner edits the source.

| Piece | Source x, y | Width, height | Use |
| --- | --- | --- | --- |
| Isolated wall | 18, 83 | 26, 27 | Complete reference for cap, face and rounded ends |
| Uneven horizontal top | 160, 83 | 32, 6 | Extend top boundaries with the original stepped line |
| West cap edge | 83, 67 | 4, 30 | Extend left boundaries with their highlight |
| East cap edge | 105, 67 | 4, 30 | Extend right boundaries with their original thickness |
| Brick run | 154, 99 | 32, 11 | Extend front faces without changing brick height |
| West face end | 18, 99 | 4, 11 | Finish an exposed left end |
| East face end | 40, 99 | 4, 11 | Finish an exposed right end |
| Upper west corner | 18, 83 | 6, 6 | Join top and west contours |
| Upper east corner | 38, 83 | 6, 6 | Join top and east contours |

The reference uses seven opaque RGB colours: `(202,158,106)`, `(84,15,0)`, `(149,109,100)`, `(215,123,103)`, `(233,224,150)`, `(119,68,57)` and `(145,103,54)`. Palette equality checks colour preservation; it does not prove that shapes or lines match.

## Map the artwork to the game

`Level.shape` holds each wall's `grid.WallShape`, the mask of its eight neighbours that are walls (N 1, E 2, S 4, W 8, NE 16, SE 32, SW 64, NW 128; a diagonal only where both sides beside it are walls), one of 47. `src/gfx/look.zig` maps it through `WALL_MASKS`, in `tools/tile_art/wall_masks.lua`'s order, the same order as the Desktop sheet's 47 cells.

The Desktop sheet draws each shape as a thin core with arms; the game does not. Runtime `assets/walls.png` (512 by 384, eight cells to a row, the 48th empty) fills every cell, built by `tools/tile_art/export_walls.lua` from `Layer 1`'s painted strips the way the old 14-shape atlas was: the stepped top line, side edges and their corners on each side the wall does not join, a 2 by 4 notch at a north corner it does not, chips copied over the cap. Where it does not join south, its bottom 23 rows are the brick face: the cap's edge, the top mortar, six courses alternating rows 101 and 104 and the last course with its foot (107 to 109), ended by the face-end strips on an unjoined side. A face beside a missing south corner meets the next cap along a one-pixel outline, a hand repair. It writes `assets/source/walls.aseprite` with one slice per mask, and only reads the Desktop file. `look.WALL_FACE_PX` must match the face height.

Regular wall work applies to `.wall`. Cave rock and forest artwork have separate sources. Their Desktop sheets, `cave-walls.aseprite` and `forest-tree-walls.aseprite`, hold full-cell guides for the owner to paint over on `Draw here`, written by `tools/tile_art/guide_walls.lua` (`--script-param source=<sheet>`) with the runtime rules above: the underdrawing with the face, the exact connection guide without it. `tools/tile_art/idea_walls.lua` (`source=<sheet>`, `kind=cave|forest`) draws rough procedural ideas on the `Ideas - hide before export` layer, tiling across joined edges, and a connected preview in `%TEMP%\wall-mocks\<sheet>-ideas-preview.png`; it is inspiration, not art to ship. `deep-water.aseprite` on the Desktop is the same sheet, made from the cave sheet by `new_sheet.lua` with a header from `sheet_title.py`; a liquid's 10-row earth bank faces north instead (`guide_walls.lua` with `face=north rows=10`, `idea_walls.lua` with `kind=water|deep rows=10`). `water.aseprite` was that sheet too, unpainted; it is now a ground template (below), the old one backed up in `%TEMP%\wall-mocks\`.

## Ground transitions

Ground terrain is drawn on a dual grid: each 64x64 piece sits where four map cells meet, and one terrain's pieces lie over the ground ranked below it, so every terrain needs only its own 16 pieces, never one set per pair. The Desktop's `grass.aseprite`, `cobble.aseprite`, `dirt.aseprite` and `water.aseprite` are the templates: 512 by 320, a 64-pixel header, the 16 cells in a 4x4 block in `tools/tile_art/ground_corners.lua`'s order, labelled by mask (NW 1, NE 2, SW 4, SE 8). Neighbouring cells share their corners, so the block paints as one picture; 15 is the plain fill and wraps on all four sides, and 0 (X) is unused. Layers as the wall sheets': paper, `Underdrawing (25%)` with this terrain's quarters shaded, labels, grid, then `Draw here`, initially empty. One slice per cell, `Corners <mask>`.

`tools/tile_art/ground_sheet.lua` (`out=`, `labels=` from `ground_labels.py`, `tint=r,g,b`) writes one, reading the paper and grid colours from `cave-walls.aseprite`. It refuses an existing sheet unless `replace=yes`, and then only when its `Draw here` is unpainted, saving a backup to `%TEMP%\wall-mocks\` first. It checks that shared corners agree, the masks are distinct and each cell's shaded quarters match its mask, then reopens the saved sheet and writes `<name>-ground-template.png` and `.txt` beside the backups.

`export_ground.lua` (`name=grass|cobble|dirt|water`, optional `source=`, `out=`) exports `Draw here` and the material's named extension layer, such as `Grass extensions`, in layer order. It crops the art block to 256x256, excluding paper, labels, grid and underdrawing, and verifies the reopened PNG. Runtime `gfx/ground.zig` uses the same mask order; `gfx/look.zig` loads available `<name>-ground.png` sheets on demand for the map. Grounds stack water, dirt, grass, cobble. An absent sheet retains the existing tile artwork. `from=underdrawing` is a stand-in export requiring an explicit `out=` outside assets.

### Grass source and extension

The working file is `C:/Users/DavidBennett/Desktop/grass.aseprite`; its installed copy is `assets/source/grass.aseprite`. The owner's `Draw here` cel is 129x160 at (0,63), with 9,375 opaque pixels in six colours. Keep that image and position unchanged, including its painted pixel row above the art block. `Grass extensions` sits beneath it; the underdrawing is retained but hidden. The completed sheet has 15 painted cells and a transparent mask 0.

`port_ground.lua name=grass` keeps complete source cells 9, 12 and 15 as painted. Its repeated fill comes from (64,128), 64x64. The NW and SE outer corners are isolated connected pieces of cell 9 at (0,64); the NE corner comes from the painted part of cell 6 at (0,192), 64x64. It copies the north boundary from cell 12's rows 16..44, the south boundary from source x 0..23 / y 86..104, the east boundary from x 20..40 / y 64..87, and the west boundary from x 24..46 / y 98..121. All coordinates are inclusive source pixels where ranges are given. Repeated edge strips retain their original contours and highlights; the missing SW corner intersects the north and east strips. No scaling, rotation, mirroring, recolouring, smoothing or new outline drawing.

The port defaults to a draft in `%TEMP%/wall-mocks/`; `work=` can choose a session directory there. `install=yes` saves a dated byte-for-byte backup there, updates the Desktop file and copies it into `assets/source/`. It refuses an existing `Grass extensions` layer or a changed source pixel count: inspect and incorporate later owner edits before regenerating. Normal future art edits should be exported directly, not regenerated: run `export_ground.lua` with `name=grass source=<canonical Aseprite path>`, producing `assets/grass-ground.png`, and synchronize the working and installed source copies deliberately.

Validation reopens the saved source to compare the original cel and extension, checks the six-colour palette, opaque/clear alpha, every mask's corner cores, the fully opaque fill, the empty unused cell and the edge cores of all 128 legal adjacent pairs. `grass-connected.png` in the TEMP work directory shows solid patches, holes, corners, isolated cells, diagonal contacts and narrow strips; inspect it and the actual headless game frames. Irregular exposed borders are intentional, so edge-core checks do not require identical exposed silhouettes at every seam.

### Dirt source and extension

The working file is `C:/Users/DavidBennett/Desktop/dirt.aseprite`; its installed copy is `assets/source/dirt.aseprite`. The owner painted this dirt version in `grass.aseprite` by mistake. Its `Draw here` cel was transferred unchanged into the dirt template, retaining dirt's own labels and guides, and the finished green grass source was restored to the Desktop. The dirt original is 129x130 at (0,63), with 8,314 opaque pixels in three RGB colours: `(128,115,84)`, `(97,73,68)` and `(189,166,107)`. It remains above a separate `Dirt extensions` layer.

`port_ground.lua name=dirt` uses dirt's own pixels in the same source regions as grass, except its west strip is y 101..124 to avoid sampling the north outline. Dirt has no painted NE outer corner: intersect its west and south strips there; its SW corner intersects north and east. Cells 9, 12 and 15 remain exact. The shared port's `art=<Aseprite path>` imports `Draw here` from another sheet only into an unpainted destination; `source=` selects that destination, otherwise Desktop `<name>.aseprite`. Both files receive dated byte-for-byte TEMP backups before installation. Existing extension layers and changed source pixel counts refuse regeneration.

Export `name=dirt source=<canonical Aseprite path>` with `export_ground.lua` to produce `assets/dirt-ground.png`, 256x256 in the same 16-mask order. The reopened source and runtime PNG are verified against the original painting and reviewed atlas, and the same 128 legal adjacent pairs are checked. Connected dirt patches and grass over dirt are inspected separately: grass is the higher ground layer. Backups, drafts, combined art previews and headless map studies stay in TEMP. Regenerating grass from its original backup with the shared port produced the identical installed PNG.

## Forest walls

The owner's `Desktop/forest-tree-walls.aseprite` and its game source `assets/source/forest-tree-walls.aseprite` contain the `Draw here` cell and a separate `Forest extensions` layer. Forest backups use `assets/backup/`, as requested by the owner; previews and reports remain in `%TEMP%/wall-mocks/`. The original geometry and position are unchanged; the owner subsequently requested the darker palette below. Guides and ideas are retained but hidden.

`port_forest.lua` copies the original 64x64 cell at sheet (0,64), with its canopy cropped to the top 50 rows. Copies translated by 32 pixels bridge each joined edge and diagonal, layered north-to-south then west-to-east. Trunks remain on south-exposed cells; vertical bridges use canopy alone. No scaling, mirroring, rotation, recolouring or hand-drawn repairs. It checks all 47 distinct masks, palette membership and connected edge cores, then reopens the saved sheet to verify the original layer and extension. Its default output is a draft in TEMP; `install=yes` updates the Desktop source and its `assets/source/` copy. It refuses an existing extension layer so later owner edits cannot be overwritten blindly.

`export_forest.lua` reads `assets/source/forest-tree-walls.aseprite` and exports only `Draw here` and `Forest extensions` into `assets/forest-tree-walls.png`: 512x384, the shared 47-mask order, final cell empty. Reopened PNG pixels must equal those layers. Edit the source and rerun this exporter to retain later hand repairs.

`gen.shapeWalls` stamps `.shrub` connections separately from `.wall` into `Level.shape`. `Level.tileShape` supplies either material; `Level.wallShape` remains brick-wall-only for torches and lighting. Missing forest shapes in older saves are filled once on resume, including visited nodes. Connected shrubs use the forest atlas. Isolated shrubs retain `shrub.png` for about two thirds of positions and use forest cell 01 elsewhere, selected by a stable position hash without consuming the run's RNG. Both block movement and sight. The forest atlas casts a continuous swept footprint with a nine-pixel blur radius and reduced contrast (alpha gain 1.3, capped at 0.75); lone trees retain their soft canopy pool. Joined shadow edges extend their boundary alpha, and torch projection uses each vertex's world position, so adjacent tiles share the same projected edge. Sun and moon use parallel projection. The existing Darken mask prevents overlap from accumulating darkness. Terrain sun shadows remove at most 45% of sky light and soften over 70% of their caster's height.

At the owner's request, `tone_forest.lua` lowered the forest foliage palette in both editable sources, leaving trunks and alpha unchanged: `(107,185,112)` to `(82,143,86)`, `(158,215,106)` to `(122,166,82)`, `(56,92,59)` to `(45,74,47)`, and `(27,66,30)` to `(23,55,25)`. The shared `grass.png` RGB values were reduced 15%, rounded to the nearest integer. Before-tone source and PNG backups are in `assets/backup/`; the script refuses to apply again when the original forest palette is absent. Brightness comes from the existing lighting pass, without a new draw-time tint.

`shot.cmd` includes `shots/forest.png` and `shadows-morning.png`, `shadows-noon.png`, `shadows-evening.png`, `shadows-moon.png`, `shadows-torch.png`. The shadow studies expose the whole posed floor to compare walls, rock, forest, trees, small plants, boulders, fungus, barrels and actors. The sky's maximum casting altitude is 42 degrees, giving noon shadows 1.11 sprite heights so they extend beyond upright artwork. The full test suite and focused shadow tests passed; 136 shared forest edge samples agree under three torch positions and sky projection. Connected artwork and the headless lighting frames were inspected; the normal executable was rebuilt with the installed PNGs.

Shadow casters use the actual light at their position without fog or memory fading; unseen props, barrels and actors remain eligible. The mask is faded by visibility where it lands, using the light map's alpha. The camera margin includes the silhouette and blur, and actor birth/death timing remains shared with the visible presentation. `shadows-hidden-sun.png`, `shadows-hidden-moon.png`, `shadows-hidden-torch.png` and `shadows-offscreen.png` exercise these boundaries. Their GPU checks count contributions from each hidden caster and require zero shadow in unseen or fully remembered ground. Bind the receiver shader's light-map sampler after changing blend mode: raylib flushes and clears auxiliary texture bindings on a blend change.

## Validate the saved result

1. Reopen the saved Aseprite file. Compare the original painted layer's image and position with the backup, and verify that the extension is in the file the owner uses.
2. Compare exported art with the intended visible art layers. Exclude grid, text, paper, guides and the unused X. Verify 64-pixel cells and the complete runtime mapping.
3. Check alpha and colour values. Check connected edge coverage separately from exposed contours; forcing every tile opaque can destroy intentional uneven edges.
4. Inspect repeated pieces together. Look for floor slits, outline discontinuities, doubled seams, clipped brick courses and misplaced faces. A count of exported tiles is not a seam test.
5. Run the relevant project checks. Use `.\check.cmd` and `.\test.cmd` when code changes. Use `.\shot.cmd` for actual headless game frames and inspect `shots/lean.png`, `shots/torch.png` and relevant world shots.
6. Run `.\build.cmd` after final assets are installed: PNGs are embedded in the executable. A correct source PNG does not update an already-built game. Do not launch the interactive game for verification.

Inspect both the unlit artwork and the lit game. Lighting can conceal a gap or make a correct outline appear different. Keep final previews beside validation reports so a later pass can distinguish an inspected result from an unfinished draft.

## Repeatable tooling and notes

Use Aseprite's native image and layer operations for pixel ports. The installed executable is `C:/Users/DavidBennett/Desktop/projects/Aseprite/src/build/bin/aseprite.exe`. On this machine, invoke a batch Lua script through PowerShell `Start-Process -WindowStyle Hidden -PassThru -Wait`; record its exit code and have the script write an explicit validation report.

For each material, retain the canonical source path, painted layers, crop coordinates, connection mask order, runtime mapping, applied transforms, local repairs and validation results. Keep scripts beside the project and dated backups, previews and reports in `%TEMP%\wall-mocks\`, never in the repository and never on the Desktop as competing "final" files.

The current regular-wall port is `tools/tile_art/port_walls.lua`. It replaces only the generated extension in the Desktop source, preserves `Layer 1`, then runs `export_walls.lua`, which builds the 47 full cells into `assets/source/walls.aseprite` and `assets/walls.png`. To rebuild them alone, without touching the Desktop sheet, run `export_walls.lua`.

Before rerunning, inspect all layers for new owner edits and incorporate those into the source selection. The present script samples `Layer 1` and regenerates its extension and runtime output; it must not overwrite later edits to generated artwork without incorporating them.

From this repository in PowerShell:

```powershell
$aseprite = 'C:/Users/DavidBennett/Desktop/projects/Aseprite/src/build/bin/aseprite.exe'
$script = Join-Path (Get-Location) 'tools/tile_art/port_walls.lua'
$process = Start-Process -FilePath $aseprite -ArgumentList @('--batch', '--script', $script) -WindowStyle Hidden -PassThru -Wait
$process.ExitCode
```

The port copies horizontal outlines, vertical outlines, rounded corners, brick runs, face ends and complete 10 by 10 cap-detail patches. Plain interior space uses the sampled cap colour. Source strips repeat without scaling or rotation. Vertical strips share their endpoint sample so stacked tiles meet. Cell 02 had an empty first row at its north connection; the extension repairs this by copying its next row beneath the untouched original layer.

Validation artifacts go to `%TEMP%\wall-mocks\`. `port_walls.lua` writes `ported-pixel-validation.txt` there; the committed copy in `output/wall-mocks/` predates the 47-shape export and still describes the old 14-shape atlas, so rerun the port before citing it. `export_walls.lua` asserts its own palette, alpha, connection coverage and distinct cells, and `look.zig`'s tests check `WALL_MASKS` and `WALL_FACE_PX` against `wall_masks.lua` and `export_walls.lua`'s `FACE`. Inspecting shots for seam gaps is not exhaustive coverage of every generated map.

Current correction notes: the generated approximation changed the drawing; resizing then distorted its pixel scale. A subsequent native-colour draft still replaced the uneven borders with straight lines. Neither palette matching nor native resolution alone is enough. Preserve the actual painted edge sequences and verify their joins.
