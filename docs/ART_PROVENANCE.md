# Art provenance and owner review

Record shipped art by source and layer. Preserve owner paint and place derived work on named editable layers.

## Procedural art and placeholders

| Element | Attribution | Location | Review |
|---|---|---|---|
| Skill icons and controller/key prompts | Assistant, procedural line art | `src/gfx/line_icons.zig`: `skillLines`, `inkSkill`; `src/gfx/prompt_icon.zig`: `Prompt` | Replace skill glyphs when desired; input symbols stay basic |
| Item glyphs | Assistant, procedural line art | `src/gfx/line_icons.zig`: `ITEM_LINES`, `drawItem` | One glyph per item kind on the skill icons' 32-unit grid; replace when desired |
| Life/mana fills and status icons | Assistant, procedural shapes | `src/ui/hud.zig` | The resource rims use the owner's artwork listed below |
| Equipment slots and tree nodes | Assistant, code-drawn placeholders; radial tree layout adapted from the owner's `zig-soulslike` | `src/ui/book.zig`, `src/ui/trees.zig` | Basic rectangles, circles, lines and shared skill glyphs; gold and item containers use the supplied rasters below |
| Event panel | Owner border, assistant layout and colors | `src/ui/journal.zig`, `assets/ui/hud-border.png` | Layout/color review; border painting is the owner's |
| Missing body/tile pictures | Assistant glyph fallback | `src/gfx/look.zig`: body/tile lookup | Unpainted kinds retain glyphs |
| Combat effects, weather, lighting, water reflections | Assistant procedural rendering | `src/gfx/fx.zig`, `pixel.zig`, `weather.zig`, `light.zig`, `shadow.zig`, `light_gpu.zig`; map drawing | Effects review; these are not painted source pixels |

## Owner originals and derived terrain

For export steps and HUD template dimensions, see [tile artwork](TILE_ART_WORKFLOW.md) and [HUD layout](HUD_LAYOUT.md).

