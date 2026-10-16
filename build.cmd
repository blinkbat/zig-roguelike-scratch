@echo off
REM Pass -Doptimize=ReleaseFast for an optimized build; raylib is linked statically.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build %*
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
echo BUILD OK: %EXE%
