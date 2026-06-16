# =============================================================================
# YT Downloader - WinForms UI for yt-dlp
# Portable, zero-dependency (uses local yt-dlp.exe + ffmpeg.exe)
# =============================================================================

#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -----------------------------------------------------------------------------
# Native .NET event sink + Updater (avoid PowerShell event subsystem).
# Loaded from a pre-compiled DLL if available (fast launch). Falls back to
# in-memory compilation on first run.
# -----------------------------------------------------------------------------
$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dllCachePath = Join-Path $thisDir 'YTD.cache.dll'

$csTypeDef = @'
using System;
using System.Diagnostics;
using System.Threading;
using System.Collections.Concurrent;

namespace YTD {
    public class ProcOutput {
        public const string ExitSentinel = "__YTD_EXIT__";
        public ConcurrentQueue<string> Queue;
        public ProcOutput(ConcurrentQueue<string> q) { Queue = q; }
        public void OnData(object sender, DataReceivedEventArgs e) {
            if (e != null && e.Data != null) Queue.Enqueue(e.Data);
        }
        public void OnExit(object sender, EventArgs e) {
            try { Process p = sender as Process; if (p != null) p.WaitForExit(); } catch { }
            Queue.Enqueue(ExitSentinel);
        }
    }
    public static class Updater {
        public const string OutputPrefix = "__YTD_UPDATE_OUT__";
        public const string DonePrefix   = "__YTD_UPDATE_DONE__";
        public static void StartUpdate(string ytdlpPath, ConcurrentQueue<string> queue, int timeoutMs) {
            Thread t = new Thread(delegate() {
                int exitCode = -1;
                try {
                    ProcessStartInfo psi = new ProcessStartInfo(ytdlpPath, "-U");
                    psi.RedirectStandardOutput = true;
                    psi.RedirectStandardError  = true;
                    psi.UseShellExecute        = false;
                    psi.CreateNoWindow         = true;
                    Process p = Process.Start(psi);
                    string outStr = p.StandardOutput.ReadToEnd();
                    string errStr = p.StandardError.ReadToEnd();
                    if (!p.WaitForExit(timeoutMs)) {
                        try { p.Kill(); } catch { }
                        queue.Enqueue(OutputPrefix + "::Timeout esperando yt-dlp -U");
                    } else {
                        exitCode = p.ExitCode;
                        string combined = (outStr + errStr).Trim();
                        if (combined.Length > 0) queue.Enqueue(OutputPrefix + "::" + combined);
                    }
                    p.Dispose();
                } catch (Exception ex) {
                    queue.Enqueue(OutputPrefix + "::ERROR " + ex.Message);
                } finally {
                    queue.Enqueue(DonePrefix + "::" + exitCode);
                }
            });
            t.IsBackground = true;
            t.Start();
        }
    }
}
'@

if (-not ('YTD.ProcOutput' -as [type])) {
    try {
        if (Test-Path $dllCachePath) {
            Add-Type -Path $dllCachePath -ErrorAction Stop
        } else {
            Add-Type -TypeDefinition $csTypeDef -OutputAssembly $dllCachePath -OutputType Library -ErrorAction Stop
            Add-Type -Path $dllCachePath -ErrorAction Stop
        }
    } catch {
        # Fallback: in-memory compile only (no cache). Slower next launch but works.
        Add-Type -TypeDefinition $csTypeDef
    }
}

# Optional helper for downloading deno.exe (JS runtime required by yt-dlp for
# full YouTube extraction). Kept as a separate Add-Type so existing YTD.cache.dll
# installs keep working without recompilation.
if (-not ('YTD.DenoInstaller' -as [type])) {
    $denoCsTypeDef = @'
using System;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Threading;
using System.Collections.Concurrent;

namespace YTD {
    public static class DenoInstaller {
        public const string OutputPrefix = "__YTD_DENO_OUT__";
        public const string DonePrefix   = "__YTD_DENO_DONE__";
        public static void Install(string scriptDir, ConcurrentQueue<string> queue) {
            Thread t = new Thread(delegate() {
                int code = 0;
                string tmpZip = Path.Combine(scriptDir, "deno-download.zip.tmp");
                string finalPath = Path.Combine(scriptDir, "deno.exe");
                try {
                    string url = "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip";
                    queue.Enqueue(OutputPrefix + "::Descargando runtime JavaScript (deno) para extraccion completa de YouTube...");
                    try {
                        ServicePointManager.SecurityProtocol = ServicePointManager.SecurityProtocol | (SecurityProtocolType)3072;
                    } catch { }
                    using (WebClient wc = new WebClient()) {
                        wc.Headers.Add("User-Agent", "YTDownloader/1.0");
                        wc.DownloadFile(url, tmpZip);
                    }
                    queue.Enqueue(OutputPrefix + "::Extrayendo deno.exe...");
                    bool extracted = false;
                    using (ZipArchive archive = ZipFile.OpenRead(tmpZip)) {
                        foreach (ZipArchiveEntry entry in archive.Entries) {
                            if (string.Equals(entry.Name, "deno.exe", StringComparison.OrdinalIgnoreCase)) {
                                entry.ExtractToFile(finalPath, true);
                                extracted = true;
                                break;
                            }
                        }
                    }
                    if (extracted && File.Exists(finalPath)) {
                        queue.Enqueue(OutputPrefix + "::deno.exe instalado. Las proximas descargas usaran extraccion completa.");
                    } else {
                        code = 1;
                        queue.Enqueue(OutputPrefix + "::deno.exe no encontrado dentro del ZIP descargado.");
                    }
                } catch (Exception ex) {
                    code = 2;
                    queue.Enqueue(OutputPrefix + "::No se pudo instalar deno automaticamente: " + ex.Message);
                } finally {
                    try { if (File.Exists(tmpZip)) File.Delete(tmpZip); } catch { }
                    queue.Enqueue(DonePrefix + "::" + code);
                }
            });
            t.IsBackground = true;
            t.Start();
        }
    }
}
'@
    try {
        # Ensure the System.IO.Compression assemblies are loaded so we can
        # reference them by absolute path (most reliable form for -ReferencedAssemblies
        # on PS 5.1, where short names can fail to resolve).
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $denoRefs = @(
            [System.IO.Compression.ZipArchive].Assembly.Location,
            [System.IO.Compression.ZipFile].Assembly.Location
        )
        Add-Type -TypeDefinition $denoCsTypeDef -ReferencedAssemblies $denoRefs -ErrorAction Stop
    } catch {
        # Non-fatal: auto-install simply will not be available; manual deno.exe still works.
    }
}

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ytdlpPath  = Join-Path $scriptDir 'yt-dlp.exe'
$ffmpegPath = Join-Path $scriptDir 'ffmpeg.exe'
$denoPath   = Join-Path $scriptDir 'deno.exe'
$configPath = Join-Path $scriptDir 'config.json'

