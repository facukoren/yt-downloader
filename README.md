# YT Downloader

Descargador de videos de YouTube para Windows con UI gráfica. Plug-and-play, sin dependencias externas, sin línea de comandos.

![Status](https://img.shields.io/badge/status-stable-brightgreen) ![Platform](https://img.shields.io/badge/platform-Windows%2010%2B-blue) ![License](https://img.shields.io/badge/license-MIT-lightgrey)

## Para usuarios finales

**Descarga el instalador** desde la página de [Releases](../../releases/latest):
- `Instalar YT Downloader.exe` (~103 MB) — instalador único, doble-click e instala
- `YT Downloader Portable.zip` (~155 MB) — portable, sin instalación

Después: doble-click en `Descargar Videos` del escritorio → pegar URL → Descargar.

### Capacidades
- Videos individuales y playlists de YouTube (y 1000+ sitios soportados por yt-dlp)
- Resoluciones desde 360p hasta 4K + modo "solo audio MP3"
- Drag & drop URL desde browser
- Auto-pega URL del clipboard al abrir
- Progress bar + logs en vivo
- Botón Reproducir abre archivo al terminar
- Notificaciones de sistema cuando completa
- Auto-actualiza yt-dlp 1x/semana (silencioso, background)
- Auto-descarga runtime JS (`deno.exe`) al primer arranque si falta — requerido por yt-dlp para extraccion completa de YouTube
- Mensajes de error en español plano (video privado, sin internet, etc.)

## Para desarrolladores

### Estructura
```
YTDownloader.ps1      App principal (WinForms, ~940 líneas PS5.1)
Launch.bat            Lanzador (powershell -File ...)
Setup.ps1 / Setup.bat First-run: genera icono, desbloquea archivos, crea shortcut
installer.iss         Inno Setup script (per-user, sin admin)
BuildInstaller.bat    Compila installer.iss → "Instalar YT Downloader.exe"
BuildPortableZip.ps1  Empaqueta ZIP portable
BuildPortableZip.bat  Wrapper del .ps1
```

### Build desde fuente

**Requisitos:**
- Windows 10+
- PowerShell 5.1+ (built-in)
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (para installer .exe)
- Binarios externos (no incluidos en repo, ver abajo)

**Binarios necesarios** (poner en raíz del proyecto):
- `yt-dlp.exe` — https://github.com/yt-dlp/yt-dlp/releases
- `ffmpeg.exe` + `ffprobe.exe` — https://www.gyan.dev/ffmpeg/builds/ (release essentials)
- `deno.exe` — https://github.com/denoland/deno/releases (runtime JS; YouTube lo requiere para extraer formatos)

**Binario opcional** (si falta, la app lo descarga sola al primer arranque):
- `deno.exe` — https://github.com/denoland/deno/releases (runtime JS requerido por yt-dlp para extracción completa de YouTube)

**Compilar:**
```bat
BuildInstaller.bat       # genera "Instalar YT Downloader.exe"
BuildPortableZip.bat     # genera "YT Downloader Portable.zip"
```

### Arquitectura técnica

**UI:** WinForms via PowerShell. Sin dependencias .NET externas, todo en runtime built-in.

**Subprocess streaming:** Helper C# (`YTD.ProcOutput` + `YTD.Updater`) compilado a `YTD.cache.dll`. Bypass del PowerShell event subsystem (que se starva durante `Application.Run`), suscribe delegates `.NET` directos a `OutputDataReceived`/`ErrorDataReceived`/`Exited`. Líneas van a `ConcurrentQueue<string>`, drenadas por WinForms `Timer` cada 80ms — actualiza UI desde UI thread vía message pump.

**Quoting argv:** `ConvertTo-CmdArg` implementa algoritmo canónico `CommandLineToArgvW` (loop-based, sin regex MatchEvaluator que rompe en PS 5.1).

**Cancelación:** `taskkill /T /F /PID` mata yt-dlp + ffmpeg hijo.

**JS runtime:** YouTube requiere ejecutar JS para extraer formatos. Se bundlea `deno.exe`; el scriptDir se inyecta al PATH del subproceso (`ProcessStartInfo.EnvironmentVariables`) para que yt-dlp lo auto-detecte. Sin esto, faltan formatos H.264/AAC y el output cae a MKV.

**Salida MP4:** los selectores de formato prefieren audio `m4a` (`bestvideo*+bestaudio[ext=m4a]/...`) para que el merge produzca MP4 limpio. El audio `opus` fuerza fallback a MKV (ffmpeg lo marca experimental en contenedor MP4).

**Captura filepath final:** `--print after_move:filepath` de yt-dlp, regex `^[A-Za-z]:[\\/].+\.[A-Za-z0-9]+$` en timer tick, `Test-Path` para validar.

**JS runtime (deno):** yt-dlp requiere un runtime JavaScript para extraer todos los formatos de YouTube (subsistema EJS). Al arrancar, la app busca `deno.exe` junto al script y en `PATH`; si no lo encuentra, lo descarga en background (`https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip`) via `WebClient`+`ZipArchive` desde un Thread .NET (mismo patrón que el auto-update de yt-dlp). Cuando está disponible, se pasa `--js-runtimes deno:<path>` a yt-dlp.

## Licencia

MIT. Binarios embebidos (yt-dlp, ffmpeg) tienen sus propias licencias (Unlicense y LGPL respectivamente).
