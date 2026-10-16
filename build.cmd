@echo off
REM build.cmd - compile roguelike to zig-out\bin without launching. Type "build". Pass -Doptimize=ReleaseFast for an optimized build.
REM Zig static-links raylib into a single exe (no raylib.dll).
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build %*
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
echo BUILD OK: %EXE%
