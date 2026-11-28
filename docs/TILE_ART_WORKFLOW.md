# Tile artwork workflow

1. Inspect the owner's working Aseprite file and identify the actual paint cel. Back up before editing. Use `%TEMP%/wall-mocks/` for working files and `assets/backup/` for owner-requested forest and grass backups.
2. Preserve native pixels, cel positions, editable layers, palette and light direction. Copy whole pieces or translate painted strips and corners by integer pixels. Keep extensions on separate layers and record local repairs. Avoid generated pixels, smoothing and rescaling.
3. Export only intended layers and cells. Reopen the layered source and PNG, compare the original paint with the backup, and compare the export with the intended composite. Keep Desktop and canonical `assets/source/` copies synchronized. Export the existing source after paint edits. Regeneration can discard later work.
4. Register runtime PNGs in `src/gfx/sprite_assets.zig` under globally unique filenames. Rebuild embedded assets and inspect native-scale runs, joined-edge cores, exposed edges, corners, holes, ends and junctions in actual headless captures. Finish with `build.cmd`. [Verification](../AGENTS.md#verification) · [Art provenance](ART_PROVENANCE.md) · [HUD artwork](HUD_LAYOUT.md)

## Running Aseprite tools

From the repository root, run batch tools windowless. Supply each Lua parameter as `--script-param key=value` before `--script`. For example, to export the canonical grass sheet:

```powershell
$aseprite = 'C:/Users/DavidBennett/Desktop/projects/Aseprite/src/build/bin/aseprite.exe'
$argsForArt = '--batch --script-param name=grass --script-param source=assets/source/grass.aseprite --script tools/tile_art/export_ground.lua'
$process = Start-Process -FilePath $aseprite -ArgumentList $argsForArt -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 0) { throw "Aseprite exited with $($process.ExitCode)" }
```

Check the script's validation report and reopened pixels. Aseprite can report a successful save even when writing failed. Keep drafts, previews, logs and reports in TEMP. Exporters stage each output under a unique temporary name, then publish the validated bytes. The port/install tools back up existing artwork before replacement. Ground, forest and bridge ports require a byte-identical existing canonical source before installation. Inspect each tool's overwrite checks before using replacement or `install=yes`.

## Walls and forest

Wall masks use N=1, E=2, S=4, W=8, NE=16, SE=32, SW=64 and NW=128. A diagonal requires both adjacent cardinals. The resulting 47 masks occupy eight 64px cells per row in a 512×384 atlas. Leave the final cell empty. Keep `wall_masks.lua`, `sprite_assets.WALL_MASKS` and `grid.WallShape` in sync.

| Material | Working source and tools under `tools/tile_art/` |
| --- | --- |
| Regular wall | Desktop `regular-walls.aseprite`, original `Layer 1`. `export_walls.lua` builds `assets/source/walls.aseprite` and `assets/walls/walls.png` from painted edges, faces, cap details and brick runs. Match `look.WALL_FACE_PX` to the exported face. Review any later edits before rerunning `port_walls.lua`, which also rebuilds the Desktop extension. |
| Forest | `export_forest.lua` exports `assets/source/forest-tree-walls.aseprite` to `assets/walls/forest-tree-walls.png`. Keep `Draw here` and `Forest extensions` separate. `port_forest.lua` derives connections from native canopy copies and refuses an existing extension. `tone_forest.lua` publishes the toned forest, grass and synchronized source copies together. Apply the tone once. Inspect `forest.png` and `shadows-*.png`. |
| New sheets | `guide_walls.lua` and `idea_walls.lua` provide guides and hidden ideas for the Desktop cave/forest sheets. `sheet_title.py <header.png> <title>` renders a header. `new_sheet.lua out=<new.aseprite> title=<header.png>` copies the cave guides into an empty sheet. |

## Ground transitions

Each 64px dual-grid piece represents four map-cell corners. Mask bits are NW=1, NE=2, SW=4, SE=8 in `ground_corners.lua` / `ground.ORDER` order. Mask 0 is empty and 15 wraps as fill. The 512×320 template includes a 64px header and a 256×256 runtime art block. Sheeted ground overlays unsheeted ground in material order, with bridges above water and shallows above deep water.

Use `export_ground.lua name=<material> source=<canonical-file>`. It exports visible paint and extensions in layer order to `assets/ground/<material>-ground.png`. Without `source=` it reads Desktop files. Optional `out=` selects the output. `from=underdrawing` requires an explicit destination outside assets and Python 3.9+ for path resolution.

| Material | Canonical file under `assets/source/` | Extension |
| --- | --- | --- |
| grass | `grass.aseprite` | Grass extensions |
| dirt | `dirt.aseprite` | Dirt extensions |
| shallows | `water.aseprite` | Water extensions |
| water | `deep-water.aseprite` | Water extensions |
| bridge | `bridge.aseprite` | Bridge extensions |

- **Templates.** `ground_sheet.lua` and `ground_labels.py` create blank sheets. `replace=yes` requires matching guide pixels, layers, slices and an unpainted template. Use a new output path for changed parameters.
- **Grass, dirt and shallow water.** `port_ground.lua name=grass|dirt|water` creates a TEMP draft. Preserve strokes across cell boundaries. Existing extensions and changed paint counts block regeneration. Inspect its connected preview alongside its 128 legal adjacent-pair, corner, fill, palette and alpha checks.
- **Deep water.** `deepen_water.lua labels=<ground_labels.py PNG>` derives the initial source using 60% RGB with original alpha and geometry. Installation requires both editable destinations to be absent. `out=` selects the working destination. Re-export the painted deep source for subsequent edits.
- **Bridge.** Keep the original `Draw here` hidden and the connected planks in `Bridge extensions`. `port_bridge.lua previous=<validated-source>` checks existing extension pixels and position before replacement. PNG export applies 70% RGB and lifts pure-black shadows to (42,33,25). Keep the editable palette intact and inspect `bridges.png`.

## Water cliffs and edges

The owner painted on layer 8, which shares a reference layer's name. `Draw here` is blank. Keep the shallow canonical source separate from the deep-only Desktop revision.

| Depth | Canonical file under `assets/source/` | Face layer |
| --- | --- | --- |
| Shallow | `water-cliff-edge.aseprite` | `Shallow cliff - half height` |
| Deep | `water-cliff-edge-deep.aseprite` | `8` |

`export_water_cliff.lua layer=<name-or-index> depth=shallow|deep source=<file>` crops the left/repeat/right slices into 192×64 face strips under `assets/water/`. It compares reopened pixels, emits cap alpha masks and writes lip/foot shadow profiles. Explicit `out=` must end in `.png` and sets the auxiliary stems. `pinch_shallow_cliff.lua` derived shallow columns from the original layer while retaining horizontal positions and lip rows. Preserve its original hidden layer.

`assets/source/water-cliff-connections.aseprite` contains three 4×4 transition blocks in ground order for dirt/shallows, dirt/deep and shallows/deep. Preserve `Owner flat border edits`, `Deep border extensions from shallow edits` and hidden `Before shallow pinch` layers. Layout, names and palette mapping live in `water_cliff_layout.lua`, `water_cliff_names.lua` and `water_cliff_materials.lua`.

- **Import edits.** `port_water_cliff_edits.lua source=<edited.png> baseline=<unedited.png> original=<layered.aseprite> output=<updated.aseprite> preview=<updated.png> report=<TEMP-report>` ports shallow border edits to the deep block. The baseline must match the original. Reopened layers must reproduce the edited composite, including every pixel outside the deep block. Erasing an opaque original pixel cannot be represented by an overlay. Preserve the existing edited sheet.
- **Export edges.** `export_water_edges.lua source=<edited.png> original=<canonical.aseprite> root=<repo-with-trailing-slash> report=<TEMP-report>` writes `dirt-shallows-edges.png`, `dirt-water-edges.png`, `shallows-water-edges.png` and `shallows-water-cap.png`. Each sparse edge atlas has five 256px bands for dry ground, shallow and deep surfaces, and shallow and deep faces. Unknown colors need an explicit material assignment.
- **New templates.** `--shot-water-cliffs` produces the three native renders used by `water_cliff_connected.py <shot-folder>`. Use `--output` for a fresh destination. `--replace` backs up both the layered file and preview. `water_edge_template.py` provides the six-piece paint kit. Its `--replace-blank` verifies the original layers, guide pixels and slices.
- **Runtime.** Inspect stepped banks, narrow pools, depth transitions, three-material joins and shadow toggles in `--shot-water-cliffs`. Play and editor share `ground.Corners.waterCliffFor`. Preserve face dimensions and direction, cap alignment and separate ends for each depth. Lighting, depth fade and reflections belong to the renderer. Use water mirror/memory/step captures and `--bench` when changing those paths.

## Tool verification

Run the matching Python test from the repository root, for example `python -B tools/tile_art/test_ground_sheet.py --aseprite <aseprite.exe>`. All tests below use that invocation with their own filename and temporary fixtures.

| Change | Test scripts under `tools/tile_art/` |
| --- | --- |
| Backup, installation, publication and reopened layers | `test_source_files.py`, `test_port_sources.py`, `test_install_sources.py`, `test_backup_failures.py`, `test_legacy_backups.py`, `test_saved_layers.py` |
| Wall atlas, ground template, deep-water derivation | `test_export_walls.py`, `test_ground_sheet.py`, `test_deepen_water.py` |
| Water faces, overlays and templates | `test_export_water_cliff.py`, `test_port_water_cliff_edits.py`, `test_water_cliff_connected.py`, `test_water_edge_template.py` |
