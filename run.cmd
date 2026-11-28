@echo off
setlocal
set "HERE=%~dp0"
call "%HERE%_zig.cmd" || exit /b 1
taskkill /IM %EXE% /F >nul 2>&1
"%ZIG%" build --build-file "%BUILD_FILE%" %*
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
REM Launched directly: `zig build run` can hang after the game exits.
"%HERE%zig-out\bin\%EXE%" %GAME_ARGS%
