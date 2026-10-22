@echo off
REM Scripts call this shared definition so toolchain versions cannot drift.
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe"
if not exist "%ZIG%" ( echo NO TOOLCHAIN: "%ZIG%" & exit /b 1 )
REM build.zig's exe name, and shot.cmd's prefix that keeps a running game's exe unlocked.
set "EXE=cistern.exe"
set "DEV=zig-out-dev"
