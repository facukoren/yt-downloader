# =============================================================================
# YT Downloader - First-run setup
#
# Idempotent. Run as standard user (no admin needed). Effects:
#   1. Generates app.ico in this folder.
#   2. Unblocks all .exe / .bat / .ps1 / .dll files (removes Zone.Identifier).
#   3. Pre-compiles the C# helper to YTD.cache.dll for fast app launch.
#   4. Creates "Descargar Videos.lnk" on the Desktop pointing to the app.
#   5. Shows confirmation.
#
# Reversal: delete the shortcut + the app folder. No system changes.
# =============================================================================

#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$iconPath    = Join-Path $scriptDir 'app.ico'
$dllPath     = Join-Path $scriptDir 'YTD.cache.dll'
$dllHashPath = Join-Path $scriptDir 'YTD.cache.hash'
$launchPath  = Join-Path $scriptDir 'YTDownloader.ps1'
$desktop     = [Environment]::GetFolderPath('Desktop')
$lnkPath     = Join-Path $desktop 'Descargar Videos.lnk'

$report = New-Object System.Collections.Generic.List[string]
function Step([string]$msg) { $report.Add($msg) }

# -----------------------------------------------------------------------------
# 1. Generate app.ico (red circle + white download arrow, 256x256 PNG inside ICO)
# -----------------------------------------------------------------------------
function New-AppIcon {
    param([string]$Path)

    $bmp = New-Object System.Drawing.Bitmap(256, 256)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Red circle background (YouTube red)
    $brushBg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 204, 0, 0))
    $g.FillEllipse($brushBg, 8, 8, 240, 240)
    $brushBg.Dispose()

    # White download arrow (head + shaft)
    $arrow = @(
        [System.Drawing.Point]::new( 96,  72),
        [System.Drawing.Point]::new(160,  72),
        [System.Drawing.Point]::new(160, 144),
        [System.Drawing.Point]::new(196, 144),
        [System.Drawing.Point]::new(128, 200),
        [System.Drawing.Point]::new( 60, 144),
        [System.Drawing.Point]::new( 96, 144)
    )
    $g.FillPolygon([System.Drawing.Brushes]::White, [System.Drawing.Point[]]$arrow)
    $g.Dispose()

    # Serialize bitmap to PNG bytes
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $pngBytes = $ms.ToArray()
    $ms.Dispose()

    # Wrap PNG into a minimal ICO container (single 256x256 entry)
    $ico = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ico)
    $bw.Write([uint16]0)              # reserved
    $bw.Write([uint16]1)              # type = icon
    $bw.Write([uint16]1)              # image count
    $bw.Write([byte]0)                # width  (0 = 256)
    $bw.Write([byte]0)                # height (0 = 256)
    $bw.Write([byte]0)                # palette
    $bw.Write([byte]0)                # reserved
    $bw.Write([uint16]1)              # planes
    $bw.Write([uint16]32)             # bits per pixel
    $bw.Write([uint32]$pngBytes.Length)
    $bw.Write([uint32]22)             # offset to image data
    $bw.Write($pngBytes)
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($Path, $ico.ToArray())
    $bw.Dispose()
    $ico.Dispose()
}

try {
    New-AppIcon -Path $iconPath
    Step "OK  Icono generado: app.ico"
} catch {
    Step "ERR Generacion icono: $($_.Exception.Message)"
}

# -----------------------------------------------------------------------------
# 2. Unblock files (remove Mark-of-the-Web so SmartScreen no longer warns)
# -----------------------------------------------------------------------------
try {
    Get-ChildItem -Path (Join-Path $scriptDir '*') -File -Include *.exe,*.bat,*.ps1,*.dll -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
    Step "OK  Archivos desbloqueados (sin Mark-of-the-Web)"
} catch {
    Step "WRN Unblock-File: $($_.Exception.Message)"
}

# -----------------------------------------------------------------------------
# 3. Pre-compile the C# helper into YTD.cache.dll for fast launch.
#    The C# source lives ONLY in YTDownloader.ps1; -CompileOnly compiles it to
#    YTD.cache.dll (+ YTD.cache.hash) and returns without showing the UI, so
#    the pre-compiled DLL always matches what the app expects.
# -----------------------------------------------------------------------------
try {
    if (Test-Path -LiteralPath $dllPath) { Remove-Item -LiteralPath $dllPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $dllHashPath) { Remove-Item -LiteralPath $dllHashPath -Force -ErrorAction SilentlyContinue }
    & $launchPath -CompileOnly
    if (Test-Path -LiteralPath $dllPath) {
        Step "OK  Helper C# compilado: YTD.cache.dll"
    } else {
        Step "WRN DLL no aparece tras compilar"
    }
} catch {
    Step "WRN Compilacion DLL fallo (la app re-compilara en runtime): $($_.Exception.Message)"
}

# -----------------------------------------------------------------------------
# 4. Create Desktop shortcut "Descargar Videos.lnk"
#    Targets powershell.exe directly (no cmd flash on click).
# -----------------------------------------------------------------------------
try {
    $shell = New-Object -ComObject WScript.Shell
    $lnk   = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath       = (Get-Command powershell.exe).Source
    $lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$launchPath`""
    $lnk.WorkingDirectory = $scriptDir
    if (Test-Path -LiteralPath $iconPath) { $lnk.IconLocation = "$iconPath,0" }
    $lnk.Description      = 'YT Downloader - Descargar videos de YouTube'
    $lnk.WindowStyle      = 7   # minimized in case PS shows briefly
    $lnk.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    Step "OK  Acceso directo creado: $lnkPath"
} catch {
    Step "ERR Acceso directo: $($_.Exception.Message)"
}

# -----------------------------------------------------------------------------
# 5. Report
# -----------------------------------------------------------------------------
$summary = "Instalacion completa.`n`n" + ($report -join "`n") +
           "`n`nAhora podes hacer doble click en 'Descargar Videos' en tu escritorio."
[System.Windows.Forms.MessageBox]::Show(
    $summary,
    'YT Downloader - Instalacion',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
