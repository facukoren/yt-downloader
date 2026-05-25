@echo off
REM Empaqueta la app en "YT Downloader Portable.zip" listo para compartir.
REM No requiere herramientas externas (usa Compress-Archive de PowerShell).
REM El destinatario extrae el ZIP y ejecuta Setup.bat una vez.

start "" /WAIT powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuildPortableZip.ps1"
