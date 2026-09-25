@echo off
REM shot.cmd - build then render shots\lean.png and shots\aim.png headless (window hidden). Leaves a running game alone.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build --prefix zig-out-dev
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
"%~dp0zig-out-dev\bin\roguelike.exe" --shot
echo SHOTS in shots\
