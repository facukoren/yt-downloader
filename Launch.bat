@echo off
REM Launcher for YT Downloader UI
REM start "" detaches so the cmd window closes immediately.
REM -STA required by WinForms, -ExecutionPolicy Bypass for this run only,
REM -WindowStyle Hidden hides the PowerShell console.

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0YTDownloader.ps1"
