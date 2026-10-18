; ShellX 2 (native) installer, Inno Setup 6.7.1. Unsigned, per-user, coexists with the Flutter ShellX.
; Compiled by windows/installer/build-installer.ps1:
;   ISCC.exe /DAppVersion=2.0.0 /DSourceDir=<folder with shellx-desktop.exe> /DOutputDir=<folder>
;            [/DAppIcon=<app_icon.ico>] shellx-native.iss
; Output: <OutputDir>\ShellX-Setup-<AppVersion>-sprint.exe
; Coexistence with the Flutter app is checked by check_coexistence.py: nothing here may share its
; AppId, exe name, install dir, Start-menu name or data dirs, and nothing may stop or delete them.

#ifndef AppVersion
  #error Define AppVersion, for example /DAppVersion=2.0.0
#endif
#ifndef SourceDir
  #error Define SourceDir (the folder holding shellx-desktop.exe)
#endif
#define AppExeName "shellx-desktop.exe"
#define ShortcutName "ShellX 2 (thử nghiệm)"
#ifndef OutputDir
  #define OutputDir "dist"
#endif

[Setup]
; AppId identifies ShellX 2 for upgrades and uninstall. Never change it.
AppId={{D322DA97-3B0D-49C7-BDB2-8EBFADBA1004}
AppName=ShellX 2
AppVersion={#AppVersion}
AppVerName=ShellX 2 {#AppVersion}
AppPublisher=ShellX
AppPublisherURL=https://shellx.pro/
AppSupportURL=https://shellx.pro/
AppUpdatesURL=https://shellx.pro/
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\ShellX Native
DefaultGroupName=ShellX 2
DisableProgramGroupPage=yes
; Per-user install, no UAC prompt.
PrivilegesRequired=lowest
; Windows 10 version 1809 (build 17763) is the first release with ConPTY.
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=ShellX-Setup-{#AppVersion}-sprint
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=ShellX 2
UninstallDisplayIcon={app}\{#AppExeName}
; Restart Manager only closes processes holding files this installer replaces (our own exe).
CloseApplications=yes
ShowLanguageDialog=auto
#ifdef AppIcon
SetupIconFile={#AppIcon}
#endif

[Languages]
Name: "vietnamese"; MessagesFile: "Vietnamese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#ShortcutName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#ShortcutName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,ShellX 2}"; Flags: nowait postinstall skipifsilent

; No [UninstallDelete] or [InstallDelete]: only {app} is removed. User state in
; %LOCALAPPDATA%\ShellX\native stays after uninstall; delete that folder by hand to remove it.
