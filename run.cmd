@echo off
REM Pass -Doptimize=ReleaseFast for an optimized run.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
taskkill /IM %EXE% /F >nul 2>&1
"%ZIG%" build run %*
