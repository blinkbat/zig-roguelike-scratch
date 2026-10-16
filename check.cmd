@echo off
REM Type-check only: no codegen or linking.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
"%ZIG%" build check
if errorlevel 1 ( echo CHECK FAILED & exit /b 1 )
echo CHECK OK
