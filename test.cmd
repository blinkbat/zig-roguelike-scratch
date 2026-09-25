@echo off
REM test.cmd - run the unit suite. Pass a filter: test.cmd fov
setlocal
call "%~dp0_zig.cmd" || exit /b 1
if "%~1"=="" (
  "%ZIG%" build test
) else (
  "%ZIG%" build test -Dtest-filter=%1
)
if errorlevel 1 ( echo TESTS FAILED & exit /b 1 )
echo TESTS OK
