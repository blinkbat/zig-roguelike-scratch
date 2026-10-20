# Art provenance and owner review

This is the attribution index for shipped art and procedural placeholders. A runtime PNG is
not automatically an owner original: some contain assistant-built extensions of owner pixels.
Keep original paint and derived work separate in editable sources. Do not regenerate over
later owner edits.

## Needs an owner art pass

| Element | Attribution | Location | Review |
|---|---|---|---|
| Skill icons and controller/key prompts | Assistant, procedural line art | `src/gfx/look.zig`: `skillLines`, `inkSkill`, `Prompt` | Replace skill glyphs when desired; input symbols stay basic |
| Life/mana orbs and status icons | Assistant, procedural shapes | `src/ui/hud.zig` | Paint orb and ailment components in the existing HUD template |
| Equipment slots, tree nodes and item markers | Assistant, code-drawn placeholders; radial tree layout adapted from the owner's `zig-soulslike` | `src/ui/book.zig`, `src/ui/trees.zig`; `src/game.zig` loot drawing | Basic rectangles, circles, lines, shared skill glyphs, `*` items and `$` gold; no item sprites yet |
| Event panel | Owner border, assistant layout and colors | `src/ui/journal.zig`, `assets/hud-border.png` | Layout/color review; border painting is the owner's |
| Missing body/tile pictures | Assistant glyph fallback | `src/gfx/look.zig`: body/tile lookup | Unpainted kinds retain glyphs |
| Combat effects, weather, lighting, water reflections | Assistant procedural rendering | `src/gfx/fx.zig`, `pixel.zig`, `weather.zig`, `light.zig`; map drawing | Effects review; these are not painted source pixels |

All additions in the inventory/progression pass are code-drawn placeholders. This pass
does not generate, alter or install raster artwork.

## Owner originals and derived terrain

These attributions are recorded in [TILE_ART_WORKFLOW.md](TILE_ART_WORKFLOW.md) and
[HUD_LAYOUT.md](HUD_LAYOUT.md). "Derived" means constructed from owner pixels by the
documented scripts; it does not mean every resulting tile has been hand-painted or approved.

| Runtime asset | Owner original | Assistant contribution | Owner review target |
|---|---|---|---|
| `assets/hud-border.png` | Desktop `border.aseprite`, `Layer 1`; canonical `assets/source/hud-border.aseprite` | Crop/export and nine-slice placement | Original border is owner-painted |
| `assets/walls.png` | Desktop `regular-walls.aseprite`, `Layer 1` | `port_walls.lua`, `export_walls.lua`; assembled 47-mask runtime sheet in `assets/source/walls.aseprite` | Generated connections, corners and faces |
| `assets/grass-ground.png` | `assets/source/grass.aseprite`, `Draw here` | `Grass extensions` via `port_ground.lua` | Extension layer and joins |
| `assets/dirt-ground.png` | `assets/source/dirt.aseprite`, `Draw here` | `Dirt extensions` via `port_ground.lua` | Extension layer and joins |
| `assets/shallows-ground.png` | `assets/source/water.aseprite`, `Draw here` | `Water extensions`, exported as shallows | Extension layer and shore joins |
| `assets/water-ground.png` | Derived from the owner's shallow-water source | `deepen_water.lua` 60% RGB transform; `assets/source/deep-water.aseprite` | Whole derived deep-water sheet, including its `Draw here` layer |
| `assets/forest-tree-walls.png` | `assets/source/forest-tree-walls.aseprite`, `Draw here` | `Forest extensions`; documented owner-requested palette transform | Generated canopy/trunk connections and recolor |
| `assets/grass.png` | Existing grass raster; original source not recorded here | Documented 15% RGB reduction in `tone_forest.lua` | Preserve owner backup; verify original attribution |
| `assets/source/hud-elements.aseprite` | Paint on the Desktop working copy must be inspected before export | Initial template, guides, reference assembly and named slices from `create_template.py` | Original paint layer versus generated guides |
| Desktop cave/forest guide sheets | Owner paint on `Draw here`, if present | `guide_walls.lua` guides and `idea_walls.lua` rough ideas | `Ideas - hide before export` is assistant work, not shipping art |

Original forest/grass backups are in `assets/backup/`, by owner request. Other backups and
reference screenshots belong in TEMP. Generated guides, labels, and rough ideas are never
owner originals.

## Existing raster files awaiting individual attribution

The project describes these as supplied PNG art, but their individual source files and edit
histories have not been verified in this pass. This is an attribution task, not an instruction
to repaint or replace them.

| Group | Runtime files | Status |
|---|---|---|
| Heroes | `archer.png`, `wizard.png` | Verify source/author |
| Foes | `rat.png`, `bloat.png`, `pib.png`, `slime.png`, `slime-half.png`, `slime-quarter.png` | Verify originals versus derived size variants |
| Props | `barrel.png`, `chest.png`, `chest-open.png`, `boulder.png` | Verify source/author |
| Ground/decor | `floor.png`, `reeds.png`, `shrub.png`, `small-shrooms.png`, `tall-grass.png`, `tall-shroom.png`, `tiny-shrub.png` | Verify source/author |

`Balthazar-Regular.ttf` is third-party font art, covered by `Balthazar-OFL.txt`.
Controller mappings are data, covered by `gamecontrollerdb-LICENSE`.

## Rules for future changes

- Record each new asset here as owner original, assistant-derived, assistant placeholder,
  third-party, or unverified; include its editable source and review status.
- Keep the owner's original layer untouched. Put assistant changes on their own named
  layer and list that layer here. Existing extension names above are retained.
- Put any new standalone assistant source art under `assets/source/assistant/`; do not move
  existing owner files or flatten mixed sources merely to reorganize them.
- The flat runtime `assets/` filenames are build inputs. Their attribution comes from this
  index and editable layers, not from the fact they are shipped.
