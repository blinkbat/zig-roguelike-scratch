# Cistern

A grid roguelike and map editor written in Zig 0.14.1 with raylib. The game includes
three hero classes, procedural and authored maps, equipment, progression and saved runs.

## Build on Windows

Download and extract [Zig 0.14.1](https://ziglang.org/download/). Run these commands
from the repository root in PowerShell:

```powershell
$env:ZIG = 'C:\tools\zig-x86_64-windows-0.14.1\zig.exe'
./check.cmd
./test.cmd
./build.cmd
```

`ZIG` selects an executable explicitly. Without it, the scripts use the existing
`../.zigtoolchain/zig-x86_64-windows-0.14.1/zig.exe`, then search `PATH`. The wrapper
checks the compiler version. The first build downloads the pinned dependencies;
later builds reuse Zig's cache. No separate raylib installation is needed.

`check.cmd` type-checks the executable and tests without linking. `test.cmd` runs
the full suite; `test.cmd save` selects test names containing `save`. Procedural-map
tests can take several minutes. `build.cmd` builds Debug without launching;
`build-release.cmd` selects ReleaseFast. Outputs go to `zig-out/bin/`.

For play, use `run.cmd`. For the editor, use `edit.cmd [map path]`. Maps and saves
are relative to the working directory; run the game from this directory.

## Verification and other platforms

Python 3.9+ is needed only for release tooling. Run `python -B tools/test_release.py`
for packaging checks. See [release builds](docs/RELEASE_BUILDS.md) for Linux and
macOS cross-builds, dependencies, archives and runtime limitations.

The [CI workflow](.github/workflows/check.yml) runs the Windows compile check, full
test suite, packaging tests and build. Source dependency boundaries and the module
test roster are checked by every Zig build step. Boundary-checker tests also run
with `test.cmd`.

Headless captures and CPU benchmarks are documented in [AGENTS.md](AGENTS.md).
Keep captures and scratch files in the system temporary directory. Verification
does not require interactive play.

## Working on the code

Start with [runtime contracts](docs/ARCHITECTURE.md) for ownership, lifetimes,
integration tests and recipes for adding skills or editor tools.

| Area | Entry point |
| --- | --- |
| Application and transitions | `src/app.zig` |
| Run state, combat and rewards | `src/game/sim.zig`, `src/game/attacks.zig`, `src/game/rewards.zig` |
| Input and turn coordination | `src/core/input.zig`, `src/game.zig` |
| Movement repeat and stick hysteresis | `src/core/input_repeat.zig` |
| Character navigation, cards and statistics | `src/ui/book.zig`, `src/ui/item_card.zig`, `src/ui/character_stats.zig` |
| Presentation timing | `src/game/presentation.zig` |
| Editor input, lifecycle and history | `src/edit/interaction.zig`, `src/edit/editor.zig`, `src/edit/history.zig` |
| Editor tools, help and naming | `src/edit/tool_catalog.zig`, `src/edit/name_field.zig` |
| Editor derived previews and thumbnails | `src/edit/preview.zig`, `src/edit/thumbnails.zig` |
| Map parsing and generation | `src/map/atlas_text.zig`, `src/map/procgen.zig` |
| Persistence | `src/save.zig`, `src/core/store.zig` |

Read [AGENTS.md](AGENTS.md) before changing runtime contracts or artwork. Saves
currently require a matching schema fingerprint; compatibility policy and file
format changes need an explicit decision. Behavior-preserving refactors should
keep the recorded save fingerprint and seeded combat outcomes unchanged.
