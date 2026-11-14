# AGENTS.md — Cistern

Grid roguelike and map editor in **Zig 0.14.1 + raylib**. Paths below are repository-relative unless stated otherwise.

## UI restraint — foundational requirement

- Implement the UI the user requests. Do not invent visible additions because they seem helpful.
- Do not add labels, headings, buttons, control hints, explanatory text, extra entry points or duplicate information unless explicitly requested. If an unrequested addition seems necessary, ask before implementing it.
- Take the request literally: adding tags means showing the tag words, not a "Tags:" label. Adding hover/controller inspection does not authorize on-screen controller or Back hints.
- Keep necessary behavior working without narrating it in the UI. Reuse established interactions. Do not add a tutorial, legend, glossary section or extra menu to explain a requested feature unless asked.
- Avoid clutter and repetition, weak readability or visual hierarchy, and unnecessary steps, menus or popups. None of these is an acceptable tradeoff to make silently; ask when a real design tradeoff arises.
- Stacked panels must become more opaque toward the top so underlying text cannot compete with the content being read.
- Review every visible addition before handoff: identify the user request that authorizes it; remove additions without one. This is a foundational UI constraint, not an optional preference.

## Working rules

- Preserve unrelated/uncommitted work. Ask before product/design decisions. Do not commit, push or branch unless asked.
- Prefer no code comments. Keep this file a short index; maintain detailed contracts in the relevant docs and balance values in source.
- Windows/PowerShell: use `login: false`, UTF-8 without BOM and targeted patches. Do not change execution policy.
- No scratch files in the repo, including ignored `shots/` or `output/`. Use `%TEMP%` for previews, logs, backups and scripts. Normal build/cache directories and the owner's `assets/backup/` are exceptions.

## Verification

Run from the repository root; wrappers select and verify Zig 0.14.1. Setup: [README.md](README.md).

- `./check.cmd`: type-check executable and tests. `./test.cmd [filter]`: run affected tests; run the full suite for combat, scheduling or lifecycle changes.
- `./build.cmd`: Debug build without launching; finish code/art handoffs with it. If the executable is locked, use `--prefix zig-out-dev`. Release: `./build-release.cmd`.
- Never launch interactive play for verification. `run.cmd`/`edit.cmd` are owner-facing and kill existing `cistern.exe` processes.
- Tests must not write saves/maps. Full procgen tests take minutes; check CPU before declaring a stall. Keep the direct test runner in `build.zig`: raylib stdout deadlocks Zig's `--listen=-` test protocol.
- Every `src/**/*.zig` except `main.zig` must appear in its `test {}` imports. Builds reject invalid syntax and modules without declarations, and enforce dependency boundaries through `tools/source_rules.zig`.
- For visual changes, inspect actual headless PNGs. Build into `zig-out-dev`; copy `maps/` and the executable (with a distinct basename) into a fresh `%TEMP%` directory, then run there. Captures write `shots/` under the working directory; do not run `shot.cmd` from the repo.
- Capture flags: `--shot` (general/maps), `--shot-ui`, `--shot-editor`, `--shot-debug`, `--shot-trees`, `--shot-water-cliffs`, `--shot-cinema`, `--shot-zoo`; `--bench` measures CPU/draw/resource costs. Coverage lives in `src/game/shots/` (`--shot` in `poses.zig`, `--shot-ui`/`--shot-editor` in `ui.zig`, otherwise one file per flag; shared helpers in `capture.zig`), dispatch in `src/app.zig`.

## Task routing

Read the relevant references before editing and keep them aligned with changes. Source paths in this table are relative to `src/`. [ARCHITECTURE.md](docs/ARCHITECTURE.md) maps contracts to owners/tests and gives skill/editor contribution recipes.

