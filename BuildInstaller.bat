@echo off
REM Compila installer.iss con Inno Setup -> "Instalar YT Downloader.exe"
REM Requiere Inno Setup instalado (https://jrsoftware.org/isdl.php - gratis).
REM Si no esta, usa BuildPortableZip.bat como fallback.

setlocal
set "ISCC="

REM Buscar ISCC.exe en ubicaciones tipicas (system + per-user)
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"  set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe"       set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if exist "%LocalAppData%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles(x86)%\Inno Setup 5\ISCC.exe"  set "ISCC=%ProgramFiles(x86)%\Inno Setup 5\ISCC.exe"

if "%ISCC%"=="" (
    echo.
    echo [ERROR] Inno Setup no esta instalado.
    echo.
    echo Descargalo gratis de:
    echo     https://jrsoftware.org/isdl.php
    echo.
    echo O usa BuildPortableZip.bat para hacer un ZIP portable sin instalador.
    echo.
    pause
    exit /b 1
)

echo Usando: %ISCC%
echo Compilando installer.iss...
echo.

"%ISCC%" "%~dp0installer.iss"
if errorlevel 1 (
    echo.
    echo [ERROR] Compilacion fallo.
    pause
    exit /b 1
)

echo.
echo [OK] Generado: "Instalar YT Downloader.exe"
echo Listo para distribuir.
pause
endlocal
