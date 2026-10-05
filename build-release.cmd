@echo off
REM build-release.cmd - ReleaseFast into zig-out\bin. Type "build-release".
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build -Doptimize=ReleaseFast
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
echo RELEASE OK: zig-out\bin\%EXE%