| Task | Start here |
| --- | --- |
| App, turns, travel, lifecycle | `app.zig`, `game.zig`, `game/sim.zig`, `game/presentation.zig`; ARCHITECTURE |
| Combat, skills, foes, statuses | `game/combat.zig`, `game/attacks.zig`, `game/foe_rules.zig`, `game/skills.zig`, `game/rewards.zig`; `play/actor.zig`, `play/skillbar.zig`, `play/skill_contract.zig`, individual `play/` skill/status modules; ARCHITECTURE |
| Items, loot, stats, progression | [PROGRESSION.md](docs/PROGRESSION.md); `play/items.zig`, `play/item_bases.zig`, `play/affixes.zig`, `play/loot.zig`, `play/gear.zig`, `play/inventory.zig`, `play/ground_items.zig`, `play/attrs.zig`, `play/progress.zig`, `game/character.zig` |
| Skill/passive trees | [DIABLO2_SKILL_TREE.md](docs/DIABLO2_SKILL_TREE.md), [POE2_PASSIVE_TREE.md](docs/POE2_PASSIVE_TREE.md); `ui/trees.zig`, `play/passives.zig`, `play/progress.zig` |
| Controls, aiming, mouse | [CONTROLLER.md](docs/CONTROLLER.md); `core/input.zig`, `input_bindings.zig`, `input_names.zig`, `input_repeat.zig` (all in `core/`); `game/targeting.zig`, `game/mouse.zig` |
| HUD, menus, cards, wording | [HUD_LAYOUT.md](docs/HUD_LAYOUT.md), [DATA_PRESENTATION.md](docs/DATA_PRESENTATION.md); `ui/hud.zig`, `ui/book.zig`, `ui/character_*.zig`, `ui/item_card.zig`, `game/overlay.zig`, `core/wording.zig` |
| Maps, generation, terrain | `map/atlas.zig`, `map/atlas_text.zig`, `map/procgen.zig`, `map/biome/`, `map/feature/`, `map/grid.zig`; [TERRAIN.md](docs/TERRAIN.md), `play/terrain.zig`; gas/fire/ice/day/climate live in `map/` |
| Editor | ARCHITECTURE; `edit/editor.zig` (lifecycle), `interaction.zig` (input), `placement.zig` (brushes), `history.zig`, `preview.zig`, `thumbnails.zig` (all in `edit/`) |
| NPCs, dialog, quests, triggers, trade | `map/script.zig`, `map/script_text.zig`, `play/trigger.zig`, `play/trade.zig`, `game/talking.zig`, `edit/plot.zig`, `edit/plot_fields.zig`, `ui/talk.zig`, `ui/quests.zig`, `ui/book.zig` (trade page); content in `maps/start.map` |
| Saves | [SAVE_FORMAT.md](docs/SAVE_FORMAT.md); `save.zig`, `save_data.zig`, `save_format.zig`, `save_values.zig`, `core/store.zig`, `core/wire.zig` |
| Rendering, lighting, FX | ARCHITECTURE; `game/scene.zig`, `game/presentation.zig`, `game/projectile_motion.zig`; `gfx/`: `look`, `sprite_assets`, `sprites`, `ground`, `light*`, `shadow`, `effect_state`, `impact_queue`, `status_marks`, `fx`, `cinema`, `weather` |
| Art/assets | [TILE_ART_WORKFLOW.md](docs/TILE_ART_WORKFLOW.md), [ART_PROVENANCE.md](docs/ART_PROVENANCE.md); `assets/source/` and `tools/tile_art/` at repo root; `gfx/sprite_assets.zig` |
| Source text editor | [TEXT_EDITOR.md](docs/TEXT_EDITOR.md); `edit/text_catalog.zig`, `edit/text_panel.zig`; root `text-tags.json`, `assets/data/player-labels.txt` |
| Linux/macOS packaging | [RELEASE_BUILDS.md](docs/RELEASE_BUILDS.md); root `build-linux.cmd`, `build-macos.cmd` |

Tests live beside their owners; integration tests are in `src/game/tests/` by domain and `src/edit/tests.zig`. Shared scripted play: `src/game/harness.zig`.

## Essential contracts

- Simulation owns rules, RNG and saved state; presentation follows resolved impacts. Simulation never reads rendering/UI. HUD, deaths, drops and statuses follow the pictured timing. Idle frames/free actions do not age simulation.
- Preview and resolution share legality, geometry, costs and scaling; previews never expose hidden targets. Preserve seeded outcomes and save identities. Read ARCHITECTURE/SAVE_FORMAT before lifecycle changes.
- `core/input.zig` alone polls devices. Controller is primary; keyboard mirrors actions. Show controls as device-aware glyphs (`gfx/prompt_icon.zig`, editor `gfx/prompt_text.zig`).
- UI shows relevant facts once, with units, effects before metrics, and no flavor text. Use the hero's name in logs/death text. Preserve shared typography, layout and muted-gold styling.
- `map/grid.zig` owns terrain rules, `gfx/look.zig` appearance; `map/fov.zig`/`map/lume.zig` own gameplay visibility. Rendering must not reveal hidden bodies or change exploration.
- Editor gestures are one undo transaction; cancel restores without consuming history. Derived previews must not mutate authored maps.
- Preserve owner pixels, native scale and authored layers; update canonical Aseprite sources and provenance. Asset filenames must be globally unique (embedded by bare filename); register body/tile PNGs in `sprite_assets`, rebuild, and inspect connected tiles. Sprites use 64px width, tall scenery retains height, and `CELL` is a whole multiple of 64.
