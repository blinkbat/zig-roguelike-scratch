# Path of Exile 2 HUD

## Requested scope

Use Path of Exile 2 as the reference. Build one fixed-width HUD centered at the bottom, with a filled red life orb on the left, skills in the middle, and a filled blue mana orb on the right. Use simple graphics that David can paint over later.

Claude owns keybinds and input behaviour; this pass owns HUD composition and rendering. Read the current bindings and device captions, without changing their controls, defaults, secondary-set behaviour or binding interactions. See [CONTROLLER.md](CONTROLLER.md).

## Reference and adaptation

The [official PlayStation Store gameplay gallery](https://store.playstation.com/en-us/concept/10010602) includes this [Path of Exile 2 controller screenshot](https://image.api.playstation.com/vulcan/ap/rnd/202408/2123/a3c89df0c4e35ea926b73c75b1c9b1bd11f6b2fc80768f06.jpg), inspected for the orb, skill-slot and button-caption hierarchy. It shows red and blue globes, a framed skill strip, and contextual button labels. Its globes sit at the screen edges; bringing both beside the skills in one fixed-width assembly is David's requested adaptation.

Only display the corresponding systems this game actually has. Do not fill the layout with imitation systems or decorative counters.

| Show | Presentation |
|---|---|
| Life | Red circular reservoir, filled from the bottom; current / maximum above the orb |
| Mana | Matching blue reservoir and current / maximum |
| Assigned skills | Existing skill pictures and each slot's input icon (`look.Prompt`); active secondary set uses the same slots |
| Skill availability | Existing held/aimed state, dimming when unavailable, remaining cooldown on the skill |
| Active ailments | Small icons with remaining turns, only while active, just above the central strip |
| Minimap | Existing upper-right map, outside the bottom assembly |

Remove the live HUD's hero-name label, enemy population counters, gold tally, permanent movement/pause/binding instructions and scrolling combat log. Keep their simulation and saved data. No screen names a key or button in words; menus and the bind screen carry no instructions. Life and mana flasks use assigned skill slots, including their remaining drinks; there is no separate flask bar. Do not add charms, experience, levels, spirit, energy shield, inventory or quest widgets: those systems do not exist here.

## Layout and placeholder art

- Target a 744-pixel-wide assembly, horizontally centered from `Game.screen`. Its width does not grow on a wider display.
- Two matching 104-pixel orb frames flank the existing seven-slot skill strip. One continuous backing plate extends behind the skills to each orb's center, so the orbs completely cover its ends. The plate is 100px tall and its lower edge sits just above the orb bases; no square endcaps project beyond the orbs.
- Mount the assembly close to the bottom edge. Draw the map behind it and at both sides instead of reserving a full-width black footer.
- Give each orb a dark empty interior, a solid coloured fill with a horizontal surface, a simple rim and a small highlight. Full, half and empty must read clearly. Clamp resource values to the valid fill range.
- Use the current Balthazar face for small resource values and cooldowns; inputs are icons, not captions. Avoid extra explanatory prose in play.
- Keep geometry, colours and draw functions together so authored orb/frame art can replace the primitives later. Reuse the existing skill images.
- Life follows the presented HP (`Game.pictured`), so it changes when a hit lands. Mana spent by Mana Shield follows each hit's impact; other mana changes and cooldowns follow the turn. Layout code does not change gameplay.

## Verification

Use the existing check, test, shot and build scripts. Inspect full, partial, critical and empty resources, active ailments, cooldown/unavailable skills, primary/secondary sets, and controller/keyboard captions. Check centering and clipping at 1280x720, 1600x900 and 1920x1080. Verify the bind screen still works with the same binding data. Keep previews and reports in TEMP or the existing headless shot workflow; do not launch an interactive game.

## Implementation

Implemented in `src/ui/hud.zig`, with game data supplied by `drawHud` and `drawSkills` in `src/game.zig`. The HUD module holds the orb/frame geometry, colours, fill calculation and ailment icons for later replacement with authored art. The selected aiming slot stays highlighted. Each slot's input is a `look.Prompt` icon under it.

Small Balthazar text is rasterized at its displayed size (12, 15, 16, 20 and 24px) with point filtering, measured and drawn from the same atlas. Larger text and map symbols retain the 96px mipmapped atlas. Input icons are 22px tall with 15px labels, 6px below their slots. Slots have 10px gaps within groups and 20px between groups; the assembly remains 744px wide. The taller plate and raised status row keep these larger captions clear of the painted rails.

The map now spans the full screen (`Game.screen`), the camera scrolling past the floor's foot by `hud.COVER`. The bind overlay is centered in the space above the HUD. The former bar, counter, log and permanent-hint renderers are removed; their gameplay and save data remain intact.

The dedicated captures are `shots/hud-full-1280.png`, `hud-partial-1600.png`, `hud-critical-1920.png`, `hud-empty-1600.png`, `hud-ps5-1280.png`, `hud-secondary-pad.png`, `hud-bind-pad.png`, `hud-bind-ps5.png`, `hud-bind-720.png`, `hud-inspect-skill.png`, `hud-inspect-status.png` and `hud-inspect-mana.png`. `shot.cmd` regenerates them all; previews and logs remain outside tracked source.

## Aseprite paint template

The working file is `C:/Users/DavidBennett/Desktop/hud-elements.aseprite`. Its initial source copy is `assets/source/hud-elements.aseprite`. The sheet is 1024x1024 at native pixel scale; paint the individual components below the assembled reference on the top **Draw here** layer. Save the Aseprite document to preserve its layers and named slices.

The locked guide layers are **underdrawing (25%)**, **alignment (22%)**, and **labels and separators (45%)**, above a separate dark paper layer. **Draw here** is blank, editable and 100% opaque. Hide paper and every GUIDE layer for artwork exports. The assembled reference is guide-only; it is not a component to export.

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

`tools/hud_art/create_template.py` prepares the guides and a native Aseprite Lua assembly in `%TEMP%/hud-template/`. It refuses to overwrite either editable source. Run that assembly with the Aseprite batch command from `TILE_ART_WORKFLOW.md`; it saves both sources, reopens them, and verifies all guide pixels, layer opacity and editability, the blank paint layer, 21 named slices (20 components plus the reference), and the nine-slice center. Previews and validation reports stay in TEMP. Before later ports, read the Desktop file for new owner painting and back it up; do not regenerate over it.

## Painted border

`C:/Users/DavidBennett/Desktop/border.aseprite` holds the owner's gold border on `Layer 1`, a 73x55 cel at (1,1) on a 128x128 canvas. `tools/hud_art/export_border.lua` preserves that source and copies it to `assets/source/hud-border.aseprite`, exporting the native 73x55 rectangle to `assets/hud-border.png`. It backs up existing files in `%TEMP%/hud-border-export/` and checks the reopened pixels and clear center. Run it with the Aseprite batch command in `TILE_ART_WORKFLOW.md`; inspect later owner edits before exporting again.

`look.hudBorder` keeps the four original 9x9 corner regions and repeats the matching horizontal and vertical strips, clipping the last repeat without scaling, mirroring, rotating or recolouring the art. Nine-pixel cuts keep the dark corner-to-rail transition out of the repeated bottom edge. The texture loads with common play graphics and is shared by the bottom plate, skill slots and bind picker, status boxes, and minimap. Selected slots retain a coloured inner outline; unavailable slots retain their opacity fade. Status boxes are 40px to keep their icons and counts clear of the painted trim, and the minimap reserves a 9px frame. Orb rims and resource fills remain procedural.
