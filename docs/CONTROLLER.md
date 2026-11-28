# Controller

The controller is primary. Keyboard and mouse share its game actions. Device polling, bindings, glyph names and repeat timing live in [core/input.zig](../src/core/input.zig), [input_bindings.zig](../src/core/input_bindings.zig), [input_names.zig](../src/core/input_names.zig) and [input_repeat.zig](../src/core/input_repeat.zig).

## Devices and options

- Glyphs follow the last active device. A button, trigger or walking stick selects the pad. A key, mouse movement, button or wheel selects keyboard/mouse. An idle pointer preserves pad navigation.
- GLFW uses the first mapped pad in raylib's four slots until another presses a button or pulls a trigger. Trigger latches engage at 60% travel and release below 40%. Sony vendor `054c` selects PS4/PS5 glyphs. The table uses Xbox positions (A/B/X/Y correspond to Cross/Circle/Square/Triangle). Left-stick click, PS button and touchpad have no game binding.
- Mappings load in increasing priority from the embedded SDL_GameControllerDB (`c1d5289`), `SDL_GAMECONTROLLERCONFIG`, then `gamecontrollerdb.txt` beside the executable. [Database license](../assets/data/gamecontrollerdb-LICENSE)
- Visuals sliders move in 5% steps or drag to either end. Confirm toggles the default/sample value, Change restores the row default, and the two bulk actions restore defaults or set every slider to zero. Display controls fullscreen, VSync and the frame cap (uncapped, 30, 60, 120 or 144 FPS).
- Pause → Debug groups gameplay, lighting, effects and diagnostics. Reveal Map affects rendering only. Diagnostics reports the OpenGL renderer/version, window and framebuffer sizes, FPS and CPU frame time excluding pacing. Debug settings last for the app session. Back restores the parent selection.

## Bindings

| Action | Pad | Keyboard |
|---|---|---|
| Move | D-pad, left stick | WASD, arrows, numpad |
| Diagonal | hold LT + d-pad | hold Shift + WASD/arrows, two keys at once, numpad 1 3 7 9 |
| Skill slots | LB, A, X, Y, B, RB, RT | 1 upwards, left to right, skipping the modifier slot |
| Secondary skill set | Hold its bound slot (LB by default) | hold Ctrl |
| Character | Start / Menu / Options | Tab |
| Game menu (from play) | Select / View / Share / Create | Esc |
| Character tabs | LB / RB | Q / E |
| Close Character | B | Esc |
| Equipment / Inventory / Stats / Passives / Skills / Quests directly | Character tabs | F1 / F2 / F3 / F4 / F5 / F7 |
| Skills: bind selected skill | X | C |
| Stats: advanced / main sheet | X | C |
| Inventory: equip / drop / change ring | A / Y / X | Enter / Del / C |
| Inspect HUD (from play) | Right-stick click (RS/R3) | I |
| Get out (reticle, binds, menus, pause) | B | X or Esc in menus/targeting |
| Confirm, select | A | Enter, Space or Z |
| Interact in play | A / Cross | Enter or Space |
| Talk to NPCs | walk into them, or Interact beside them | walk into them, Enter or Space beside them |
| Conversation: choose, go on | D-pad up/down, A | arrows/WS, Enter, Space or Z |
| Scroll event log | Inspect log, up/down | Wheel over log, or Inspect then up/down |
| Bind screen: change, remove | X, Y | C, Del |
| Passive tree: browse | Left stick, actual bearing | WASD, arrows, numpad |
| Passive tree: pan | Right stick | Shift + WASD/arrows/numpad |
| Passive tree: zoom | D-pad up/down or X/Y steps | =/-, keypad +/-, Page Up/Down or C/Del steps |
| Passive tree: overview | Right-stick click | Home |
| Delete a save | Y | Del |
| Fullscreen | Options > Display > Fullscreen | Alt+Enter, or Options |
| Name the hero | walk the letter grid, A types, X deletes | Type, Backspace deletes, Enter finishes |

Class kits come from `skillbar`. New runs and the binding picker filter class skills by learned rank. With the default modifier, Ctrl selects the secondary set and 1–6 address A, X, Y, B, RB and RT. Moving the modifier renumbers the other slots.

