@echo off
setlocal
call "%~dp0_zig.cmd" || exit /b 1
if "%~1"=="" (
  "%ZIG%" build --build-file "%BUILD_FILE%" test
) else (
  "%ZIG%" build --build-file "%BUILD_FILE%" test -Dtest-filter=%1
)
if errorlevel 1 ( echo TESTS FAILED & exit /b 1 )
echo TESTS OK
