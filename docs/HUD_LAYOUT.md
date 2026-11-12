# HUD layout

The HUD is one fixed-width assembly centered at the bottom: red life orb, skills,
then blue mana orb. Controls follow [CONTROLLER.md](CONTROLLER.md); wording and
typography follow [DATA_PRESENTATION.md](DATA_PRESENTATION.md).

## Contents

| Show | Presentation |
|---|---|
| Life | Red circular reservoir, filled from the bottom; current / maximum above the orb |
| Mana | Matching blue reservoir and current / maximum |
| Assigned skills | Existing skill pictures and each slot's input icon (`prompt_icon.Prompt`); active secondary set uses the same slots |
| Skill availability | Existing held/aimed state, dimming when unavailable, remaining cooldown on the skill |
| Experience | Thin bar of 10 segments over the skill strip: a faint white track, filled with a warm parchment gradient through the current level |
| Active ailments | Small icons with remaining turns, only while active, just above the central strip |
| Status resistance | A gold buildup meter while active; inspection lists each status's resistance and expiry separately |
| Minimap | Existing upper-right map, outside the bottom assembly |
| Time of day | A thin line under the minimap: the sun rides it from sunrise to sunset, the moon from sunset to sunrise, following the drawn hour (`Presentation.hour_shown`) |
| Event log | Bottom-left panel, newest at bottom, color-coded events during exploration and combat |
| Character and Menu | Clickable actions with glyphs in the bottom-right gutter while keyboard/mouse hints are active |

The live HUD omits the hero-name label, enemy counters, gold tally and permanent control instructions. No screen names a key or button in words; menus and the bind screen show concise action labels beside device glyphs. Life and mana flasks use assigned skill slots, including remaining drinks. Exact XP, levels, equipment and both skill trees appear in Character.

## Layout and placeholder art

- Target a 640-pixel-wide assembly, horizontally centered from `Game.screen`. Its width does not grow on a wider display.
- Two matching 96-pixel orb frames flank the seven-slot skill strip. One continuous backing plate extends behind the skills to each orb's center, so the orbs cover its ends. The plate is 94px tall, at 70% opacity with a 25% shadow.
- The minimap background uses the shared fog gray at 70% opacity. Unexplored texture cells are transparent so they do not obscure that background; terrain and markers retain their contrast.
- Keep the log 12px from the left and bottom edges, 360px tall. Its width follows the free gutter beside the HUD, capped at 330px. It has no heading; text, background and border fade together to 10% of their base opacity at the top. Tooltips and item comparisons follow [DATA_PRESENTATION.md](DATA_PRESENTATION.md): effects and properties lead, with no flavor text, and separate selected and equipped item cards.
- Mount the assembly close to the bottom edge. Draw the map behind it and at both sides instead of reserving a full-width black footer.
- Give each orb a dark empty interior, a solid coloured fill with a horizontal surface, a simple rim and a small highlight. Full, half and empty must read clearly. Clamp resource values to the valid fill range.
- Use Source Sans 3 for compact resource values and cooldowns, with Balthazar for headings and symbols; inputs are icons, not captions. Avoid extra explanatory prose in play.
- Keep geometry, colours and draw functions together so authored orb/frame art can replace the primitives later. Reuse the existing skill images.

## Ownership and timing

`src/ui/hud.zig` owns geometry and drawing; `src/game/overlay.zig` supplies
game data through `drawHud` and `drawSkills`. The map spans `Game.screen`,
with camera clearance from `hud.COVER`. The bind panel sizes for skill rows,
wrapped descriptions and actions using Character's scale.

Life uses `Presentation.pictured`; Mana Shield spending follows its impact.
Skill spending and flask sips update immediately; natural recovery and cooldowns
follow spent turns. Life/mana fills ease in both directions while labels remain
exact. New floors and resumed saves settle fills immediately. These floats are
presentation-only and unsaved. XP follows `Presentation.xp_shown` once the turn
is drawn.

`play/log.zig` owns saved history; `ui/journal.zig` draws it. New events return
to the latest entry; the wheel or HUD inspector scrolls it.

