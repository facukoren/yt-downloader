# BuildPortableZip.ps1 — Empaqueta la app en "YT Downloader Portable.zip"
# No requiere herramientas externas (usa Compress-Archive nativo).
# El destinatario extrae el ZIP y ejecuta Setup.bat una vez.

$d = $PSScriptRoot
$requiredFiles = @(
    'yt-dlp.exe',
    'ffmpeg.exe',
    'ffprobe.exe',
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
    if (Test-Path -LiteralPath $path) { $files += $path }
    else { $missing += $f }
}

# Archivos opcionales: DLL cache + su hash, y el runtime JS (deno). Si el
# runtime falta, la app lo descarga sola al primer arranque.
foreach ($opt in @('YTD.cache.dll', 'YTD.cache.hash', 'deno.exe')) {
    $path = Join-Path $d $opt
    if (Test-Path -LiteralPath $path) { $files += $path }
}

if ($missing.Count -gt 0) {
    Write-Host "[ERROR] Faltan archivos:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Revisa que todos los archivos esten en: $d"
    Read-Host "Presiona Enter para salir"
    exit 1
}

$out = Join-Path $d 'YT Downloader Portable.zip'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

try {
    Compress-Archive -LiteralPath $files -DestinationPath $out -CompressionLevel Optimal -ErrorAction Stop
    $sz = (Get-Item $out).Length
    Write-Host "[OK] Generado: $out" -ForegroundColor Green
    Write-Host ("Tamano: {0:N1} MB" -f ($sz / 1MB))
    Write-Host ("Archivos incluidos: {0}" -f $files.Count)
} catch {
    Write-Host "[ERROR] No se pudo crear el ZIP: $_" -ForegroundColor Red
}

Read-Host "Presiona Enter para salir"
