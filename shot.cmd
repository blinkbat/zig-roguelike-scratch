@echo off
REM Headless captures use a separate executable so a running game stays open.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build --prefix %DEV%
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
"%~dp0%DEV%\bin\%EXE%" --shot
if errorlevel 1 ( echo SHOTS FAILED & exit /b 1 )
echo SHOTS in shots\
