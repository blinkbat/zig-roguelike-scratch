@echo off
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build --build-file "%BUILD_FILE%" %*
if errorlevel 1 ( echo BUILD FAILED & exit /b 1 )
echo BUILD OK: %EXE%
