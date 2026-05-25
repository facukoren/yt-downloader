@echo off
REM First-run setup. Creates desktop shortcut, generates icon, unblocks files.
REM Idempotent: safe to run multiple times.

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Setup.ps1"
