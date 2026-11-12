# Tile artwork workflow

Preserve owner pixels, native scale, authored layers and lighting direction.
[ART_PROVENANCE.md](ART_PROVENANCE.md) records attribution and derived work;
[HUD_LAYOUT.md](HUD_LAYOUT.md) covers HUD sources. Script parameters and sampling
algorithms live in `tools/tile_art/`.

## Editing and validation

1. Inspect the file the owner is actually editing and its layers. A layer named
   Draw here is not proof that it contains the paint. Back up before changes:
   use `%TEMP%/wall-mocks/`, except owner-requested forest/grass backups in
   `assets/backup/`.
2. Export paint alone and inspect it at native resolution and integer zoom.
   Preserve the original layer's pixels and position; extensions belong on their
   own editable layer. Synchronize the working file and canonical
   `assets/source/` copy deliberately.
3. Copy whole pieces, then painted strips/corners at native size. Translate by
   whole pixels; splice rather than stretch. Preserve uneven edge sequences,
   highlights and palette. Keep unavoidable hand repairs local and recorded.
   Do not use image generation, smoothing, antialiasing or rescaling. Rotation
   and mirroring must respect the painted lighting and face direction.
4. Export only intended art layers, excluding paper, labels, grids, guides and
   unused cells. Reopen the saved Aseprite and PNG; compare originals with backups
   and exports with the intended layers. Palette equality alone is not a shape test.
5. Inspect connected runs, corners, holes, ends, junctions and narrow passages.
   Check joined-edge cores separately from irregular exposed transparency.
