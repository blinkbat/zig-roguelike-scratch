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
- **No live switching between pad and keyboard.** PoE2 picks its control mode at the menu, and prompts stay in it
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
device last pressed (`State.device`, `look.Prompt`): any gamepad button or the stick pushed past walking makes it the
pad, any key the keyboard, and no pad plugged in is always the keyboard. This is where we go past PoE2, after Diablo
IV. Hovering over the HUD shows a tooltip without changing the device icons or spending a turn.

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
| Bind screen | hold View (`input.HOLD_S`, 0.4 s) | hold Tab |
| Pause (from play) | Menu | Esc |
| Inspect HUD (from play) | Right-stick click (RS/R3) | I |
| Get out (reticle, binds, menus, pause) | B or Menu | X or Esc (Esc alone in play) |
| Confirm, select | A | Enter, Space or Z |
| Interact in play | A / Cross | Enter or Space |
| Scroll event log | Inspect log, up/down | Wheel over log, or Inspect then up/down |
| Bind screen: change, remove | X, Y | C, Del |
| Passive tree: browse | Left stick, actual bearing | WASD, arrows, numpad |
| Passive tree: pan | Right stick | Shift + WASD/arrows/numpad |
| Passive tree: zoom | D-pad up/down; X/Y steps | +/-, keypad +/-, Page Up/Down; C/Del steps |
| Passive tree: overview | Right-stick click | Home |
| Delete a save | Y | Del |
| Fullscreen | Options > Fullscreen | Alt+Enter, or Options |
| Name the hero | walk the letter grid, A types, X deletes | type it; Backspace deletes, Enter is done |

Class kits and template bindings live in `skillbar`; `progress.State` filters new-run defaults and the bind picker to learned skills.
With the default LB modifier, the keyboard uses Ctrl, then 1 to 6 for A, X, Y, B, RB, RT.

- **Everything is slots.** On the pad a slot is its button. On the keyboard it is a number (`input.SLOT_ORDER`), and
  the slot holding "Activate Secondary Skill Set" is Ctrl instead, so moving the modifier renumbers the rest. The bar
  and bind screen show whichever the device is, as icons.
- **Menus and targeting have their own keys.** In play the numbers, Ctrl, Tab, Esc and I handle skills and screens (`State.context`); Enter and Space interact with visible objects underfoot or adjacent, while menu letters never fire a slot. While a name is typed the letters and Space type, so
  Enter is done there. Esc gets out of whatever is open, a step at a time.
- **Target once, then confirm or back out.** A (Cross), Enter, Space or Z confirms a target; B (Circle), Menu, X or
  Esc cancels. On the keyboard the skill's own number confirms too (1, then 1); on the pad pressing the skill again
  does not confirm it unless that button is also the standard confirm. B always cancels, even when it opened the skill. Secondary skills keep their selected set after the modifier is released.
- **Hold View for binds, no radial.** A tap of View does nothing in play. A press of View that closes the bind screen or
  cancels a reticle is spent (`State.spend`), so holding it on does not open the binds again.
- **Menu taps to pause** from play, as PoE2's taps to the inventory; anywhere else it backs out, as Esc does.
- **Pause > Debug** contains Restart Map and Reveal Map. Reveal shows terrain and the minimap without changing
  normal sight or saved exploration; switching it off restores the normal view. Back exits Debug to Pause first.
- **Pause > Character** opens equipment, the inventory list, stats, shared passives and class skills. Move left/right
  across tabs, down into content, or click a row/node. Back exits the current confirmation/action/content layer first,
  then returns to Pause. Equipment uses the inspected D2 paperdoll; item details show worn/item/delta columns.
  Item changes require a separate Cancel-first confirmation and spend one turn; point allocation spends points.
  The passive tree opens at 2.2x on the class origin. Its controls follow the Soulslike reference:
  left-stick bearing selects nodes, right stick pans, and D-pad up/down zooms continuously.
  Shift turns keyboard navigation into pan; +/-, keypad +/-, and Page Up/Down zoom.
  X/Y and C/Delete retain stepped zoom. Mouse wheel over the tree works even while tabs have focus,
  and its plus/minus controls also zoom. Right-stick click or Home returns to the full overview.
  Directional node selection recenters the view; reaching a tree edge keeps focus on the tree.
  Back returns to tabs without allocating anything. Pan and zoom never spend points or turns.
- **Interact** opens a list of visible items, chests and doors on the hero's cell or adjacent cells. Selecting an entry
  opens a Cancel-first confirmation; browsing and canceling are free. A / Cross prioritizes nearby interaction over
  its skill binding. Gold collects automatically when stepping or arriving onto it.
- **Inspect** walks the life orb, skill slots, mana orb, active statuses and event log without spending a turn. The
  log scrolls up/down while selected; move sideways to leave it. B, Menu or
  another right-stick click closes it; keyboard X, Esc or I does the same. Holding the modifier (or Ctrl) shows the
  secondary set's slots there too (`State.sets`).
- **The editor is a desk tool** (`input.Desk`): keyboard and mouse only, by design.
  Its help, tooltips, status messages, tool shortcuts and modal shortcuts use the same keycap and
  mouse glyph styles as the game. `gfx/prompt_text.zig` measures and clips marked captions as whole glyphs.
  In Objects, select a foe and choose Fight (or Enter) to test it in an arena. The pause menu returns to the
  unchanged editor; death retry or Debug > Restart Map resets the fight.
