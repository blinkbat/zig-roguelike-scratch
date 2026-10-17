@echo off
REM Defaults to maps\main.map when no path is given.
call "%~dp0run.cmd" -- --edit %1
