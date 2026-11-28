# HUD layout

The map fills the window. A fixed 640px HUD sits at bottom center with room for the camera above `hud.COVER`. Geometry and drawing live in [ui/hud.zig](../src/ui/hud.zig). [game/overlay.zig](../src/game/overlay.zig) supplies pictured resources, skills and statuses.

## Runtime layout

| Region | Placement and contents |
| --- | --- |
| Life and mana | Two 96px orbs flank the seven skill slots. Each shows a horizontal fill, dark empty well, highlight and exact current/maximum value above its painted rim. |
| Skill plate | A continuous 94px-high backing at 70% opacity, with a 25% shadow, reaches each orb's center. Slots show the active set, input glyph, availability, cooldown or remaining drinks, and held/aimed state. |
| Experience and statuses | Ten XP segments run over the skill strip. Active 40px status tiles stack upward, centered between the orbs. Tiles show remaining turns and active resistance buildup. Inspection gives individual resistance and expiry. Tooltips open above the highest row. |
| Minimap | Top right in a 9px frame. Transparent unexplored cells expose a 70% fog-gray backing. A sun or moon moves along the line below it with `Presentation.hour_shown`. |
| Event log | Bottom left, 12px from both edges, 360px tall and 120–330px wide. The newest event is at the bottom. Text, background and border fade to 10% at the top. New events return to the latest entry. |
| Character and Menu | Small borderless glyph actions in the bottom-right gutter while keyboard/mouse hints are active. |

Character holds exact XP, level, equipment and skill trees. Keep the play view free of a hero-name label, enemy counters, a gold tally and permanent control instructions. [Controls](CONTROLLER.md) · [Typography and inspection](DATA_PRESENTATION.md)

## Ownership and timing

Life and Mana Shield loss follow the pictured impact. Skill spending and flask sips update immediately. Recovery and cooldowns follow spent turns. Orb fills ease in both directions, then settle immediately on floor entry or loading. Labels show exact pictured values. XP follows `Presentation.xp_shown` after the turn is drawn. Fill animations stay out of saves. [Presentation](../src/game/presentation.zig)

The log saves history in `play/log.zig` and renders it through `ui/journal.zig`. Use `--shot-ui` to inspect full, partial, critical and empty resources, ailments, cooldowns, both sets, bindings and glyphs at 1280×720 and larger supported sizes. [Verification](../AGENTS.md#verification)

## Aseprite paint template

The 1024×1024 sheet has 21 named slices (20 components and one assembled reference). Its Desktop working file is `C:/Users/DavidBennett/Desktop/hud-elements.aseprite` and its canonical copy is `assets/source/hud-elements.aseprite`. Inspect and back up the owner's latest paint before exporting. Slice dimensions below apply to the template.

Paint individual components on **Draw here** at native scale and preserve the layers and slices. The original guides are locked at 25% for underdrawing, 22% for alignment and 45% for labels/separators. Hide every guide and the paper layer for exports. The assembled reference is a guide.

| Component slices | Size | Painting rule |
| --- | --- | --- |
| `hud_border_9slice` | 48x48 | 16px corners and edge strips, keep the central 16x16 clear. Slice metadata records the cuts. |
| `hud_background_tile` | 32x32 | Seamless in both directions, match opposite edges without a border or baked lighting gradient. |
| `skill_frame`, `skill_frame_active` | 56x56 | Keep the central 40x40 icon space clear (8px inset). |
| `ailment_frame` | 32x32 | Transparent center, allow the turn count at bottom right. |
| `orb_frame_life`, `orb_frame_mana` | 104x104 | Keep the centered 88px opening clear (8px inset). |
| `orb_well` | 88x88 | Empty circular reservoir, transparent outside its circle. |
| `orb_fill_life`, `orb_fill_mana` | 88x88 | Paint full circular fills, resource amounts determine the visible fill height. |
| `orb_glass` | 104x104 | Optional transparent highlight overlay, centered over the reservoir. |
| Six `skill_*` icons | 40x40 | Shoot, Wait, Secondary Set, Juke, Burning Arrow and Glacial Shot. |
| Three `ailment_*` icons | 24x24 | Bleeding, burning and chilled. |

Runtime code draws text, counts, resource fills, skill glyphs and status icons. Owner paintings supply the frame PNGs. For a fresh template, `tools/hud_art/create_template.py` prepares the guides and Lua assembly under `%TEMP%/hud-template/`. The batch assembly verifies guide pixels, layer settings, the initial blank paint layer, named slices and nine-slice center. The generator and assembly refuse to overwrite either editable source. [Aseprite workflow](TILE_ART_WORKFLOW.md) · [Art provenance](ART_PROVENANCE.md)

## Painted border

The owner's `Desktop/border.aseprite` contains a 73×55 cel at (1,1) on a 128×128 canvas, on `Layer 1`. `tools/hud_art/export_border.lua` copies the source to `assets/source/hud-border.aseprite`, exports the native rectangle to `assets/ui/hud-border.png`, and checks reopened pixels and the clear center. Numbered backups go under `%TEMP%/hud-border-export/`.

Large frames retain the 9×9 original corners. `raster.frame` tiles the rails at native scale and clips the final repeat, keeping the corner transitions out of the rails. Small boxes use the 52×35 `hud-border-small.png` with 4px cuts. Selected slots retain an inner outline and unavailable slots fade. The life and mana rim PNGs sit over their fills at native scale. [Frame renderer](../src/gfx/raster.zig)