| Runtime asset | Owner original | Assistant contribution | Owner review target |
|---|---|---|---|
| `assets/bodies/knight.png` | Desktop `knight.aseprite`, `Layer 1`; byte-for-byte canonical copy at `assets/source/knight.aseprite` | Native 64x64 visible-layer export, with pixels, transparency and placement unchanged; registered for the knight body | Original sprite is owner-painted |
| `assets/ui/hud-border.png` | Desktop `border.aseprite`, `Layer 1`; canonical `assets/source/hud-border.aseprite` | Crop/export and nine-slice placement | Original border is owner-painted |
| `assets/ui/hud-life-frame.png` | Desktop `hud-elements.aseprite`, `Layer 1` (the `orb_frame_life` drawing, cropped to its painted bounds); canonical `assets/source/hud-elements.aseprite` | Crop/export and placement over the life orb | Original frame is owner-painted |
| `assets/ui/hud-border-small.png` | Desktop `hud-border-small.png` (top-left corner, top and left rails); canonical `assets/source/hud-border-small-drawn.png` | Mirrored into a 52x35 nine-slice, 4px corner cut, drawn one texel per screen pixel by `menu.border` | Original rail and corner are owner-painted |
| `assets/ui/hud-mana-frame.png` | Desktop `hud-elements.aseprite`, `Layer 1` (the `orb_frame_mana` drawing, cropped to its painted bounds); canonical `assets/source/hud-elements.aseprite` | Crop/export and placement over the mana orb | Original frame is owner-painted |
| `assets/walls/walls.png` | Desktop `regular-walls.aseprite`, `Layer 1` | `port_walls.lua`, `export_walls.lua`; assembled 47-mask runtime sheet in `assets/source/walls.aseprite` | Generated connections, corners and faces |
| `assets/ground/grass-ground.png` | `assets/source/grass.aseprite`, `Draw here` | `Grass extensions` via `port_ground.lua` | Extension layer and joins |
| `assets/ground/dirt-ground.png` | `assets/source/dirt.aseprite`, `Draw here` | `Dirt extensions` via `port_ground.lua` | Extension layer and joins |
| `assets/ground/shallows-ground.png` | `assets/source/water.aseprite`, `Draw here` | `Water extensions`, exported as shallows | Extension layer and shore joins |
| `assets/ground/water-ground.png` | Derived from the owner's shallow-water source | `deepen_water.lua` 60% RGB transform; `assets/source/deep-water.aseprite` | Whole derived deep-water sheet, including its `Draw here` layer |
| `assets/ground/bridge-ground.png` | Desktop `bridge.aseprite`, `Draw here` (kept, hidden); canonical `assets/source/bridge.aseprite` | `Bridge extensions` via `port_bridge.lua`: continuous interior copied from his grain, exposed caps and side-outline repairs across all 15 cells; owner-requested 30% RGB darkening and pure-black shadow lift to (42,33,25) on PNG export only | Whole extension layer, especially exposed edges and grain joins |
| `assets/walls/forest-tree-walls.png` | `assets/source/forest-tree-walls.aseprite`, `Draw here` | `Forest extensions`; documented owner-requested palette transform | Generated canopy/trunk connections and recolor |
| `assets/props/caravan-cart.png` | Owner-supplied 128x128 raster preserved on `Owner original` in `assets/source/assistant/caravan-cart.aseprite` | Lowered the three light canvas colors and softened selected seam pixels on `Canvas highlights` and `Canvas seam cleanup`. Added three short ridge highlights on `Off-white canvas accents`. | Canvas touch-up at native scale with the original silhouette |
| `assets/ground/grass.png` | Existing grass raster; original source not recorded here | Documented 15% RGB reduction in `tone_forest.lua` | Preserve owner backup; verify original attribution |
| `assets/source/hud-elements.aseprite` | Paint on the Desktop working copy must be inspected before export | Initial template, guides, reference assembly and named slices from `create_template.py` | Original paint layer versus generated guides |
| Desktop cave/forest guide sheets | Owner paint on `Draw here`, if present | `guide_walls.lua` guides and `idea_walls.lua` rough ideas | `Ideas - hide before export` is assistant work, not shipping art |
| `assets/water/shallows-cliff.png`, `assets/water/water-cliff.png` | Desktop `water-cliff-edge.aseprite`, layer 8 (duplicate reference-layer name); canonical copies at `assets/source/water-cliff-edge.aseprite` (shallow, which adds `Shallow cliff - half height` below) and byte-for-byte `water-cliff-edge-deep.aseprite` (deep) | `water_edge_template.py` supplies guides; `export_water_cliff.lua layer="Shallow cliff - half height" depth=shallow source=...` and `layer=8 depth=deep source=...` each copy three 64x64 tiles without reference pixels, the deep ones unchanged; runtime joins the pieces along viewer-facing banks | Owner-painted faces at both depths. Assistant-derived `*-cliff-cap.png` alpha masks fill above the paint using adjacent ground; cap masks close and taper the outside end gaps with aligned plain ground texture; exported foot profiles anchor shadows to the painted outline. Faces share the water camera/depth tint; other border tiles retain their original light/dark rims. Guide/reference layers are assistant layout, separate from the cropped artwork |

### Supplied rasters

These runtime PNGs were supplied by the owner. Their editable sources or individual authorship are unverified. Preserve their pixels at native scale.

