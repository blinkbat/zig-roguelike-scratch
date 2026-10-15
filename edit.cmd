@echo off
REM edit.cmd - build Debug and open the world editor on worlds\main.world, or on the .world file named.
call "%~dp0run.cmd" -- --edit %1
