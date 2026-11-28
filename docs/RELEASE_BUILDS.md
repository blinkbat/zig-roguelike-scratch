# Release builds

Run from the repository root with Python 3.9+ and Zig 0.14.1. The Windows wrappers select the compiler through `_zig.cmd`.

| Target | Build on Windows | Archive under `zig-out/releases/` |
| --- | --- | --- |
| Linux x86-64 | `./build-linux.cmd` | `cistern-linux-x86_64.tar.gz` |
| macOS 11+, Apple Silicon and Intel | `./build-macos.cmd` | `cistern-macos-arm64.tar.gz`, `cistern-macos-x86_64.tar.gz` |

Use `--arch arm64` or `--arch x86_64` for one Mac architecture. With Zig on PATH, run `python3 tools/release.py linux` or `python3 tools/release.py macos`. Each archive has a SHA-256 sidecar. Extract into a writable directory and start `./run.sh`, or double-click `run.command` on macOS. The launcher selects its directory for maps and saves. Transfer the archive to retain maps, licenses and executable permissions.

## Linux

The baseline x86-64 target requires glibc 2.31, X11 or XWayland, and OpenGL 3.3. The archive README lists system graphics packages. The launcher requests NVIDIA PRIME offload when `/proc/driver/nvidia` exists, otherwise `DRI_PRIME=1`. Existing environment settings win. Windows exports `NvOptimusEnablement` and `AmdPowerXpressRequestHighPerformance` for discrete GPU selection.

For graphics reports, capture vendor, renderer, OpenGL version and build mode under Debug > Diagnostics. Options > Display controls fullscreen, VSync and frame limit. Debug > Lighting and Effects isolates individual passes. Linux fullscreen uses the current monitor's native mode and restores the window geometry on exit.

## macOS

The archives contain portable development folders. Zig supplies an ad-hoc signature for Apple Silicon and the release helper verifies each signed page. Distribution signing, notarization and runtime driver checks require a Mac.

The pinned raylib revision scales viewport and clipping queries even with Retina framebuffers disabled. `build.zig` patches a generated copy of `rcore.c` to apply scaling only in high-DPI mode. Window, input and effect textures then share coordinates through fullscreen transitions.

## Dependencies and verification

`tools/release-deps.json` pins Linux development packages by URL, version and SHA-256. The helper verifies downloads before extraction and falls back to the Debian archive mirror. Zig manifests pin raylib and the macOS frameworks mirror. The direct raylib archive avoids an incomplete Git fetch in Zig 0.14.1. SDK files stay in the global package cache.

The dependency cache defaults to `../.zigtoolchain/cistern-release/`. First use needs network access. Override `--cache-dir` and `--output-dir` as needed. The Python helper accepts `--zig`, `--build-cache` and `--global-cache` for an alternate compiler and Zig caches. Raw binaries are under `<output-dir>/build/<platform>-<arch>/bin/cistern`.

The helper type-checks, builds stripped ReleaseFast, inspects the binary, and packages that binary with every current map and required licenses. It checks the source hash again before publication and verifies the archive's member inventory, contents and permissions. Sorted entries, fixed metadata and recorded hashes support reproducible builds. Cross-builds do not exercise target drivers.

Run `python -B tools/test_release.py` for packaging and failure-path tests.
