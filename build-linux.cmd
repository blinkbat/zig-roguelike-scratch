@echo off
setlocal
call "%~dp0_zig.cmd" || exit /b 1
python "%~dp0tools\release.py" linux --zig "%ZIG%" %*
exit /b %errorlevel%
