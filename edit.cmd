@echo off
REM edit.cmd - build (incremental) and open the world editor on worlds\main.world, or on the .world file named.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
taskkill /IM roguelike.exe /F >nul 2>&1
"%ZIG%" build run -- --edit %1
