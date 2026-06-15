; =============================================================================
; YT Downloader - Inno Setup installer script
;
; Per-user install, no admin required, fully reversible via uninstaller.
; Default install path: %LocalAppData%\YT Downloader
; Compile with: BuildInstaller.bat  (or run ISCC.exe directly on this file)
; =============================================================================

#define AppName        "YT Downloader"
#define AppVersion     "1.0.0"
#define AppPublisher   "YT Downloader"
#define AppExeName     "YTDownloader.ps1"
#define ShortcutName   "Descargar Videos"

[Setup]
AppId={{4F8D7B12-3C4E-4A77-9B6E-1F2D8A0E5C99}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=.
OutputBaseFilename=Instalar YT Downloader
Compression=lzma2/ultra64
SolidCompression=yes
SetupIconFile=app.ico
UninstallDisplayIcon={app}\app.ico
WizardStyle=modern
ShowLanguageDialog=auto
AllowNoIcons=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=force
RestartApplications=no

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";  Description: "Crear acceso directo en el {cm:MyEscritorio}"; GroupDescription: "{cm:MyShortcutGroup}"; Flags: checkedonce

[CustomMessages]
spanish.MyEscritorio=escritorio
spanish.MyShortcutGroup=Accesos directos:
spanish.MyLaunch=Iniciar YT Downloader ahora
english.MyEscritorio=desktop
english.MyShortcutGroup=Shortcuts:
english.MyLaunch=Launch YT Downloader now

[Files]
Source: "yt-dlp.exe";        DestDir: "{app}"; Flags: ignoreversion
Source: "ffmpeg.exe";        DestDir: "{app}"; Flags: ignoreversion
Source: "ffprobe.exe";       DestDir: "{app}"; Flags: ignoreversion
Source: "YTDownloader.ps1";  DestDir: "{app}"; Flags: ignoreversion
Source: "Launch.bat";        DestDir: "{app}"; Flags: ignoreversion
Source: "Setup.ps1";         DestDir: "{app}"; Flags: ignoreversion
Source: "Setup.bat";         DestDir: "{app}"; Flags: ignoreversion
Source: "app.ico";           DestDir: "{app}"; Flags: ignoreversion
Source: "YTD.cache.dll";     DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
; Optional JS runtime for yt-dlp (full YouTube extraction). If absent at build
; time the app downloads it on first launch.
Source: "deno.exe";          DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{userdesktop}\{#ShortcutName}"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ""{app}\{#AppExeName}"""; \
    WorkingDir: "{app}"; \
    IconFilename: "{app}\app.ico"; \
    Comment: "YT Downloader - Descargar videos de YouTube"; \
    Tasks: desktopicon
Name: "{userprograms}\{#AppName}\{#ShortcutName}"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ""{app}\{#AppExeName}"""; \
    WorkingDir: "{app}"; \
    IconFilename: "{app}\app.ico"; \
    Comment: "YT Downloader - Descargar videos de YouTube"
Name: "{userprograms}\{#AppName}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ""{app}\{#AppExeName}"""; \
    WorkingDir: "{app}"; \
    Flags: nowait postinstall skipifsilent; \
    Description: "{cm:MyLaunch}"

[UninstallDelete]
; Remove user-generated files inside install dir on uninstall
Type: files;       Name: "{app}\config.json"
Type: files;       Name: "{app}\YTD.cache.dll"
; deno.exe may be downloaded post-install; clean it up too.
Type: files;       Name: "{app}\deno.exe"
Type: dirifempty;  Name: "{app}"