6. Register runtime body/tile PNGs in `gfx/sprite_assets.zig`; filenames must be
   globally unique. Rebuild embedded assets and inspect actual headless captures
   from TEMP using [AGENTS.md](../AGENTS.md#verification). Finish with
   `build.cmd`; never launch interactive play to verify.

Export existing art directly after edits. Port/template generators reconstruct
derived work and must not overwrite later paint. Inspect their refusal checks and
take a fresh backup before using an installation or replacement option.

## Walls and forest

Walls use eight-neighbor masks: N=1, E=2, S=4, W=8, NE=16, SE=32, SW=64, NW=128.
A diagonal counts only when both adjacent cardinal neighbors exist, yielding
47 masks. `wall_masks.lua`, `sprite_assets.WALL_MASKS` and `grid.WallShape`
must agree. Runtime atlases are 512x384: eight 64px cells per row, final cell empty.

| Material | Editable source and export |
| --- | --- |
| Regular wall | Desktop `regular-walls.aseprite`, original `Layer 1`; `export_walls.lua` builds `assets/source/walls.aseprite` and `assets/walls/walls.png` |
| Forest | `assets/source/forest-tree-walls.aseprite`, `Draw here` plus `Forest extensions`; `export_forest.lua` writes `assets/walls/forest-tree-walls.png` |
| Cave/forest guides | Desktop `cave-walls.aseprite` / `forest-tree-walls.aseprite`; `guide_walls.lua` supplies guides, `idea_walls.lua` supplies hidden assistant ideas |

Regular-wall runtime cells fill the tile, unlike the thin cores in the Desktop
reference sheet. `export_walls.lua` samples original painted edges, cap details,
brick runs and face ends; `look.WALL_FACE_PX` must match the exporter's face height.
`port_walls.lua` also regenerates the Desktop extension. Both sample the original
layer, so incorporate later edits before regeneration.

Forest export preserves native canopy/trunk geometry and the separate extension.
`port_forest.lua` constructs connections from native canopy copies and refuses an
existing extension. `tone_forest.lua` records the owner-requested forest palette
change and grass darkening; do not apply transforms twice.
Connected shrubs use the forest atlas; isolated shrubs retain stable visual
variants without consuming gameplay RNG. Brick and shrub shape queries remain
separate for lighting. Inspect `forest.png` and relevant `shadows-*.png` captures.

## Ground transitions

Ground uses a dual grid: each 64px piece spans the corners of four map cells.
Masks are NW=1, NE=2, SW=4, SE=8 in `ground_corners.lua` / `ground.ORDER` order.
Each material overlays lower-ranked ground. Mask 15 is the wrapping fill;
mask 0 is empty. Templates are 512x320 with a 64px header and a 4x4 art block;
runtime exports crop that block to 256x256.

`export_ground.lua name=<material> source=<canonical-file>` exports visible
`Draw here` and the named extension layer in layer order, excluding guides.
Use explicit canonical sources to avoid accidentally exporting an older Desktop
copy. Optional `out=` selects output. `from=underdrawing` is a stand-in only and
requires an explicit output outside assets.

| Runtime material | Canonical source under `assets/source/` | Extension |
| --- | --- | --- |
| grass | `grass.aseprite` | Grass extensions |
| dirt | `dirt.aseprite` | Dirt extensions |
| shallows | `water.aseprite` | Water extensions |
| water | `deep-water.aseprite` | Water extensions |
| bridge | `bridge.aseprite` | Bridge extensions |

Outputs are `assets/ground/<material>-ground.png`. Without `source=`, the
exporter reads Desktop sources; water maps to deep-water and shallows to water.
An absent ground sheet retains existing tile artwork. Sheeted grounds draw above
unsheeted grounds, keeping `ground.Ground` order within each group; deep water
lies below shallows and bridges cover other sheeted ground.

`port_ground.lua name=grass|dirt|water` derives missing masks from owner paint.
It writes a TEMP draft by default; `install=yes` backs up and updates working
and canonical sources. Existing extensions and changed source pixel counts
block regeneration. Keep original cels and strokes crossing cell boundaries intact.
The port validates palette/alpha, empty mask 0, fill, corner cores and all 128
legal adjacent pairs; inspect its connected preview as well.

Deep water is derived by `deepen_water.lua` from the shallow sheet with a 60% RGB
transform, retaining alpha, geometry and positions. Export the existing deep
source for later edits rather than repeating the derivation.

Bridge's original `Draw here` remains hidden; `Bridge extensions` holds its
connected plank field. `port_bridge.lua` protects existing extensions through
`previous=<validated-source>` and exact image/position checks. The ground
exporter applies 70% RGB and lifts pure-black shadows to (42,33,25) on the PNG
only; editable sources keep their palette. Re-exporting must not compound tone.
Inspect `bridges.png` for runs, wide crossings and junctions.

`ground_sheet.lua` and `ground_labels.py` create new templates.
Replacement requires an unpainted Draw here layer and a backup. Generated
guides are never runtime artwork.

## Water cliff sources and export

The shallow and deep originals are separate canonical files. The owner painted
on layer 8, despite its duplicate reference-layer name; Draw here is blank.
Never replace the shallow source with the Desktop deep-only revision.

| Depth | Canonical source | Export layer |
| --- | --- | --- |
| Shallow | `assets/source/water-cliff-edge.aseprite` | Shallow cliff - half height |
| Deep | `assets/source/water-cliff-edge-deep.aseprite` | 8 |

`export_water_cliff.lua layer=<name-or-index> depth=shallow|deep source=<file>`
copies the three named 64px left/repeat/right slices to
`assets/water/shallows-cliff.png` or `water-cliff.png` (192x64).
It excludes references and compares reopened crop pixels. Derived
`*-cliff-cap.png` alpha masks fill above faces and taper outside ends;
`*-cliff-lip.txt` and `*-cliff-foot.txt` anchor cast/contact shadows.

`pinch_shallow_cliff.lua` created the shallow half-height layer from original
layer 8, which stays hidden and intact. Columns retain lip rows and horizontal
positions, with native-palette endpoint sampling. It also moved corresponding
border edits. Deep faces and reference strips remain unchanged. This is derived
owner art, not new painting.

The connected source `assets/source/water-cliff-connections.aseprite` contains
three 4x4 blocks in `ground.ORDER`: dirt/shallows, dirt/deep, shallows/deep.
Preserve `Owner flat border edits`, the separate
`Deep border extensions from shallow edits`, and hidden
`Before shallow pinch` layers. Desktop working copies and PNG previews must
stay synchronized with the canonical source.

`export_water_edges.lua source=<edited-PNG> original=<canonical-Aseprite>
root=<repo-with-trailing-slash> report=<TEMP-report>` compares edits against
original layers, excluding edit overlays. It emits `dirt-shallows-edges.png`,
`dirt-water-edges.png` and `shallows-water-edges.png`, plus
`shallows-water-cap.png`. Each sparse edge atlas has five 256px bands:
dry ground, shallow surface, deep surface, shallow face and deep face.
Unchanged pixels remain transparent. `water_cliff_materials.lua` owns material
classification and shallow-to-deep palette mapping; unknown colors stop export
and require an explicit material assignment.

`port_water_cliff_edits.lua` transfers changed shallow border pixels to the
deep block while preserving taller faces and all pixels outside that block.
Inspect `source`, `baseline`, `original`, `output`, `preview` and
`report` inputs before using it. Do not regenerate templates over these edits.

For new templates, `--shot-water-cliffs` exports three native game renders.
`water_cliff_connected.py <shot-folder>` prepares a TEMP Aseprite assembly;
replacement backs up existing outputs. `water_edge_template.py` supplies the
original six-piece paint kit and refuses painted replacement. Connected flat
edits require export/porting; they are not automatically loaded by the game.
Keep dimensions and tile positions fixed, and never bake lighting into art.

## Runtime joins and visual checks

`ground.Corners.waterCliffFor` selects known dry-north/wet-south and
shallow-north/deep-south banks. Unknown corners, bridges, lava, chasms and deep
water do not supply a dry bank. Faces retain native width and height, without
mirroring; caps sample aligned neighboring ground. Different depths retain
separate ends. Play and editor share the path.

Faces use terrain lighting and the water camera/depth fade without reflections;
shallow surface caps use the ordinary water shader. Lip and foot profiles control
bank shadows independently of terrain solidity and sight. Inspect
`--shot-water-cliffs` for straight/stepped shores, narrow pools, mixed grounds,
both depths, three-material joins and shadow toggles.

Water artwork keeps fixed pixels, alpha and texture coordinates. Reflections,
glints and visibility are runtime effects, not source paint.
Use water mirror/memory/step captures and `--bench` when changing those paths.
Rendering must not expose hidden live bodies or effects.

## Aseprite batch tooling

Use native Aseprite operations for layered pixel ports. On this machine:

```powershell
$aseprite = 'C:/Users/DavidBennett/Desktop/projects/Aseprite/src/build/bin/aseprite.exe'
$script = Join-Path (Get-Location) 'tools/tile_art/export_walls.lua'
$process = Start-Process -FilePath $aseprite -ArgumentList @('--batch', '--script', $script) -WindowStyle Hidden -PassThru -Wait
$process.ExitCode
```

Pass Lua parameters with `--script-param key=value` before `--script`.
Check exit status and the script's validation report. Keep backups, drafts,
previews and reports in TEMP. Rerun validation before citing an old report;
successful export alone does not verify connected artwork in the game.