| Asset | Runtime use |
| --- | --- |
| `assets/bodies/beefy-pib.png`, `assets/bodies/bandit-crossbowman.png`, `assets/bodies/pib-shaman.png`, `assets/bodies/bandit-trapper.png`, `assets/bodies/pyre-bloat.png`, `assets/bodies/bog-leech.png`, `assets/bodies/skeleton.png` | Foe bodies |
| `assets/plants/swamp-tree.png` | Standalone tree near water on the default map |
| `assets/plants/large-tree.png` | Two-cell-high tree anchored at its blocking base, scattered sparsely on grass; upper bough fades while hiding the hero |
| `assets/plants/brush.png` | Scattered on grass tiles by stable cell position |
| `assets/plants/flowers.png` | Scattered on separate grass tiles alongside brush by stable cell position |
| `assets/plants/glowbulb.png` | Registered as the glowbulb (`glow_plant`) prop's picture over its grass, replacing its `&` glyph |
| `assets/plants/shrub2.png` | Stable alternate for lone shrubs that are not forest clumps |
| `assets/props/small-coins.png`, `assets/props/large-coins.png` | Registered for ground gold without items; mixed drops share an item bag and chest gold stays in its chest; no coin lights |
| `assets/props/item-bag.png`, `assets/props/chest-item-bag.png` | Registered for ground item piles and nonempty open chests |
| `assets/props/mimic-closed.png`, `assets/bodies/mimic-open.png` | Closed: a mimic's chest while disguised and until its death in it is drawn. Open: the mimic's body |
| `assets/ground/grass2.png` | Stable alternate for fully filled grass pieces using existing borders |
| `assets/ground/dirt2.png` | Stable alternate for fully filled dirt pieces using existing borders |
| `assets/ground/shallows2.png`, `assets/ground/shallows3.png` | Stable alternates for fully filled shallows pieces using existing borders |

### Water-cliff layers

The Desktop `water-cliff-connections.aseprite` template and PNG preview were assembled from native game renders and six owner-painted face crops at their original RGBA. The assistant supplied the labels, mask keys, grid and three 16-mask blocks. Lighting, reflections and shadows are applied at runtime.

| Editable layer | Attribution and verification |
| --- | --- |
| `Owner flat border edits` | The canonical `assets/source/water-cliff-connections.aseprite` retains the owner's subsequent PNG edits above the template. |
| `Deep border extensions from shallow edits` | `port_water_cliff_edits.lua` transferred 918 changed shallow pixels using the deep palette and extended eight erased end pixels through the taller feet. All pixels outside the middle block match the owner's edited PNG. |
| `Shallow cliff - half height` | `pinch_shallow_cliff.lua` compressed the painted columns with native-palette endpoint sampling, preserving lip rows and horizontal positions. The original layer 8 stays hidden. Matching shallow border edits moved with the faces. The previous connected layers remain under `Before shallow pinch`. |
| Runtime edge sheets | `export_water_edges.lua` writes `dirt-shallows-edges.png`, `dirt-water-edges.png`, `shallows-water-edges.png` and `shallows-water-cap.png`. Dry ground, water surfaces and faces retain their material classification. The shallow profile uses a 6/64-cell shadow height. |

Keep the owner-requested forest and grass backups in `assets/backup/`. Other backups, references and previews belong in TEMP.

## Existing raster files awaiting individual attribution

The following shipped PNGs still need individual source and edit-history verification.

| Group | Runtime files | Status |
|---|---|---|
| Heroes | `archer.png`, `wizard.png` | Verify source/author |
| Foes | `rat.png`, `caustic-bloat.png` (renamed from `bloat.png`, identical image bytes), `pib.png`, `slime.png`, `slime-half.png`, `slime-quarter.png` | Verify originals versus derived size variants |
| Props | `barrel.png`, `chest.png`, `chest-open.png`, `boulder.png` | Verify source/author |
| Ground/decor | `floor.png`, `reeds.png`, `shrub.png`, `small-shrooms.png`, `tall-grass.png`, `tall-shroom.png`, `tiny-shrub.png` | Verify source/author |

`Balthazar-Regular.ttf` is third-party font art, covered by `Balthazar-OFL.txt`.
`SourceSans3-Regular.ttf` is Adobe's unmodified Source Sans 3, used for compact UI text,
covered by `SourceSans3-OFL.txt`. Source: [Adobe's release tree](https://github.com/adobe-fonts/source-sans/tree/87b37a2daaed80fcb8e8ccb0085c4d72ddade12e),
`TTF/SourceSans3-Regular.ttf`. Balthazar remains the display face.
Controller mappings are data, covered by `gamecontrollerdb-LICENSE`.

## Attribution rules

- Record each new asset here as owner original, assistant-derived, assistant placeholder,
  third-party, or unverified; include its editable source and review status.
- Record the exact layer containing each assistant edit.
- Put any new standalone assistant source art under `assets/source/assistant/`; do not move
  existing owner files or flatten mixed sources merely to reorganize them.