# Clean up any stale partial download from a previous interrupted session.
$denoTmpZip = Join-Path $scriptDir 'deno-download.zip.tmp'
if (Test-Path -LiteralPath $denoTmpZip) {
    try { Remove-Item -LiteralPath $denoTmpZip -Force -ErrorAction SilentlyContinue } catch {}
}

# Sanity check: yt-dlp must exist
if (-not (Test-Path $ytdlpPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "No se encontro yt-dlp.exe en:`n$scriptDir`n`nColoca yt-dlp.exe junto a este script.",
        "Error - yt-dlp.exe faltante",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    return
}

$ffmpegAvailable = Test-Path $ffmpegPath

# -----------------------------------------------------------------------------
# Resolution presets
# -----------------------------------------------------------------------------
# Format selectors force H.264 (avc1) video + AAC (m4a) audio for maximum
# compatibility — output is always MP4 / H.264 / AAC, playable on any device
# or player (old TVs, editors, phones). Fallbacks keep the download working
# if avc1 is unavailable for a given video.
# NOTE: YouTube only serves H.264 up to 1080p; the 4K/1440p presets still cap
# at the best available H.264 (effectively 1080p) because higher resolutions
# exist only in AV1/VP9.
$resolutions = @(
    [PSCustomObject]@{ Label = 'Mejor calidad (H.264)';    Format = 'bestvideo[vcodec^=avc1]+bestaudio[ext=m4a]/best[vcodec^=avc1]/best[ext=mp4]/best';                                                                                            AudioOnly = $false }
    [PSCustomObject]@{ Label = '4K (2160p)';               Format = 'bestvideo[height<=2160][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=2160][vcodec^=avc1]/best[height<=2160][ext=mp4]/best[height<=2160]';        AudioOnly = $false }
    [PSCustomObject]@{ Label = '1440p';                    Format = 'bestvideo[height<=1440][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=1440][vcodec^=avc1]/best[height<=1440][ext=mp4]/best[height<=1440]';        AudioOnly = $false }
    [PSCustomObject]@{ Label = '1080p (Full HD)';          Format = 'bestvideo[height<=1080][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=1080][vcodec^=avc1]/best[height<=1080][ext=mp4]/best[height<=1080]';        AudioOnly = $false }
    [PSCustomObject]@{ Label = '720p (HD)';                Format = 'bestvideo[height<=720][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=720][vcodec^=avc1]/best[height<=720][ext=mp4]/best[height<=720]';              AudioOnly = $false }
    [PSCustomObject]@{ Label = '480p';                     Format = 'bestvideo[height<=480][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=480][vcodec^=avc1]/best[height<=480][ext=mp4]/best[height<=480]';              AudioOnly = $false }
    [PSCustomObject]@{ Label = '360p';                     Format = 'bestvideo[height<=360][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=360][vcodec^=avc1]/best[height<=360][ext=mp4]/best[height<=360]';              AudioOnly = $false }
    [PSCustomObject]@{ Label = 'Solo audio (MP3)';         Format = $null;                                                                                                                                              AudioOnly = $true  }
)

# -----------------------------------------------------------------------------
# Shared state (used by async event handlers)
# -----------------------------------------------------------------------------
$script:logQueue       = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:proc           = $null
$script:procSink       = $null
$script:dataDelegate   = $null
$script:exitDelegate   = $null
$script:isRunning        = $false
$script:isUpdating       = $false
$script:isInstallingDeno = $false
$script:exitSentinel     = [YTD.ProcOutput]::ExitSentinel
$script:updateOutPrefix  = [YTD.Updater]::OutputPrefix
$script:updateDonePrefix = [YTD.Updater]::DonePrefix
if ('YTD.DenoInstaller' -as [type]) {
    $script:denoOutPrefix  = [YTD.DenoInstaller]::OutputPrefix
    $script:denoDonePrefix = [YTD.DenoInstaller]::DonePrefix
} else {
    $script:denoOutPrefix  = '__YTD_DENO_OUT__'
    $script:denoDonePrefix = '__YTD_DENO_DONE__'
}
$script:notifyIcon       = $null
$script:appIcon          = $null
$script:lastDestForOpen    = $null  # captured at download start for balloon click
$script:lastDownloadedFile = $null  # absolute path of last successfully downloaded file
$script:lastUpdateCheck    = $null  # ISO8601 string of last yt-dlp update check

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Proper Windows argv quoting per Microsoft C runtime rules.
# Implementation follows the canonical CommandLineToArgvW algorithm.
# Loop-based (no regex MatchEvaluator) for PS 5.1 compatibility.
function ConvertTo-CmdArg {
    param([string]$Arg)
    if ([string]::IsNullOrEmpty($Arg)) { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    $i = 0
    $len = $Arg.Length
    while ($i -lt $len) {
        $backslashes = 0
        while ($i -lt $len -and $Arg[$i] -eq '\') {
            $backslashes++
            $i++
        }
        if ($i -eq $len) {
            # End of string: double backslashes so closing quote is not escaped.
            if ($backslashes -gt 0) { [void]$sb.Append('\' * ($backslashes * 2)) }
            break
        } elseif ($Arg[$i] -eq '"') {
            # Double backslashes + escape the quote with one extra backslash.
            [void]$sb.Append('\' * ($backslashes * 2 + 1))
            [void]$sb.Append('"')
            $i++
        } else {
            if ($backslashes -gt 0) { [void]$sb.Append('\' * $backslashes) }
            [void]$sb.Append($Arg[$i])
            $i++
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Locate a JS runtime for yt-dlp (deno is the default expected by yt-dlp's EJS
# subsystem). Prefer a local deno.exe next to the script (portable installs),
# then anything on PATH. Returns the full path or $null if none is available.
function Resolve-DenoPath {
    if (Test-Path -LiteralPath $denoPath) { return $denoPath }
    try {
        $cmd = Get-Command 'deno' -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $cmd) { return $cmd.Source }
    } catch {}
    return $null
}

function Test-IsValidUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $trimmed = $Url.Trim()
    if ($trimmed -notmatch '^(?i)https?://') { return $false }
    try {
        $uri = [System.Uri]$trimmed
        return $uri.IsAbsoluteUri -and ($uri.Scheme -in @('http','https'))
    } catch { return $false }
}

function Load-Config {
    if (-not (Test-Path $configPath)) { return $null }
    try {
        $raw = Get-Content $configPath -Raw -ErrorAction Stop
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch { return $null }
}

function Save-Config {
    param([hashtable]$Config)
    try {
        $Config | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Non-fatal: persistence failure should not break the app
    }
}

# Translate yt-dlp exit code + log content to a human-friendly message.
function Get-FriendlyError {
    param([int]$ExitCode, [string]$LogText)
    $t = if ($null -ne $LogText) { $LogText } else { '' }
    switch -Regex ($t) {
        'Private video'                       { return 'El video es privado.' }
        'Video unavailable'                   { return 'El video no esta disponible.' }
        'This video has been removed'         { return 'El video fue eliminado.' }
        'Sign in to confirm'                  { return 'YouTube pide iniciar sesion para este video (edad / contenido restringido).' }
        'members[- ]only'                     { return 'Video solo para miembros del canal.' }
        'Premiere will begin'                 { return 'El video todavia no esta disponible (premiere futura).' }
        'requested format is not available|Requested format is not available' {
            return 'La calidad elegida no esta disponible para este video. Probá con otra.'
        }
        'Unable to extract'                   { return 'yt-dlp no pudo procesar el video. Quizas hay que actualizarlo (Actualizar yt-dlp en el menu).' }
        'getaddrinfo|Name or service not known|No address associated|Unable to resolve|Failed to establish' {
            return 'Sin conexion a internet o servidor inaccesible.'
        }
        'HTTP Error 403'                      { return 'YouTube bloqueo la descarga (403). Probá actualizar yt-dlp.' }
        'HTTP Error 404'                      { return 'Video no encontrado (404).' }
        'HTTP Error 429'                      { return 'YouTube limito el ritmo de descargas. Esperá unos minutos.' }
        'is not a valid URL|Unsupported URL'  { return 'La URL no es valida o el sitio no esta soportado.' }
        'No space left on device|There is not enough space' {
            return 'No hay espacio en el disco destino.'
        }
        'Permission denied|Access is denied'  { return 'Sin permisos para escribir en la carpeta destino.' }
    }
    if ($ExitCode -eq 0) { return 'OK' }
    return "Descarga fallo (codigo $ExitCode). Revisa el registro para detalles."
}

# Show a Windows balloon tip (transient notification near the system tray).
function Show-Notification {
    param([string]$Title, [string]$Body, [ValidateSet('Info','Warning','Error')] [string]$Kind = 'Info')
    if ($null -eq $script:notifyIcon) { return }
    $iconType = switch ($Kind) {
        'Warning' { [System.Windows.Forms.ToolTipIcon]::Warning }
        'Error'   { [System.Windows.Forms.ToolTipIcon]::Error }
        default   { [System.Windows.Forms.ToolTipIcon]::Info }
    }
    try { $script:notifyIcon.ShowBalloonTip(6000, $Title, $Body, $iconType) } catch { }
}

# -----------------------------------------------------------------------------
# Build UI
# -----------------------------------------------------------------------------
$form               = New-Object System.Windows.Forms.Form
$form.Text          = 'YT Downloader'
$form.Size          = New-Object System.Drawing.Size(720, 560)
$form.MinimumSize   = New-Object System.Drawing.Size(720, 480)
$form.StartPosition = 'CenterScreen'
$form.Font          = New-Object System.Drawing.Font('Segoe UI', 9)

# Load app icon (fallback to default if missing/corrupt)
$iconPath = Join-Path $scriptDir 'app.ico'
if (Test-Path $iconPath) {
    try {
        $script:appIcon = New-Object System.Drawing.Icon($iconPath)
        $form.Icon = $script:appIcon
    } catch { }
}

# --- URL ---
$lblUrl              = New-Object System.Windows.Forms.Label
$lblUrl.Text         = 'URL del video o playlist:'
$lblUrl.Location     = New-Object System.Drawing.Point(12, 12)
$lblUrl.AutoSize     = $true
$form.Controls.Add($lblUrl)

$txtUrl              = New-Object System.Windows.Forms.TextBox
$txtUrl.Location     = New-Object System.Drawing.Point(12, 32)
$txtUrl.Size         = New-Object System.Drawing.Size(580, 24)
$txtUrl.Anchor       = 'Top, Left, Right'
$form.Controls.Add($txtUrl)

$btnPaste            = New-Object System.Windows.Forms.Button
$btnPaste.Text       = 'Pegar'
$btnPaste.Location   = New-Object System.Drawing.Point(600, 30)
$btnPaste.Size       = New-Object System.Drawing.Size(90, 26)
$btnPaste.Anchor     = 'Top, Right'
$form.Controls.Add($btnPaste)

# --- Destino ---
$lblDest             = New-Object System.Windows.Forms.Label
$lblDest.Text        = 'Carpeta destino:'
$lblDest.Location    = New-Object System.Drawing.Point(12, 68)
$lblDest.AutoSize    = $true
$form.Controls.Add($lblDest)

$txtDest             = New-Object System.Windows.Forms.TextBox
$txtDest.Location    = New-Object System.Drawing.Point(12, 88)
$txtDest.Size        = New-Object System.Drawing.Size(580, 24)
$txtDest.Anchor      = 'Top, Left, Right'
$form.Controls.Add($txtDest)

$btnBrowse           = New-Object System.Windows.Forms.Button
$btnBrowse.Text      = 'Examinar...'
$btnBrowse.Location  = New-Object System.Drawing.Point(600, 86)
$btnBrowse.Size      = New-Object System.Drawing.Size(90, 26)
$btnBrowse.Anchor    = 'Top, Right'
$form.Controls.Add($btnBrowse)

# --- Resolución ---
$lblRes              = New-Object System.Windows.Forms.Label
$lblRes.Text         = 'Calidad:'
$lblRes.Location     = New-Object System.Drawing.Point(12, 124)
$lblRes.AutoSize     = $true
$form.Controls.Add($lblRes)

$cmbRes              = New-Object System.Windows.Forms.ComboBox
$cmbRes.Location     = New-Object System.Drawing.Point(12, 144)
$cmbRes.Size         = New-Object System.Drawing.Size(260, 24)
$cmbRes.DropDownStyle = 'DropDownList'
foreach ($r in $resolutions) { $cmbRes.Items.Add($r.Label) | Out-Null }
$cmbRes.SelectedIndex = 0
$form.Controls.Add($cmbRes)

# --- Acciones ---
$btnDownload          = New-Object System.Windows.Forms.Button
$btnDownload.Text     = 'Descargar'
$btnDownload.Location = New-Object System.Drawing.Point(290, 142)
$btnDownload.Size     = New-Object System.Drawing.Size(110, 28)
$btnDownload.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnDownload.ForeColor = [System.Drawing.Color]::White
$btnDownload.FlatStyle = 'Flat'
$form.Controls.Add($btnDownload)

$btnCancel            = New-Object System.Windows.Forms.Button
$btnCancel.Text       = 'Cancelar'
$btnCancel.Location   = New-Object System.Drawing.Point(405, 142)
$btnCancel.Size       = New-Object System.Drawing.Size(85, 28)
$btnCancel.Enabled    = $false
$form.Controls.Add($btnCancel)

$btnOpenFolder        = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text   = 'Abrir carpeta'
$btnOpenFolder.Location = New-Object System.Drawing.Point(495, 142)
$btnOpenFolder.Size   = New-Object System.Drawing.Size(105, 28)
$btnOpenFolder.Anchor = 'Top, Right'
$form.Controls.Add($btnOpenFolder)

$btnPlay              = New-Object System.Windows.Forms.Button
$btnPlay.Text         = [char]0x25B6 + ' Reproducir'
$btnPlay.Location     = New-Object System.Drawing.Point(605, 142)
$btnPlay.Size         = New-Object System.Drawing.Size(85, 28)
$btnPlay.Anchor       = 'Top, Right'
$btnPlay.Enabled      = $false
$form.Controls.Add($btnPlay)

# Enter = Descargar, Escape = Cancelar (keyboard shortcuts for plug-and-play UX)
$form.AcceptButton = $btnDownload
$form.CancelButton = $btnCancel

# --- Progreso ---
$progressBar          = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(12, 182)
$progressBar.Size     = New-Object System.Drawing.Size(678, 22)
$progressBar.Anchor   = 'Top, Left, Right'
$progressBar.Minimum  = 0
$progressBar.Maximum  = 100
$form.Controls.Add($progressBar)

$lblStatus            = New-Object System.Windows.Forms.Label
$lblStatus.Text       = if ($ffmpegAvailable) { 'Listo.' } else { 'Aviso: ffmpeg.exe no encontrado. Calidad limitada.' }
$lblStatus.Location   = New-Object System.Drawing.Point(12, 210)
$lblStatus.Size       = New-Object System.Drawing.Size(678, 18)
$lblStatus.Anchor     = 'Top, Left, Right'
$form.Controls.Add($lblStatus)

# --- Log ---
$txtLog               = New-Object System.Windows.Forms.TextBox
$txtLog.Location      = New-Object System.Drawing.Point(12, 234)
$txtLog.Size          = New-Object System.Drawing.Size(678, 270)
$txtLog.Multiline     = $true
$txtLog.ScrollBars    = 'Vertical'
$txtLog.ReadOnly      = $true
$txtLog.BackColor     = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtLog.ForeColor     = [System.Drawing.Color]::FromArgb(220, 220, 220)
$txtLog.Font          = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Anchor        = 'Top, Bottom, Left, Right'
$form.Controls.Add($txtLog)

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
function Write-Log {
    param([string]$Text)
    if ($null -eq $Text) { return }
    $txtLog.AppendText($Text + [Environment]::NewLine)
}

# -----------------------------------------------------------------------------
# Load saved config
# -----------------------------------------------------------------------------
$cfg = Load-Config
if ($cfg) {
    if ($cfg.PSObject.Properties.Name -contains 'LastDest' -and -not [string]::IsNullOrWhiteSpace($cfg.LastDest)) {
        $txtDest.Text = $cfg.LastDest
    }
    if ($cfg.PSObject.Properties.Name -contains 'LastResolution') {
        $wanted = [string]$cfg.LastResolution
        for ($i = 0; $i -lt $resolutions.Count; $i++) {
            if ($resolutions[$i].Label -eq $wanted) { $cmbRes.SelectedIndex = $i; break }
        }
    }
    if ($cfg.PSObject.Properties.Name -contains 'LastUpdateCheck') {
        $script:lastUpdateCheck = $cfg.LastUpdateCheck
    }
}
if ([string]::IsNullOrWhiteSpace($txtDest.Text)) {
    $txtDest.Text = [Environment]::GetFolderPath('UserProfile') + '\Downloads'
}

# NotifyIcon for balloon notifications (system tray)
try {
    $script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    if ($null -ne $script:appIcon) { $script:notifyIcon.Icon = $script:appIcon }
    else { $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application }
    $script:notifyIcon.Text = 'YT Downloader'
    $script:notifyIcon.Visible = $true
    # Click on balloon -> open last destination folder
    $script:notifyIcon.add_BalloonTipClicked({
        $d = $script:lastDestForOpen
        if (-not [string]::IsNullOrWhiteSpace($d) -and (Test-Path -LiteralPath $d)) {
            try { [System.Diagnostics.Process]::Start('explorer.exe', $d) | Out-Null } catch { }
        }
    })
} catch {
    $script:notifyIcon = $null
}

# Auto-update check: max 1x/week, runs on background thread (never blocks UI).
function Start-UpdateCheck {
    if ($script:isUpdating -or $script:isRunning) { return }
    $shouldRun = $true
    if ($script:lastUpdateCheck) {
        try {
            $diff = (Get-Date) - [datetime]$script:lastUpdateCheck
            if ($diff.TotalDays -lt 7) { $shouldRun = $false }
        } catch { }
    }
    if (-not $shouldRun) { return }

    $script:isUpdating = $true
    $btnDownload.Enabled = $false
    $lblStatus.Text = 'Buscando actualizaciones de yt-dlp...'
    Write-Log '[Update] Verificando version de yt-dlp...'
    try {
        [YTD.Updater]::StartUpdate($ytdlpPath, $script:logQueue, 60000)
    } catch {
        Write-Log "[Update] No se pudo iniciar: $($_.Exception.Message)"
        $script:isUpdating = $false
        $btnDownload.Enabled = $true
        $lblStatus.Text = 'Listo.'
    }
}

# yt-dlp requires a JS runtime (default: deno) for full YouTube extraction.
# If deno.exe is missing from the install dir AND not on PATH, fetch it once
# in the background. Safe to call on every launch — exits early if not needed.
function Start-DenoInstall {
    if ($script:isInstallingDeno) { return }
    if ($null -ne (Resolve-DenoPath)) { return }
    if (-not ('YTD.DenoInstaller' -as [type])) { return }
    $script:isInstallingDeno = $true
    try {
        [YTD.DenoInstaller]::Install($scriptDir, $script:logQueue)
    } catch {
        Write-Log "[JS runtime] No se pudo iniciar la descarga de deno: $($_.Exception.Message)"
        $script:isInstallingDeno = $false
    }
}

# -----------------------------------------------------------------------------
# Download orchestration
# -----------------------------------------------------------------------------

function Detach-ProcHandlers {
    if ($null -ne $script:proc) {
        try {
            if ($null -ne $script:dataDelegate) {
                $script:proc.remove_OutputDataReceived($script:dataDelegate)
                $script:proc.remove_ErrorDataReceived($script:dataDelegate)
            }
            if ($null -ne $script:exitDelegate) {
                $script:proc.remove_Exited($script:exitDelegate)
            }
        } catch {}
    }
    $script:dataDelegate = $null
    $script:exitDelegate = $null
    $script:procSink     = $null
}

function Kill-Download {
    if ($null -ne $script:proc -and -not $script:proc.HasExited) {
        try {
            # /T kills child processes (ffmpeg), /F forces termination
            & taskkill.exe /T /F /PID $script:proc.Id 2>$null | Out-Null
        } catch {}
    }
}

function Reset-UIState {
    $script:isRunning      = $false
    $btnDownload.Enabled   = $true
    $btnCancel.Enabled     = $false
    $txtUrl.Enabled        = $true
    $txtDest.Enabled       = $true
    $cmbRes.Enabled        = $true
    $btnBrowse.Enabled     = $true
}

function Start-Download {
    if ($script:isRunning) { return }

    $url  = $txtUrl.Text.Trim()
    $dest = $txtDest.Text.Trim()

    if (-not (Test-IsValidUrl $url)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Ingresa una URL valida (http:// o https://).',
            'URL invalida',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        $txtUrl.Focus()
        return
    }

    if ([string]::IsNullOrWhiteSpace($dest)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Selecciona una carpeta destino.',
            'Carpeta faltante',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    if (-not (Test-Path -LiteralPath $dest)) {
        $create = [System.Windows.Forms.MessageBox]::Show(
            "La carpeta no existe:`n$dest`n`nCrearla?",
            'Crear carpeta',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($create -eq [System.Windows.Forms.DialogResult]::Yes) {
            try { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
            catch {
                [System.Windows.Forms.MessageBox]::Show("No se pudo crear: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
                return
            }
        } else { return }
    }

    $resIdx = $cmbRes.SelectedIndex
    if ($resIdx -lt 0) { $resIdx = 0 }
    $res = $resolutions[$resIdx]

    # Persist preferences + remember dest for balloon click
    $script:lastDestForOpen = $dest
    $cfgToSave = @{ LastDest = $dest; LastResolution = $res.Label }
    if ($script:lastUpdateCheck) { $cfgToSave.LastUpdateCheck = $script:lastUpdateCheck }
    Save-Config -Config $cfgToSave

    # Build argument list
    $argList = New-Object System.Collections.Generic.List[string]
    if ($ffmpegAvailable) {
        $argList.Add('--ffmpeg-location'); $argList.Add($scriptDir)
    }
    $argList.Add('--newline')          # progress on new lines (better log parsing)
    $argList.Add('--no-colors')        # strip ANSI escape codes
    $argList.Add('--no-mtime')         # use current time on output files
    $argList.Add('-P'); $argList.Add($dest)
    $argList.Add('-o'); $argList.Add('%(title).200B [%(id)s].%(ext)s')
    # Print final filepath after all post-processing — used to enable Play button
    $argList.Add('--print'); $argList.Add('after_move:filepath')

    if ($res.AudioOnly) {
        $argList.Add('-x')
        $argList.Add('--audio-format'); $argList.Add('mp3')
        $argList.Add('--audio-quality'); $argList.Add('0')
    } else {
        $argList.Add('-f'); $argList.Add($res.Format)
        if ($ffmpegAvailable) {
            # m4a audio preference (above) keeps this on mp4; mkv is a last resort
            # for the rare video lacking an m4a track (opus can't go in mp4).
            $argList.Add('--merge-output-format'); $argList.Add('mp4/mkv')
        }
    }

    # Point yt-dlp at the JS runtime if we have one (default is deno on PATH).
    # Passing an explicit path avoids the "No supported JavaScript runtime" warning
    # and unlocks the full set of YouTube formats.
    $resolvedDeno = Resolve-DenoPath
    if ($null -ne $resolvedDeno) {
        $argList.Add('--js-runtimes'); $argList.Add("deno:$resolvedDeno")
    }

    $argList.Add('--')                 # end of options; URL follows
    $argList.Add($url)

    # Build the quoted command line string (used for ProcessStartInfo.Arguments).
    $argString = ($argList | ForEach-Object { ConvertTo-CmdArg $_ }) -join ' '

    # Clear UI + reset per-download state
    $script:lastDownloadedFile = $null
    $btnPlay.Enabled = $false
    $txtLog.Clear()
    $progressBar.Value = 0
    $lblStatus.Text = 'Iniciando...'
    Write-Log "> yt-dlp $argString"
    Write-Log ''

    # Lock UI
    $script:isRunning     = $true
    $btnDownload.Enabled  = $false
    $btnCancel.Enabled    = $true
    $txtUrl.Enabled       = $false
    $txtDest.Enabled      = $false
    $cmbRes.Enabled       = $false
    $btnBrowse.Enabled    = $false

    # Drain any leftover queue
    $sink = ''
    while ($script:logQueue.TryDequeue([ref]$sink)) { }

    # Build process
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $ytdlpPath
    $psi.Arguments              = $argString
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.WorkingDirectory       = $scriptDir
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo          = $psi
    $proc.EnableRaisingEvents = $true
    $script:proc = $proc

    # Subscribe to .NET events DIRECTLY (bypasses PowerShell event subsystem,
    # which is starved while Application.Run blocks the runspace). Handlers
    # run on thread-pool threads and enqueue to the ConcurrentQueue.
    try {
        $sink = [YTD.ProcOutput]::new($script:logQueue)
        $dataDel = [System.Delegate]::CreateDelegate(
            [System.Diagnostics.DataReceivedEventHandler], $sink, 'OnData')
        $exitDel = [System.Delegate]::CreateDelegate(
            [System.EventHandler], $sink, 'OnExit')

        $proc.add_OutputDataReceived($dataDel)
        $proc.add_ErrorDataReceived($dataDel)
        $proc.add_Exited($exitDel)

        # Keep references alive to prevent GC of delegates and sink object
        $script:procSink     = $sink
        $script:dataDelegate = $dataDel
        $script:exitDelegate = $exitDel

        [void]$proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
    } catch {
        Write-Log ("Error iniciando proceso: " + $_.Exception.Message)
        Detach-ProcHandlers
        try { $proc.Dispose() } catch {}
        $script:proc = $null
        Reset-UIState
        return
    }
}

# -----------------------------------------------------------------------------
# UI pump: drains queue, updates log + progress
# -----------------------------------------------------------------------------
$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = 80

$timer.Add_Tick({
    $line = ''
    $reachedEnd = $false
    $updateExitCode = $null
    while ($script:logQueue.TryDequeue([ref]$line)) {

        if ($line -eq $script:exitSentinel) {
            $reachedEnd = $true
            continue
        }

        # Update output: "__YTD_UPDATE_OUT__::..."
        if ($line.StartsWith($script:updateOutPrefix)) {
            $msg = $line.Substring($script:updateOutPrefix.Length + 2)
            foreach ($l in ($msg -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($l)) { Write-Log "[Update] $l" }
            }
            continue
        }
        # Update done: "__YTD_UPDATE_DONE__::<exitCode>"
        if ($line.StartsWith($script:updateDonePrefix)) {
            $tail = $line.Substring($script:updateDonePrefix.Length + 2)
            $tmpCode = -1
            [void][int]::TryParse($tail, [ref]$tmpCode)
            $updateExitCode = $tmpCode
            continue
        }

        # Deno install output: "__YTD_DENO_OUT__::..."
        if ($line.StartsWith($script:denoOutPrefix)) {
            $msg = $line.Substring($script:denoOutPrefix.Length + 2)
            foreach ($l in ($msg -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($l)) { Write-Log "[JS runtime] $l" }
            }
            continue
        }
        # Deno install done: "__YTD_DENO_DONE__::<exitCode>"
        if ($line.StartsWith($script:denoDonePrefix)) {
            $script:isInstallingDeno = $false
            continue
        }

        # Strip stray carriage returns
        $clean = $line -replace "`r", ''

        # Parse progress: [download]   45.3% of  120.5MiB at ...
        if ($clean -match '^\[download\]\s+(\d+(?:\.\d+)?)%') {
            $pct = [int][double]$matches[1]
            if ($pct -lt 0) { $pct = 0 }
            if ($pct -gt 100) { $pct = 100 }
            $progressBar.Value = $pct
            $lblStatus.Text = $clean
        }
        elseif ($clean -match '^\[(Merger|ExtractAudio|VideoConvertor)\]') {
            $lblStatus.Text = $clean
        }
        # Capture final filepath (from --print after_move:filepath).
        # yt-dlp prints just the absolute path on its own line.
        elseif ($clean -match '^[A-Za-z]:[\\/].+\.[A-Za-z0-9]+$') {
            try {
                if (Test-Path -LiteralPath $clean) {
                    $script:lastDownloadedFile = $clean
                }
            } catch { }
        }

        Write-Log $clean
    }

    # Update flow completion
    if ($null -ne $updateExitCode) {
        $script:isUpdating = $false
        $script:lastUpdateCheck = (Get-Date).ToString('o')
        Save-Config -Config @{
            LastDest        = $txtDest.Text
            LastResolution  = $resolutions[[Math]::Max(0,$cmbRes.SelectedIndex)].Label
            LastUpdateCheck = $script:lastUpdateCheck
        }
        if ($updateExitCode -eq 0) {
            Write-Log '[Update] Verificacion completada.'
        } else {
            Write-Log "[Update] Verificacion termino con codigo $updateExitCode (continuando con version actual)."
        }
        if (-not $script:isRunning) {
            $btnDownload.Enabled = $true
            $lblStatus.Text = 'Listo.'
        }
    }

    if ($reachedEnd) {
        $exitCode = -1
        if ($null -ne $script:proc) {
            try { $exitCode = $script:proc.ExitCode } catch {}
        }
        $logText = $txtLog.Text
        if ($exitCode -eq 0) {
            $progressBar.Value = 100
            $lblStatus.Text = 'Descarga completada.'
            Write-Log ''
            Write-Log '=== Descarga completada con exito ==='
            if ($null -ne $script:lastDownloadedFile) { $btnPlay.Enabled = $true }
            Show-Notification -Title 'YT Downloader' -Body 'Tu descarga termino. Click aqui para abrir la carpeta.' -Kind 'Info'
        } else {
            $friendly = Get-FriendlyError -ExitCode $exitCode -LogText $logText
            $lblStatus.Text = $friendly
            Write-Log ''
            Write-Log "=== Proceso finalizado con codigo $exitCode ==="
            Write-Log "=== $friendly ==="
            Show-Notification -Title 'YT Downloader - Problema' -Body $friendly -Kind 'Warning'
        }
        Detach-ProcHandlers
        if ($null -ne $script:proc) {
            try { $script:proc.Dispose() } catch {}
            $script:proc = $null
        }
        Reset-UIState
    }
})
$timer.Start()

# -----------------------------------------------------------------------------
# Event handlers
# -----------------------------------------------------------------------------

$btnPaste.Add_Click({
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $txt = [System.Windows.Forms.Clipboard]::GetText().Trim()
            if (-not [string]::IsNullOrWhiteSpace($txt)) { $txtUrl.Text = $txt }
        }
    } catch {}
})

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Selecciona carpeta destino'
    if (-not [string]::IsNullOrWhiteSpace($txtDest.Text) -and (Test-Path -LiteralPath $txtDest.Text)) {
        $dlg.SelectedPath = $txtDest.Text
    }
    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtDest.Text = $dlg.SelectedPath
    }
})

$btnOpenFolder.Add_Click({
    $dest = $txtDest.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($dest) -and (Test-Path -LiteralPath $dest)) {
        # Resolve to canonical full path; quote for explorer.exe arg parsing.
        $full = (Resolve-Path -LiteralPath $dest).ProviderPath
        [System.Diagnostics.Process]::Start('explorer.exe', "`"$full`"") | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show('La carpeta destino no existe.', 'Aviso', 'OK', 'Information') | Out-Null
    }
})

$btnDownload.Add_Click({ Start-Download })

$btnCancel.Add_Click({
    if ($script:isRunning) {
        $lblStatus.Text = 'Cancelando...'
        Kill-Download
    }
})

$btnPlay.Add_Click({
    $f = $script:lastDownloadedFile
    if (-not [string]::IsNullOrWhiteSpace($f) -and (Test-Path -LiteralPath $f)) {
        try {
            [System.Diagnostics.Process]::Start($f) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "No se pudo abrir el archivo:`n$($_.Exception.Message)",
                'Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    } else {
        $btnPlay.Enabled = $false
        [System.Windows.Forms.MessageBox]::Show(
            'El archivo ya no existe en su ubicacion original.',
            'Archivo no encontrado',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
})

# URL site detection — appends "[host]" to the URL label on TextChanged
$txtUrl.add_TextChanged({
    $u = $txtUrl.Text.Trim()
    if (Test-IsValidUrl $u) {
        try {
            $h = ([System.Uri]$u).Host -replace '^www\.', ''
            $lblUrl.Text = "URL del video o playlist:    [sitio: $h]"
        } catch {
            $lblUrl.Text = 'URL del video o playlist:'
        }
    } else {
        $lblUrl.Text = 'URL del video o playlist:'
    }
})

# Drag-and-drop URL support (from browser address bar, plain text, etc.)
$dragEnterHandler = [System.Windows.Forms.DragEventHandler]{
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::UnicodeText) -or
        $e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::Text)) {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    } else {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::None
    }
}
$dragDropHandler = [System.Windows.Forms.DragEventHandler]{
    param($s, $e)
    $text = $null
    try {
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::UnicodeText)) {
            $text = [string]$e.Data.GetData([System.Windows.Forms.DataFormats]::UnicodeText)
        } elseif ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::Text)) {
            $text = [string]$e.Data.GetData([System.Windows.Forms.DataFormats]::Text)
        }
    } catch { return }
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    # Some browsers send "url<newline>title" — keep first line only
    $first = ($text -split "`r?`n", 2)[0].Trim()
    if (Test-IsValidUrl $first) { $txtUrl.Text = $first }
}
$form.AllowDrop   = $true
$txtUrl.AllowDrop = $true
$form.add_DragEnter($dragEnterHandler)
$form.add_DragDrop($dragDropHandler)
$txtUrl.add_DragEnter($dragEnterHandler)
$txtUrl.add_DragDrop($dragDropHandler)

# On show: auto-paste URL from clipboard + trigger update check (gated to 1x/week)
$form.Add_Shown({
    if ([string]::IsNullOrWhiteSpace($txtUrl.Text)) {
        try {
            if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                $clip = [System.Windows.Forms.Clipboard]::GetText().Trim()
                if (Test-IsValidUrl $clip) { $txtUrl.Text = $clip }
            }
        } catch {}
    }
    $txtUrl.Focus()
    Start-UpdateCheck
    Start-DenoInstall
})

# Clean shutdown
$form.Add_FormClosing({
    param($sender, $e)
    if ($script:isRunning) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            'Hay una descarga en curso. Cancelar y salir?',
            'Confirmar salida',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            $e.Cancel = $true
            return
        }
        Kill-Download
    }
    try { $timer.Stop() } catch {}
    Detach-ProcHandlers
    if ($null -ne $script:proc) {
        try { $script:proc.Dispose() } catch {}
        $script:proc = $null
    }
    # Cleanup tray icon so it disappears immediately (not after mouse-hover)
    if ($null -ne $script:notifyIcon) {
        try { $script:notifyIcon.Visible = $false; $script:notifyIcon.Dispose() } catch {}
        $script:notifyIcon = $null
    }
    if ($null -ne $script:appIcon) {
        try { $script:appIcon.Dispose() } catch {}
        $script:appIcon = $null
    }
})

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------
[System.Windows.Forms.Application]::Run($form)
