; =============================================================================
;  涂想 Doodle  —  Inno Setup 6 installer script
;  FULLY OFFLINE: no download pages, no update check, no online code.
;  Compile:  iscc /DAppVer=2.0.0 installer\setup.iss   (from the repo root)
;            or just run:  powershell -File installer\build_installer.ps1
; =============================================================================

; -----------------------------------------------------------------------------
;  ONE-LINE KNOB: the exe file name produced by `flutter build windows`
;  (CMake BINARY_NAME).  >>> CHANGE THIS LINE ONLY if you rename the binary <<<
; -----------------------------------------------------------------------------
#define MyAppExeName "doodle.exe"

#define MyAppName      "涂想 Doodle"
#define MyAppPublisher "LazyAwen"
#define MyAppId        "com.lazyawen.Doodle"   ; stable id; Inno appends "_is1"
#define MyAppURL       ""                      ; offline app -> no URLs at all
#define MyReleaseDir   "..\build\windows\x64\runner\Release"

; OutputDir is resolved relative to THIS script's directory, so "output"
; => D:\Work\scribble-pad\installer\output
#define MyOutputDir    "output"

; -----------------------------------------------------------------------------
;  Version: overridable on the command line with  iscc /DAppVer=x.y.z
;  build_installer.ps1 always passes it, read from pubspec.yaml.
; -----------------------------------------------------------------------------
#ifndef AppVer
  #define AppVer "1.0.0"
#endif

; -----------------------------------------------------------------------------
;  Exe detection: prefer MyAppExeName, fall back to the old scribble_pad.exe.
; -----------------------------------------------------------------------------
#if FileExists(MyReleaseDir + "\" + MyAppExeName)
  #define MyAppExe MyAppExeName
#elif FileExists(MyReleaseDir + "\scribble_pad.exe")
  #define MyAppExe "scribble_pad.exe"
#else
  #error Build output missing: no .exe under build\windows\x64\runner\Release. Run: flutter build windows --release
#endif

; -----------------------------------------------------------------------------
;  Optional extras, only included when the file really exists.
; -----------------------------------------------------------------------------
#if FileExists("..\windows\runner\resources\app_icon.ico")
  #define HasSetupIcon "1"
#endif
#if FileExists("..\README.md")
  #define HasReadme "1"
#endif
#if FileExists("C:\Users\Awen\AppData\Local\Programs\Inno Setup 6\Languages\ChineseSimplified.isl")
  #define HasChinese "1"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#AppVer}
AppVerName={#MyAppName} {#AppVer}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
VersionInfoVersion={#AppVer}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; NOTE: DisableDirPage is deliberately NOT set — the user must pick the path.
OutputDir={#MyOutputDir}
OutputBaseFilename=DoodleSetup-{#AppVer}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
; lets a non-admin install into {localappdata}\Programs instead of failing
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayName={#MyAppName} {#AppVer}
AllowNoIcons=yes
#ifdef HasSetupIcon
SetupIconFile=..\windows\runner\resources\app_icon.ico
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
#ifdef HasChinese
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"; Flags: checkedonce

[Files]
Source: "{#MyReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef HasReadme
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
#endif

[Icons]
; Start Menu shortcut (always). Inno auto-adds the uninstall icon to this group.
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"
; Desktop shortcut (optional task, default ON)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent
