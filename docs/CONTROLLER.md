# Controller

The controller is the primary input; the keyboard mirrors it. Path of Exile 2's controller scheme is the high-water
mark. Everything that touches a device is `src/core/input.zig`.

## Path of Exile 2

What PoE2 does, from player reports and guides (late 2024 to 2025; no official map was found, so check in game):

- **Skills sit on buttons, not a numbered bar.** Face buttons, bumpers and triggers each hold a skill. A second set
  is used while a modifier is held, a shoulder by default (reports say LB; some say LT), and the modifier can be
  rebound or made a toggle. Dodge roll is B.
- **Binding is a screen of slots.** Pick a slot, then the skill for it; or pick a skill and press the button to put it
  on. The secondary-set modifier is itself a bindable slot ("Activate Secondary Skill Set").
- **Held buttons open menus.** Holding View (PS: touchpad) opens a radial; its 6 o'clock entry is the bind screen.
  Holding Menu (inventory) is also reported to reach rebinding. A tap of Menu opens the inventory.
- **Historical reports of no live switching between pad and keyboard.** PoE2 picks its control mode at the menu, and prompts stay in it
  until restart; players ask for the Diablo IV / Baldur's Gate 3 behaviour, where prompts follow whatever was last
  touched.

Sources: [Steam: hold back for the mini menu](https://steamcommunity.com/app/2694490/discussions/0/594008672803383278),
[Steam: hold select, bottom of the radial](https://steamcommunity.com/app/2694490/discussions/0/598513665563476233),
[PoE forum: toggle secondary skill set](https://www.pathofexile.com/forum/view-thread/3892566),
[Keymap Labs](https://keymap.io/controls/path-of-exile-2/),
[Game8: dodge](https://game8.co/games/Path-of-Exile-2/archives/490382),
[Deltia's: binding skills](https://deltiasgaming.com/?p=95876),
[Steam: no on-the-fly switching](https://steamcommunity.com/app/2694490/discussions/0/598513772173271367),
[PoE forum: simultaneous inputs](https://www.pathofexile.com/forum/view-thread/3673537).

## Ours

No screen names a key or button in prose. Control hints use glyphs throughout, including the editor.
The skill bar and bind screen show each slot's input as an icon of the
device last pressed (`State.device`, `prompt_icon.Prompt`): any gamepad button or the stick pushed past walking makes it the
pad; any key, mouse movement, mouse button or wheel motion selects keyboard/mouse hints. A stationary cursor leaves controller navigation alone, and no pad plugged in is always the keyboard. This behavior is deliberate; the dated reports above do not establish the latest PoE2 client. HUD tooltips spend no turn.

GLFW maps every pad onto Xbox's buttons by place, so the table names Xbox's. A Sony pad (vendor `054c` in the
joystick's GUID, `input.padOf`) shows PlayStation's icons instead: Cross A, Circle B, Square X, Triangle Y, L1/R1 the
bumpers, L2/R2 the triggers. The right-stick click (RS/R3) opens Inspect. The left-stick click and
PS button do nothing; GLFW reads no touchpad.

- **Mappings** (`input.mapPads`): `assets/gamecontrollerdb.txt` is SDL_GameControllerDB at commit `c1d5289`
  (2026-10-02, zlib, `assets/gamecontrollerdb-LICENSE`), embedded and newer than the copy GLFW ships (which lacks the
  DualSense Edge). `SDL_GAMECONTROLLERCONFIG`, then a `gamecontrollerdb.txt` beside the exe, take over the pads they
  name, so a new pad needs no rebuild. To update, replace the asset from the repo's `gamecontrollerdb.txt`.
- **Which pad**: the first of raylib's four slots that GLFW has a mapping for, until another pad presses a button or
  pulls a trigger past its latch (`input.choosePad`). A wheel or an unmapped joystick is passed over.
- **Queued input**: movement, skills and interactions asked for while the last turn is still drawn run once it is quiet;
  the latest wins, except that a held walk repeating does not displace a queued skill or interaction.
  Interactions queued during door travel open the nearby menu after arrival.
- **Focus**: play input is cleared while the window is out of focus, including unsettled taps and queued actions;
  the current turn's presentation finishes without spending another turn. Device icons are retained, and trigger
  latches keep polling so a held trigger does not register a new press on return.
- **Triggers** press past 60% of their travel and let go under 40% (`input.TRIGGER_ON`/`OFF`), not raylib's one line
  at 55%, so a finger resting on RT does not fire its slot over and over.

| Action | Pad | Keyboard |
|---|---|---|
| Move | D-pad, left stick | WASD, arrows, numpad |
| Diagonal | hold LT + d-pad | hold Shift + WASD/arrows, two keys at once, numpad 1 3 7 9 |
| Skill slots | LB, A, X, Y, B, RB, RT | 1 on, left to right, skipping the modifier's slot |
| Secondary skill set | hold the slot bound to it (LB) | hold Ctrl |
| Character | Start / Menu / Options | Tab |
| Game menu (from play) | Select / View / Share / Create | Esc |
| Character tabs | LB / RB | Q / E |
| Equipment / Inventory / Stats / Passives / Skills directly | Character tabs | F1 / F2 / F3 / F4 / F5 |
| Skills: bind selected skill | X | C |
| Stats: advanced / main sheet | X | C |
| Inventory: equip / drop / change ring | A / Y / X | Enter / Del / C |
| Inspect HUD (from play) | Right-stick click (RS/R3) | I |
| Get out (reticle, binds, menus, pause) | B | X or Esc (Esc alone in play) |
| Confirm, select | A | Enter, Space or Z |
| Interact in play | A / Cross | Enter or Space |
| Scroll event log | Inspect log, up/down | Wheel over log, or Inspect then up/down |
| Bind screen: change, remove | X, Y | C, Del |
| Passive tree: browse | Left stick, actual bearing | WASD, arrows, numpad |
| Passive tree: pan | Right stick | Shift + WASD/arrows/numpad |
| Passive tree: zoom | D-pad up/down; X/Y steps | =/-, keypad +/-, Page Up/Down; C/Del steps |
| Passive tree: overview | Right-stick click | Home |
| Delete a save | Y | Del |
| Fullscreen | Options > Fullscreen | Alt+Enter, or Options |
| Name the hero | walk the letter grid, A types, X deletes | type it; Backspace deletes, Enter is done |

Class kits and template bindings live in `skillbar`; `progress.State` filters new-run defaults and the bind picker to learned skills.
With the default LB modifier, the keyboard uses Ctrl, then 1 to 6 for A, X, Y, B, RB, RT.

### Mouse

Arcane Barrier uses two ordinary targeting confirmations for its endpoints. With the
mouse, press on the first endpoint, drag to preview the straight wall and release to
confirm the second. Cancel discards the whole preview without spending mana or a turn.
Overwatch uses normal targeting to choose the direction of its covered cone.

- Click a menu row to activate it; the wheel browses long lists. Right-click or the visible Back/Close action goes back one layer. The name grid accepts clicks on letters, Space, Delete and Done. Each occupied save row has its own Delete action, requiring a second deliberate press on the same slot.
- Click explored ground to walk there by a known route. Routes avoid walls, known barrels, visible gas and intermediate doors. Movement waits for each turn to finish and stops at the destination, on visible enemies, damage, another action, focus loss or a screen/level change. With a foe already visible, a ground click takes at most one step. Clicking the hero waits one turn.
- Click a visible foe to use the first bound targeted attack in the shown skill set that can reach it; an adjacent foe can be bumped when no bound attack reaches it. Click a nearby chest, bag or door to interact with that specific object. Existing visibility, costs and turn rules apply.
- Click a HUD skill to activate it. A targeted skill previews under the pointer; click the map to confirm and right-click to cancel. Clicking a HUD panel never confirms a map target. Click the modifier slot to toggle the secondary set, or wheel over a slot (down for secondary, up for primary). Returning to a controller clears the mouse toggle.
- Character and Menu buttons sit in the bottom-right gutter with keyboard/mouse hints. Right-click during play also opens the game menu. Character tabs, shoulder arrows, equipment, inventory, loot, tree actions and binding controls accept clicks. Click an item, skill, passive node or binding slot to select it; moving toward its action button preserves that selection. The wheel scrolls lists and the event log.
- On Passives, wheel to zoom and drag with the middle button to pan; release stops the drag. The visible Overview action resets zoom and pan. Selection, pan and zoom spend no points. Use the visible allocation or upgrade action to spend one point.
- The death screen's action is clickable once the lethal turn finishes. The editor retains paint/erase, wheel zoom and middle-drag pan, with clickable Copy/Cut/Paste/Clear/Fit controls and right-click to close modals. Play here and Go through in its status bar arm the next map-cell click; right-click cancels. These actions neither paint nor change the map.

- **Everything is slots.** On the pad a slot is its button. On the keyboard it is a number (`input.SLOT_ORDER`), and
  the slot holding "Activate Secondary Skill Set" is Ctrl instead, so moving the modifier renumbers the rest. The bar
  and bind screen show whichever the device is, as icons.
- **Menus and targeting have their own keys.** In play the numbers, Ctrl, Tab, Esc and I handle skills and screens (`State.context`); Enter and Space interact with visible objects underfoot or adjacent, while menu letters never fire a slot. While a name is typed the letters and Space type, so
  Enter is done there. Esc gets out of whatever is open, a step at a time.
- **Target once, then confirm or back out.** A (Cross), Enter, Space or Z confirms a target; B (Circle), Select, X or
  Esc cancels. On the keyboard the skill's own number confirms too (1, then 1); on the pad pressing the skill again
  does not confirm it unless that button is also the standard confirm. B always cancels, even when it opened the skill. Secondary skills keep their selected set after the modifier is released.
- **Smart aim** keeps the previously selected enemy while it remains alive, visible and legal for the chosen skill,
  following it when it moves. Otherwise the reticle selects the nearest legal visible enemy. Directional input
  selects another legal enemy in that direction; with none there, the existing cell or swing-direction controls apply.
  Leap destinations remain freely aimed. Selecting or replacing a target spends nothing and never fires automatically;
  the normal confirmation is still required. A direct mouse click on an enemy is explicit targeting and confirmation.
  Target memory clears on level changes, restarts and save loads.
- **Character and Game are separate.** Start opens Character directly on its last page, already focused on content; another press closes it. F1–F5 open the corresponding Character page, switch pages directly, and close an already open matching page. Their glyphs appear on the tabs when using the keyboard. These shortcuts cancel an unconfirmed reticle and spend no turn. Select opens the game menu. From Character on a pad, Select switches to Game. Escape backs out from Character and opens Game only from play. There is no hidden hold gesture.
- **Binding belongs to Skills.** Its bind action carries a learned skill to the slot screen; select a destination and confirm once. Back returns to Skills. The picker remains available for utility skills and the secondary-set modifier. Clearing a slot is direct. Binding spends no turn.
- **Pause > Debug** groups controls into Gameplay (Restart Map, Reveal Map, Unkillable), Lighting
  (Composed Lighting, Shadows, Body Lighting, Effect Lights), Effects (Bloom, Atmosphere, Depth Of Field,
  Water Reflections, Water Glints, Weather), Display (Fullscreen, VSync, Frame Limit), and Diagnostics.
  Diagnostics shows the active OpenGL vendor/renderer/version, window and framebuffer size, build mode,
  and FPS/CPU timing; its performance overlay can be toggled. CPU timing excludes frame pacing and is
  not GPU timing. Frame Limit cycles through uncapped, 30, 60, 120 and 144 FPS; VSync can cap it further.
  Visual effects default on. Debug settings last for the application session and are not saved.
  Reveal changes neither normal sight nor saved exploration. Back returns one submenu at a time,
  retaining the parent selection, before returning to Pause.
- **Character** contains equipment, inventory, stats, shared passives and class skills. Shoulders / Q and E change pages from anywhere. Clicking a tab enters its content. Back closes Character in one step. Equip, unequip, drop and point allocation each take one deliberate action; no action submenu or confirmation modal. Rings have an explicit destination switch and the comparison follows that destination. Successful item actions keep the screen open and still spend one turn. Point allocation is free of simulation turns. The underlying inventory/progression transactions remain authoritative.
- The passive tree starts zoomed in, at `trees.ZOOM_START`. Left-stick bearing browses, right stick pans, D-pad up/down zooms. Shifted keyboard navigation pans; =/-, keypad +/- and Page Up/Down zoom; right-stick click / Home gives the overview. Pan and zoom never allocate points.
- **Interact** or a first bump opens a closed chest for one turn, revealing its items and gold without opening a panel. Stepping onto a loose bag or stocked open chest opens loot for the movement turn; bags stay walkable even when loot is left behind. Ground gold without items uses a coin drop and auto-loots when stepped onto, with no extra turn or modal. Gold with items shares their bag. Interact browses a sole visible bag/open chest within reach for free, or takes a sole coin drop for one turn. Multiple nearby drops/containers/doors first offer a choice; selecting an entry affects only that cell. Doors always keep a choice, preventing queued input from immediately returning through an arrival door. Loot offers Take item or Take gold for the selected row through the confirm control and Take all through the change control, with device glyphs and clickable buttons. Each successful pickup action takes one turn; Take all collects gold, fills available inventory space and leaves excess items. Gold needs no inventory space. The modal closes when empty. Busy input waits for the current turn or door travel. Movement and browsing never collect gold from bags or chests.
- **Inspect** walks the life orb, skill slots, mana orb, active statuses and event log without spending a turn. The
  log scrolls up/down while selected; move sideways to leave it. B, Select or
  another right-stick click closes it; keyboard X, Esc or I does the same. Holding the modifier (or Ctrl) shows the
  secondary set's slots there too (`State.sets`).
- **The editor is a desk tool** (`input.Desk`): keyboard and mouse only, by design.
  Its help, tooltips, status messages, tool shortcuts and modal shortcuts use the same keycap and
  mouse glyph styles as the game. `gfx/prompt_text.zig` measures and clips marked captions as whole glyphs.
  In Objects, select a foe and choose Fight (or Enter) to test it in an arena. The pause menu returns to the
  unchanged editor; death retry or Debug > Gameplay > Restart Map resets the fight.

## Binding and glyph audit, 2026-10-20

The second pass checked play, targeting, Character, both trees, binding, Inspect, naming, title/options, save deletion and the desk editor. The defaults remain controller-first, with keyboard mirrors. Targeting still needs an explicit commit because it spends a roguelike turn; menus do not add another confirmation after that choice. Save deletion retains its second press because it destroys a run.

| Finding | Fix |
|---|---|
| Character buried in Pause; bind screen hidden behind a hold | Separate Start/Select entry points, binding in Skills |
| Four confirmations to equip, multiple back layers | One direct command, one back to play; gear screen stays open |
| Tab navigation steals content focus | Shoulder/Q/E page switching; list and node navigation stay in content |
| Direction held through page changes moves the new cursor | Consume carried navigation on page changes |
| Tiny fixed book | Window-scaled panels, larger body/detail type, matching hit regions and tree clipping |
| Old icons survived the button remapping | `Prompt.of` derives from `Button.pad`; Xbox Menu/View and Sony Options/Share/Create checked |
| Keyboard back looked like an arbitrary letter | Escape is the primary back glyph; X remains an alias |
| Binding actions and mouse targets unclear | Explicit glyph actions, direct selected-skill assignment, scaled mouse targets and wrapped descriptions |
| Clicking UI left controller hints active | Mouse movement, buttons and wheel select keyboard/mouse prompts; a stationary cursor leaves controller selection alone |
| Queued interaction could bounce through a door | Direct opening limited to sole bags/chests; doors keep their choice |

[D2R's console account](https://news.blizzard.com/en-us/article/23722094/bringing-the-original-diablo-ii-experience-to-console) supports direct skill trays and adapting interaction to the device. GGG's [PoE2 0.1.1c notes](https://webcdn.pathofexile.com/forum/view-thread/3717308) explicitly cover controller font enlargement, item navigation, dedicated interface-confirm bindings, advanced item information and a full-inventory weapon-swap fix. The useful comparison is direct access, readable consequences, consistent device hints and intact transactions. These are dated primary sources, not claims about every present-day default.

Mapping/state tests and rendered captures do not substitute for a physical controller play session. `--shot-ui` captures Character, loot, HUD and level-up studies without rerunning the map/effect studies; run it from a temporary working directory as with `--shot`.
