@echo off
REM Scripts call this shared definition so toolchain versions cannot drift.
set "ZIG_VERSION=0.14.1"
if defined ZIG goto verify
set "ZIG=%~dp0..\.zigtoolchain\zig-x86_64-windows-%ZIG_VERSION%\zig.exe"
if exist "%ZIG%" goto verify
set "ZIG="
for /f "delims=" %%Z in ('where zig.exe 2^>nul') do if not defined ZIG set "ZIG=%%Z"
if not defined ZIG ( echo Install Zig %ZIG_VERSION% or set ZIG to its executable. See README.md. & exit /b 1 )
:verify
if not exist "%ZIG%" ( echo NO TOOLCHAIN: "%ZIG%" & exit /b 1 )
set "ZIG_FOUND="
for /f "delims=" %%V in ('""%ZIG%" version"') do set "ZIG_FOUND=%%V"
if not "%ZIG_FOUND%"=="%ZIG_VERSION%" ( echo Expected Zig %ZIG_VERSION%, found "%ZIG_FOUND%". See README.md. & exit /b 1 )
REM build.zig's exe name, and shot.cmd's prefix that keeps a running game's exe unlocked.
set "EXE=cistern.exe"
set "DEV=zig-out-dev"
