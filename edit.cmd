@echo off
REM Defaults to maps\main.map when no path is given.
setlocal
if "%~1"=="" (set GAME_ARGS=--edit) else (set GAME_ARGS=--edit "%~1")
call "%~dp0run.cmd"
