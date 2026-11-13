# Controller

The controller is primary; keyboard and mouse mirror its actions.
`src/core/input.zig` alone polls devices. Binding tables, glyph names and repeat
behavior live in `input_bindings.zig`, `input_names.zig` and `input_repeat.zig`.

## Devices and options

Options > Visuals and Pause > Options > Visuals share effect sliders. Vertical navigation selects a
row; horizontal navigation adjusts it in 5% steps. Confirm switches between a
neutral/default value and a sample strength, Change resets the selected value,
and Reset to defaults restores the visual preset. Set all to 0 zeros every slider.
Display settings (fullscreen, VSync, frame limit) are in Options > Display.
Mouse users can drag the rails,
including beyond their ends to reach the limits, and scroll through the list.

No screen names a key or button in prose. Control hints use glyphs throughout, including the editor.
The skill bar and bind screen show each slot's input as an icon of the
device last pressed (`State.device`, `prompt_icon.Prompt`): any gamepad button or the stick pushed past walking makes it the
pad; any key, mouse movement, mouse button or wheel motion selects keyboard/mouse hints. A stationary cursor leaves controller navigation alone, and no pad plugged in is always the keyboard. HUD tooltips spend no turn.

GLFW maps every pad onto Xbox's buttons by place, so the table names Xbox's. A Sony pad (vendor `054c` in the
joystick's GUID, `input.padOf`) shows PlayStation's icons instead: Cross A, Circle B, Square X, Triangle Y, L1/R1 the
bumpers, L2/R2 the triggers. The right-stick click (RS/R3) opens Inspect. The left-stick click and
PS button do nothing; GLFW reads no touchpad.

- **Mappings** (`input.mapPads`): `assets/data/gamecontrollerdb.txt` is SDL_GameControllerDB at commit `c1d5289`
  (zlib, `assets/data/gamecontrollerdb-LICENSE`), embedded to supplement GLFW's mappings. `SDL_GAMECONTROLLERCONFIG`, then a `gamecontrollerdb.txt` beside the exe, take over the pads they
  name, so a new pad needs no rebuild. To update, replace the asset from the repo's `gamecontrollerdb.txt`.
- **Which pad**: the first of raylib's four slots that GLFW has a mapping for, until another pad presses a button or
  pulls a trigger past its latch (`input.choosePad`). A wheel or an unmapped joystick is passed over.
- **Queued input**: movement, skills and interactions asked for while the last turn is still drawn run once it is quiet;
  the latest wins, except that a held walk repeating does not displace a queued skill or interaction.
  With a visible foe nearby (the same check that suppresses automatic chest opening), only inputs in the
  final 120 ms of the turn are buffered, including mouse map clicks; earlier inputs are discarded.
  Interactions queued during door travel open the nearby menu after arrival.
- **Focus**: play input is cleared while the window is out of focus, including unsettled taps and queued actions;
  the current turn's presentation finishes without spending another turn. Device icons are retained, and trigger
  latches keep polling so a held trigger does not register a new press on return.
- **Triggers** press past 60% of their travel and let go under 40% (`input.TRIGGER_ON`/`OFF`), not raylib's one line
  at 55%, so a finger resting on RT does not fire its slot over and over.

## Bindings

| Action | Pad | Keyboard |
|---|---|---|
| Move | D-pad, left stick | WASD, arrows, numpad |
| Diagonal | hold LT + d-pad | hold Shift + WASD/arrows, two keys at once, numpad 1 3 7 9 |
| Skill slots | LB, A, X, Y, B, RB, RT | 1 on, left to right, skipping the modifier's slot |
| Secondary skill set | hold the slot bound to it (LB) | hold Ctrl |
| Character | Start / Menu / Options | Tab |
| Game menu (from play) | Select / View / Share / Create | Esc |
| Character tabs | LB / RB, or left / right on the tabs | Q / E, or arrows on the tabs |
| Character page back to its tabs, then closed | B | Esc |
| Equipment / Inventory / Stats / Passives / Skills / Quests directly | Character tabs | F1 / F2 / F3 / F4 / F5 / F7 |
| Skills: bind selected skill | X | C |
| Stats: advanced / main sheet | X | C |
| Inventory: equip / drop / change ring | A / Y / X | Enter / Del / C |
| Inspect HUD (from play) | Right-stick click (RS/R3) | I |
| Get out (reticle, binds, menus, pause) | B | X or Esc (Esc alone in play) |
| Confirm, select | A | Enter, Space or Z |
| Interact in play | A / Cross | Enter or Space |
| Talk to NPCs | walk into them, or Interact beside them | walk into them, Enter or Space beside them |
| Conversation: choose, go on | D-pad up/down, A | arrows/WS, Enter, Space or Z; or click a reply/Continue (no back-out) |
| Scroll event log | Inspect log, up/down | Wheel over log, or Inspect then up/down |
| Bind screen: change, remove | X, Y | C, Del |
| Passive tree: browse | Left stick, actual bearing | WASD, arrows, numpad |
| Passive tree: pan | Right stick | Shift + WASD/arrows/numpad |
| Passive tree: zoom | D-pad up/down; X/Y steps | =/-, keypad +/-, Page Up/Down; C/Del steps |
| Passive tree: overview | Right-stick click | Home |
| Delete a save | Y | Del |
| Fullscreen | Options > Display > Fullscreen | Alt+Enter, or Options |
| Name the hero | walk the letter grid, A types, X deletes | type it; Backspace deletes, Enter is done |

Class kits and template bindings live in `skillbar`; `progress.State` filters new-run defaults and the bind picker to learned skills.
With the default LB modifier, the keyboard uses Ctrl, then 1 to 6 for A, X, Y, B, RB, RT.

## Mouse

Arcane Barrier and Fire Wall use two ordinary targeting confirmations for their endpoints. With the
mouse, press on the first endpoint, drag to preview the straight line and release to
confirm the second. Cancel discards the whole preview without spending mana or a turn.
Overwatch uses normal targeting to choose the direction of its covered cone.

- Click a menu row to activate it; the wheel browses long lists. Right-click or the visible Back/Close action goes back one layer. The name grid accepts clicks on letters, Space, Delete and Done. Each occupied save row has its own Delete action, requiring a second deliberate press on the same slot.
- Click explored ground to walk there by a known route. Routes avoid walls, known barrels, visible gas and intermediate doors. Movement waits for each turn to finish and stops at the destination, on visible enemies, damage, another action, focus loss or a screen/level change. With a foe already visible, a ground click takes at most one step. Clicking the hero waits one turn.
- Click a visible foe to use the first bound targeted attack in the shown skill set that can reach it; an adjacent foe can be bumped when no bound attack reaches it. Click a nearby chest, bag or door to interact with that specific object. Existing visibility, costs and turn rules apply.
- Click a HUD skill to activate it. A targeted skill previews under the pointer; click the map to confirm and right-click to cancel. Clicking a HUD panel never confirms a map target. Click the modifier slot to toggle the secondary set, or wheel over a slot (down for secondary, up for primary). Returning to a controller clears the mouse toggle.
- Character and Menu buttons sit in the bottom-right gutter with keyboard/mouse hints. Right-click during play also opens the game menu. Character tabs, shoulder arrows, equipment, inventory, loot, tree actions and binding controls accept clicks. Click an item, skill, passive node or binding slot to select it; moving toward its action button preserves that selection. The wheel scrolls lists and the event log.
- On Passives, wheel to zoom and drag with the middle button to pan; release stops the drag. The visible Overview action resets zoom and pan. Selection, pan and zoom spend no points. Use the visible allocation or upgrade action to spend one point.
- The death screen's action is clickable once the lethal turn finishes. The editor retains paint/erase, wheel zoom and middle-drag pan, with clickable Copy/Cut/Paste/Clear/Fit controls and right-click to close modals. Play here (top bar) and Go through (Doors tab) arm the next map-cell click; right-click cancels. These actions neither paint nor change the map.

## Interaction contracts

- **Everything is slots.** On the pad a slot is its button. On the keyboard it is a number (`input.SLOT_ORDER`), and
  the slot holding "Activate Secondary Skill Set" is Ctrl instead, so moving the modifier renumbers the rest. The bar
  and bind screen show whichever the device is, as icons.
- **Menus and targeting have their own keys.** In play the numbers, Ctrl, Tab, Esc and I handle skills and screens (`State.context`); Enter and Space interact with visible objects underfoot or adjacent, while menu letters never fire a slot. While a name is typed the letters and Space type, so
  Enter is done there. Esc gets out of whatever is open, a step at a time.
- **Target once, then confirm or back out.** A (Cross), Enter, Space or Z confirms a target; B (Circle), Select, X or
  Esc cancels. On the keyboard the skill's own number confirms too (1, then 1); on the pad pressing the skill again
  does not confirm it unless that button is also the standard confirm. B always cancels, even when it opened the skill. Secondary skills keep their selected set after the modifier is released.
- **Smart aim** keeps the previously selected enemy while it remains alive, visible and legal for the chosen skill,
  following it when it moves. Otherwise the reticle selects the nearest legal visible enemy. From a selected enemy,
  directional input cycles to a legal visible enemy within 45 degrees of the pressed direction, measured from the
  reticle, without wrapping. With no candidate in that direction, the reticle moves freely using the skill's normal
  movement and range limits. Free aim stays free until the reticle lands on a legal enemy again; suggestions never
  pull it back from empty ground. This applies to projectile, melee and rush targeting.
  Projectile aiming opens without an enemy and accepts empty or dark cells within range and geometric line of sight.
  Previews and automatic suggestions ignore unseen bodies and barrels. If the preview has no visible target, the first
  confirmation asks without spending a turn or mana; confirming again at the same cell fires. Nonpiercing flight stops
  at the first collision, including unseen interceptors.
  Leap destinations remain freely aimed. Selecting or replacing a target spends nothing and never fires automatically;
  the normal confirmation is still required. A direct mouse click on an enemy is explicit targeting and confirmation.
  Target memory clears on level changes, restarts and save loads.
- **Character and Game are separate.** Start opens Character inside its last page; another Start press closes Character. Selecting a tab enters it immediately. F1–F5 and F7 open the corresponding Character page, switch pages directly, and close an already open matching page. Their glyphs appear on the tabs when using the keyboard. These shortcuts cancel an unconfirmed reticle and spend no turn. Select opens the game menu. From Character on a pad, Select switches to Game. Escape backs out from Character and opens Game only from play. There is no hidden hold gesture.
- **Binding belongs to Skills.** Its bind action carries a learned skill to the slot screen; select a destination and confirm once. Back returns to Skills. The picker remains available for utility skills and the secondary-set modifier. Clearing a slot is direct. Binding spends no turn.
- **Pause > Debug** groups controls into Gameplay (Restart Map, Reveal Map, Unkillable), Lighting
  (Composed Lighting, Shadows, Body Lighting, Effect Lights), Effects (Bloom, Atmosphere, Depth Of Field,
  Water Reflections, Water Glints, Weather), and Diagnostics. Display settings live in Options > Display.
  Diagnostics shows the active OpenGL vendor/renderer/version, window and framebuffer size, build mode,
  and FPS/CPU timing; its performance overlay can be toggled. CPU timing excludes frame pacing and is
  not GPU timing. Frame Limit cycles through uncapped, 30, 60, 120 and 144 FPS; VSync can cap it further.
  Visual effects default on. Debug settings last for the application session and are not saved.
  Reveal changes neither normal sight nor saved exploration. Back returns one submenu at a time,
  retaining the parent selection, before returning to Pause.
- **Character** contains equipment, inventory, stats, shared passives and class skills. Shoulders / Q and E change pages from anywhere. Clicking a tab enters its content. Back returns from page content to the tabs, then closes Character from the tabs. Equip, unequip, drop and point allocation each take one deliberate action; no action submenu or confirmation modal. Rings have an explicit destination switch and the comparison follows that destination. Successful item actions keep the screen open and still spend one turn. Point allocation is free of simulation turns. The underlying inventory/progression transactions remain authoritative.
- Loot opening, gold collection and turn accounting follow
  [PROGRESSION.md](PROGRESSION.md#inventory-and-loot-transactions).
  Loot offers Take item on confirm and Take all on change, with glyphs and clickable
  buttons. Busy input waits for the current turn or door travel.
- **Inspect** walks visible onscreen characters, the life orb, skill slots, mana orb, active statuses and event log without spending a turn.
  Underlined keywords have their own inspection layer: hover a word, or press
  Inspect again while terms are visible to focus them. Directional input moves
  among the words; Back or Inspect returns to the unchanged underlying card or
  menu. Advanced Stats exposes the status groups even without active ailments.
  Every unit card shows only its name (title case for foes, the hero's own name) and pictured HP, then a divider and the tile with its signed effects.
  Page controls and the mouse wheel scroll long cards. The
  log scrolls up/down while selected; move sideways to leave it. B, Select or
  another right-stick click closes it; keyboard X, Esc or I does the same. Holding the modifier (or Ctrl) shows the
  secondary set's slots there too (`State.sets`).
- **The editor is a desk tool** (`input.Desk`): keyboard and mouse only, by design.
  Its help, tooltips, status messages, tool shortcuts and modal shortcuts use the same keycap and
  mouse glyph styles as the game. `gfx/prompt_text.zig` measures and clips marked captions as whole glyphs.
  In Objects, select a foe and choose Fight (or Enter) to test it in an arena. The pause menu returns to the
  unchanged editor; death retry or Debug > Gameplay > Restart Map resets the fight.

## Verification

Mapping/state tests and rendered captures do not substitute for physical controller
testing. Use `--shot-ui` for Character, loot, HUD and binding, and `--shot-trees`
for trees, following [AGENTS.md](../AGENTS.md#verification). Keep previews in TEMP.
