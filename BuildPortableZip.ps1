# BuildPortableZip.ps1 — Empaqueta la app en "YT Downloader Portable.zip"
# No requiere herramientas externas (usa Compress-Archive nativo).
# El destinatario extrae el ZIP y ejecuta Setup.bat una vez.

$d = $PSScriptRoot
$requiredFiles = @(
    'yt-dlp.exe',
    'ffmpeg.exe',
    'ffprobe.exe',
    'deno.exe',
    'YTDownloader.ps1',
    'Launch.bat',
    'Setup.ps1',
    'Setup.bat',
    'app.ico'
)

$files = @()
$missing = @()
foreach ($f in $requiredFiles) {
    $path = Join-Path $d $f
    if (Test-Path $path) { $files += $path }
    else { $missing += $f }
}

# Incluir DLL cache si existe (opcional)
$dll = Join-Path $d 'YTD.cache.dll'
if (Test-Path $dll) { $files += $dll }

# Incluir runtime JS si esta presente (opcional, evita el warning de yt-dlp).
# Si falta, la app lo descarga sola al primer arranque.
$deno = Join-Path $d 'deno.exe'
if (Test-Path $deno) { $files += $deno }

if ($missing.Count -gt 0) {
    Write-Host "[ERROR] Faltan archivos:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Revisa que todos los archivos esten en: $d"
    Read-Host "Presiona Enter para salir"
    exit 1
}

$out = Join-Path $d 'YT Downloader Portable.zip'
if (Test-Path $out) { Remove-Item $out -Force }

try {
    Compress-Archive -Path $files -DestinationPath $out -CompressionLevel Optimal -ErrorAction Stop
    $sz = (Get-Item $out).Length
    Write-Host "[OK] Generado: $out" -ForegroundColor Green
    Write-Host ("Tamano: {0:N1} MB" -f ($sz / 1MB))
    Write-Host ("Archivos incluidos: {0}" -f $files.Count)
} catch {
    Write-Host "[ERROR] No se pudo crear el ZIP: $_" -ForegroundColor Red
}

Read-Host "Presiona Enter para salir"
