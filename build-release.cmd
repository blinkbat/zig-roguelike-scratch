@echo off
REM build-release.cmd - ReleaseFast into zig-out\bin. Type "build-release".
call "%~dp0build.cmd" -Doptimize=ReleaseFast
