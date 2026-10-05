@echo off
REM run.cmd - build (incremental) and launch. Type "run".
setlocal
call "%~dp0_zig.cmd" || exit /b 1
taskkill /IM %EXE% /F >nul 2>&1
"%ZIG%" build run
