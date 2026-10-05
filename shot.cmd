@echo off
REM shot.cmd - build then render every shots\*.png headless (window hidden). Leaves a running game alone.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build --prefix %DEV%
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
"%~dp0%DEV%\bin\%EXE%" --shot
if errorlevel 1 ( echo SHOTS FAILED & exit /b 1 )
echo SHOTS in shots\
