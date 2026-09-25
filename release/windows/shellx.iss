; ShellX desktop agent installer (Inno Setup 6).
; Compiled by release/windows/build-installer.ps1:
;   ISCC.exe /DAppVersion=1.0.0 /DSourceDir=<flutter Release folder>
;            /DOutputDir=<folder> [/DAppIcon=<app_icon.ico>] release\windows\shellx.iss
; Output: <OutputDir>\ShellX-Setup-<AppVersion>.exe

#ifndef AppVersion
  #error Define AppVersion, for example /DAppVersion=1.0.0
#endif
#ifndef SourceDir
  #error Define SourceDir (apps\desktop\build\windows\x64\runner\Release)
#endif
; apps/desktop (plan 04) builds ShellX.exe.
#define AppExeName "ShellX.exe"
#ifndef OutputDir
  #define OutputDir "dist"
#endif

[Setup]
; AppId identifies ShellX for upgrades and uninstall. Never change it.
AppId={{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE}
AppName=ShellX
AppVersion={#AppVersion}
AppVerName=ShellX {#AppVersion}
AppPublisher=ShellX
AppPublisherURL=https://shellx.pro/
AppSupportURL=https://shellx.pro/
AppUpdatesURL=https://shellx.pro/
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\ShellX
DefaultGroupName=ShellX
DisableProgramGroupPage=yes
; Per-user install, no UAC prompt: the agent runs as a normal user (spec 8.5).
PrivilegesRequired=lowest
; Windows 10 version 1809 (build 17763) is the first release with ConPTY (spec 3.1).
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=ShellX-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=ShellX
UninstallDisplayIcon={app}\{#AppExeName}
; The agent is stopped explicitly in PrepareToInstall; no Restart Manager prompt needed.
CloseApplications=no
; Pick the language from the Windows UI language; ask only when neither matches.
ShowLanguageDialog=auto
#ifdef AppIcon
SetupIconFile={#AppIcon}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; Unofficial translation from jrsoftware/issrc tag is-6_7_1 (Files/Languages/Unofficial/Vietnamese.isl),
; vendored next to this script; its SHA-256 is pinned in release/tests/inno.test.mjs.
Name: "vietnamese"; MessagesFile: "Vietnamese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\ShellX"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\ShellX"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,ShellX}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop the tray agent so its files can be deleted.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM ""{#AppExeName}"""; Flags: runhidden; RunOnceId: "StopShellX"

[UninstallDelete]
; The agent's per-user data folder: flutter_secure_storage's DPAPI-encrypted file (device key,
; access token, trusted-phone list) and shared_preferences settings. CompanyName is "pro.shellx",
; ProductName "ShellX" (Runner.rc, plan 04); path_provider's application-support directory
; resolves to %APPDATA%\pro.shellx\ShellX (confirmed in plan 04's Task 1).
Type: filesandordirs; Name: "{userappdata}\pro.shellx\ShellX"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  { Stop a running agent: it keeps its exe and DLLs locked. Its terminal sessions end,
    exactly as when the agent quits (spec 7). }
  if not Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM "{#AppExeName}"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Log('taskkill could not be started');
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  { launch_at_startup (apps/desktop) registers the HKCU Run value "ShellX". }
  if CurUninstallStep = usPostUninstall then
    if not RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'ShellX') then
      Log('No ShellX Run value to remove');
end;
