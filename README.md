# Cistern

Cistern is a grid roguelike and map editor built with Zig 0.14.1 and raylib. Play one of three hero classes on authored or procedural maps.

## Build on Windows

Run these commands from the repository root in PowerShell.

```powershell
$env:ZIG = 'C:\tools\zig-x86_64-windows-0.14.1\zig.exe'
./check.cmd
./test.cmd
./build.cmd
```

The wrappers check the compiler version. Set `ZIG` to the executable, or let them look in `../.zigtoolchain/zig-x86_64-windows-0.14.1/` and then `PATH`. The first build downloads the pinned raylib dependencies. [Download Zig](https://ziglang.org/download/)

| Command | Result |
| --- | --- |
| `./check.cmd` | Type-check the executable and tests |
| `./test.cmd` | Run the full suite, including procedural generation and source-boundary checks |
| `./test.cmd save` | Run game tests with “save” in the name |
| `./build.cmd` or `./build-release.cmd` | Build Debug or ReleaseFast in `zig-out/bin/` |
| `./run.cmd` or `./edit.cmd [map path]` | Launch play or the editor using this directory's maps and saves |

## Working on Cistern

Start with the [project instructions and subsystem index](AGENTS.md) for code ownership and headless captures. The [runtime contracts](docs/ARCHITECTURE.md) cover turn ordering and how to add a skill or editor tool. The [save format](docs/SAVE_FORMAT.md) defines compatibility and migrations.

For Linux and macOS archives, see [release builds](docs/RELEASE_BUILDS.md). Windows CI runs the compile check, full test suite, packaging tests and Debug build. [CI workflow](.github/workflows/check.yml)
