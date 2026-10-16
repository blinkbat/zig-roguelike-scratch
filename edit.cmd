@echo off
REM Defaults to worlds\main.world when no path is given.
call "%~dp0run.cmd" -- --edit %1
