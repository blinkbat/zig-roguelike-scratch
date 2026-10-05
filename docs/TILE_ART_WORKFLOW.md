# Wall and repeating tile artwork

Extend the owner's pixel art by copying and manipulating the actual painted pieces. Preserve the uneven contours, pixel clusters, stroke thickness, palette and lighting. Apply this process to walls and other repeating terrain, recording each material's connection rules separately.

## Start from the editable source

1. Locate the file the owner is actually editing and inspect its layers. Do not assume the layer named "Draw here" contains the drawing.
2. Save a dated backup under the project's output directory before changing it.
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

The 47-cell authoring reference and the game's wall atlas have different layouts. The current game stores 14 `WallShape` values in `Level.shape`; `src/gfx/look.zig` maps them through `WALL_CELLS`. Do not substitute a 47-cell sheet for that atlas or change simulation geometry to accommodate an export.

Runtime `assets/walls.png` has 64-pixel cells in a 640 by 256 atlas. Its occupied positions are:

| Shape | Column, row | Brick face |
| --- | --- | --- |
| corner_tl | 0, 0 | No |
| top | 1, 0 | Yes |
| corner_tr | 2, 0 | No |
| left | 0, 1 | No |
| right | 2, 1 | No |
| corner_bl | 0, 2 | No |
| bottom | 1, 2 | No |
| corner_br | 2, 2 | No |
| block_tl | 5, 1 | No |
| block_tr | 6, 1 | No |
| block_bl | 5, 2 | Yes |
| block_br | 6, 2 | Yes |
| post | 8, 1 | Yes |
| solid | 9, 1 | No |

Room corners are named by their location in the room: `corner_tl` has floor to its southeast. A brick face occupies the bottom 11 pixels of a faced runtime tile. `look.WALL_FACE_PX` and the face lighting boundary in `src/gfx/light.zig` must agree with the exported pixels.

Regular wall work applies to `.wall`. Cave rock and forest artwork are separate and are deferred.

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

For each material, retain the canonical source path, painted layers, crop coordinates, connection mask order, runtime mapping, applied transforms, local repairs and validation results. Keep scripts beside the project and dated backups under `output/`, rather than filling the Desktop with competing "final" files.

The current regular-wall port is `tools/tile_art/port_walls.lua`. It replaces only the generated extension in the Desktop source, preserves `Layer 1`, and writes an editable runtime atlas to `assets/source/walls.aseprite`. It reopens that atlas and exports exactly those pixels to `assets/walls.png`. The desktop sheet is the 47-pattern authoring reference; the repository source is the exact 14-shape game atlas.

Before rerunning, inspect all layers for new owner edits and incorporate those into the source selection. The present script samples `Layer 1` and regenerates its extension and runtime output; it must not overwrite later edits to generated artwork without incorporating them.

From this repository in PowerShell:

```powershell
$aseprite = 'C:/Users/DavidBennett/Desktop/projects/Aseprite/src/build/bin/aseprite.exe'
$script = Join-Path (Get-Location) 'tools/tile_art/port_walls.lua'
$process = Start-Process -FilePath $aseprite -ArgumentList @('--batch', '--script', $script) -WindowStyle Hidden -PassThru -Wait
$process.ExitCode
```

The port copies horizontal outlines, vertical outlines, rounded corners, brick runs, face ends and complete 10 by 10 cap-detail patches. Plain interior space uses the sampled cap colour. Source strips repeat without scaling or rotation. Vertical strips share their endpoint sample so stacked tiles meet. Cell 02 had an empty first row at its north connection; the extension repairs this by copying its next row beneath the untouched original layer.

Validation artifacts live in `output/wall-mocks/`: `ported-pixel-validation.txt`, `regular-walls-current.png`, `walls-ported-room.png`, `ported-shots.log` and `ported-build.log`. The copied-edge pass passed the native pixel assertions, headless shots and normal executable build. The underlying wall mapping and lighting changes passed `check.cmd` and the full test suite before this asset-only correction. The room preview and actual `lean` and `torch` shots were inspected for visible seam gaps; that is not exhaustive coverage of every generated map.

Current correction notes: the generated approximation changed the drawing; resizing then distorted its pixel scale. A subsequent native-colour draft still replaced the uneven borders with straight lines. Neither palette matching nor native resolution alone is enough. Preserve the actual painted edge sequences and verify their joins.