Use `--shot-ui` with [AGENTS.md](../AGENTS.md#verification). Inspect full,
partial, critical and empty resources, ailments, cooldowns, unavailable skills,
both sets, binding and device glyphs at 1280x720, 1600x900 and 1920x1080.
Capture definitions live in `src/game/shots/`.

## Aseprite paint template

The working file is `C:/Users/DavidBennett/Desktop/hud-elements.aseprite`. Its canonical source copy is `assets/source/hud-elements.aseprite`. The sheet is 1024x1024 at native pixel scale; paint the individual components below the assembled reference on the top **Draw here** layer. Save the Aseprite document to preserve its layers and named slices.

These are template dimensions, not current runtime geometry. Inspect owner edits before adapting the sheet; provenance is recorded in [ART_PROVENANCE.md](ART_PROVENANCE.md).

The locked guide layers are **underdrawing (25%)**, **alignment (22%)**, and **labels and separators (45%)**, above a separate dark paper layer. The initial **Draw here** layer is blank, editable and 100% opaque; inspect for later paint before exporting. Hide paper and every GUIDE layer for artwork exports. The assembled reference is guide-only; it is not a component to export.

| Component slices | Size | Painting rule |
| --- | --- | --- |
| `hud_border_9slice` | 48x48 | 16px corners and edge strips; keep the central 16x16 clear. Slice metadata records the cuts. |
| `hud_background_tile` | 32x32 | Seamless in both directions; match opposite edges without a border or baked lighting gradient. |
| `skill_frame`, `skill_frame_active` | 56x56 | Keep the central 40x40 icon space clear (8px inset). |
| `ailment_frame` | 32x32 | Transparent center; allow the turn count at bottom right. |
| `orb_frame_life`, `orb_frame_mana` | 104x104 | Keep the centered 88px opening clear (8px inset). |
| `orb_well` | 88x88 | Empty circular reservoir, transparent outside its circle. |
| `orb_fill_life`, `orb_fill_mana` | 88x88 | Paint full circular fills; resource amounts determine the visible fill height. |
| `orb_glass` | 104x104 | Optional transparent highlight overlay, centered over the reservoir. |
| Six `skill_*` icons | 40x40 | Shoot, Wait, Secondary Set, Juke, Burning Arrow and Glacial Shot. |
| Three `ailment_*` icons | 24x24 | Bleeding, burning and chilled. |

Numbers, resource labels, button captions and cooldowns remain code-rendered. The rectangular frames now use the owner's border artwork described below; the other components retain their procedural graphics until painted.

`tools/hud_art/create_template.py` prepares the guides and a native Aseprite Lua assembly in `%TEMP%/hud-template/`. Both the generator and the generated assembly refuse to overwrite either editable source. Run that assembly with the Aseprite batch command from `TILE_ART_WORKFLOW.md`; it saves both sources, reopens them, and verifies all guide pixels, layer opacity and editability, the blank paint layer, 21 named slices (20 components plus the reference), and the nine-slice center. Previews and validation reports stay in TEMP. Before later ports, read the Desktop file for new owner painting and back it up; do not regenerate over it.

## Painted border

`C:/Users/DavidBennett/Desktop/border.aseprite` holds the owner's gold border on `Layer 1`, a 73x55 cel at (1,1) on a 128x128 canvas. `tools/hud_art/export_border.lua` preserves that source and copies it to `assets/source/hud-border.aseprite`, exporting the native 73x55 rectangle to `assets/ui/hud-border.png`. It backs up existing files in `%TEMP%/hud-border-export/` and checks the reopened pixels and clear center. Run it with the Aseprite batch command in `TILE_ART_WORKFLOW.md`; inspect later owner edits before exporting again.

`sprites.hudBorder` keeps the four original 9x9 corner regions and repeats the matching horizontal and vertical strips, clipping the last repeat without scaling, mirroring, rotating or recolouring the art. Nine-pixel cuts keep the dark corner-to-rail transition out of the repeated bottom edge. The texture loads with common play graphics and is shared by the bottom plate, skill slots and bind picker, status boxes, minimap, the character card, tooltips and prompts, the event log, menus and save rows, conversations and the death panel. Selected slots retain a coloured inner outline; unavailable slots retain their opacity fade. Status boxes are 40px to keep their icons and counts clear of the painted trim, and the minimap reserves a 9px frame. Orb rims and resource fills remain procedural.