## Interaction contracts

- **Turn buffering.** Movement, skills and interactions wait for the current turn to finish. The latest request wins, except a held movement repeat cannot replace a queued skill or interaction. With a visible foe nearby, the buffer opens for the final 120 ms, including map clicks. Interaction queued during door travel runs after arrival. Focus loss clears pending input and unsettled taps. The current picture finishes, device glyphs persist, and trigger latches continue polling.
- **Targeting.** Confirm with A, Enter, Space, Z or the skill's own number. B, Select, X or Esc cancels even if B opened targeting. A secondary skill keeps its set after modifier release. Arcane Barrier and Fire Wall take two endpoint confirmations. Overwatch takes a direction.
- **Smart aim.** Projectile, melee and rush skills retain a living, visible, legal target or select the nearest eligible foe. From a selected foe, a direction cycles to a candidate within 45° of the input bearing from the reticle. Without a candidate the reticle moves freely and stays free until it reaches another eligible foe. Leaps are freely aimed. The reticle shows the inspection card for the visible foe under it. Changing levels, restarting or loading clears target memory.
- **Hidden collisions.** Reach highlights, wall lines and suggestions use visible bodies. Casting checks actual occupancy. A projectile may aim at dark or empty ground in range and line of sight. If its preview has no visible target, confirm twice on the same cell to fire. A nonpiercing shot stops at the first actual collision.
- **Character.** Start or Tab reopens the last page and closes it on a second press. Direct page keys switch pages or close the matching page, canceling an unconfirmed reticle. From Character, Select opens Game on a pad and Esc backs out on keyboard. The cursor stays in page content. Equip, unequip and drop keep Character open and spend a turn. Ring comparison follows the chosen destination. Browsing, allocating points and binding spend no turns. From Skills, select a binding destination and confirm once. Back returns to Skills.
- **Inspect.** Browse visible units, life, skills, mana, active statuses and log. Hold the modifier to inspect the secondary set. Page controls or the wheel scroll long cards. Scroll the log vertically and leave it sideways. Back, Select or Inspect closes this layer. Inspect on linked terms focuses their definitions. [Keyword behavior](DATA_PRESENTATION.md#shared-presentation)

## Mouse

- Click a menu row to activate it, wheel through lists, and use right-click or Back/Close to dismiss one layer. Delete a save with two deliberate presses on the same slot. The name grid accepts letters, Space, Delete and Done. Click a reply or Continue to advance a conversation. Conversations run to their authored ending.
- Click explored ground to walk a known route avoiding walls, known barrels, visible gas and intermediate doors. Walking stops at arrival, a visible foe, damage, another action, focus loss, or a screen/level change. With a foe already visible, a click takes at most one step. Click the hero to wait.
- Click a visible enemy to use the first bound, available targeted attack in the shown set that can reach it. An adjacent foe can receive a bump attack if no slot qualifies. Click a nearby chest, bag or door to interact with that object.
- Click a skill to activate it, then confirm a reticle on the map or right-click to cancel. For walls, press on the first endpoint, drag and release on the second. HUD clicks stay within the HUD. Click the modifier slot to toggle sets or wheel over a slot (down for secondary, up for primary). Pad input clears the mouse toggle.
- Bottom-right Character/Menu actions appear for keyboard/mouse. Right-click in play opens Game. Select items, nodes or bindings with one click, then click their action. On Passives, wheel zooms, middle-drag pans and Overview resets both. Loot has Take item and Take all. The death action becomes available after the lethal turn finishes. [Loot transactions](PROGRESSION.md#equipment-and-loot)

## Editor and verification

The editor uses keyboard and mouse. Paint/erase, wheel zoom, middle-drag pan and right-click dismissal share the canvas with clickable Copy/Cut/Paste/Clear/Fit. Play here and Go through arm the next map click and cancel on right-click. In Objects, Fight or Enter tests the selected foe in an arena. Pause returns to the unchanged editor, and retry or Restart Map resets the fight. Editor help uses whole measured glyphs from [prompt_text.zig](../src/gfx/prompt_text.zig).

`--shot-ui` covers Character, trees, loot, HUD and binding. Physical controller behavior requires a connected pad. [Verification](../AGENTS.md#verification)
