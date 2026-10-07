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
; A7 D8: the uninstaller removes our entry from the user's Path; this makes it broadcast
; WM_SETTINGCHANGE so Explorer and new terminals stop seeing it.
ChangesEnvironment=yes
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
; Terminal sharing (spec 10.6): remove the ShellX block from the PowerShell profiles and delete
; %LOCALAPPDATA%\ShellX\bin and \term. Works whether or not the agent still runs (it takes no lock
; and opens no window), so the order against the taskkill above does not matter.
Filename: "{app}\{#AppExeName}"; Parameters: "--terminal-sharing-cleanup"; Flags: runhidden waituntilterminated; RunOnceId: "TerminalSharingCleanup"

[UninstallDelete]
; The agent's per-user data folder: flutter_secure_storage's DPAPI-encrypted file (device key,
; access token, trusted-phone list) and shared_preferences settings. CompanyName is "pro.shellx",
; ProductName "ShellX" (Runner.rc, plan 04); path_provider's application-support directory
; resolves to %APPDATA%\pro.shellx\ShellX (confirmed in plan 04's Task 1).
Type: filesandordirs; Name: "{userappdata}\pro.shellx\ShellX"
; Terminal sharing's folders, in case --terminal-sharing-cleanup could not delete them (a
; shellx-term.exe that was still running then has exited by now).
Type: filesandordirs; Name: "{localappdata}\ShellX\bin"
Type: filesandordirs; Name: "{localappdata}\ShellX\term"
; A5a D22: saved session layout and terminal contents.
Type: filesandordirs; Name: "{localappdata}\ShellX\restore"
; A7 D7: the shellx command (a copy of shellx-term.exe); its Path entry goes in
; CurUninstallStepChanged.
Type: filesandordirs; Name: "{localappdata}\ShellX\cli"
; A5b D5 / A7 D30: the command-line host's endpoint and lock (the running host removes its
; endpoint when it stops; the folder stays).
Type: filesandordirs; Name: "{localappdata}\ShellX\mux"

[Code]
const
  { A5a I1: how long a running agent gets to save and quit on its own, and how often to look. }
  QuitWaitMs = 8000;
  QuitPollMs = 250;

{ True while ShellX.exe runs for this user: tasklist lists it, find matches it (exit code 0). }
function ShellXRunning(): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'),
    '/C tasklist /FI "IMAGENAME eq {#AppExeName}" /NH | find /I "{#AppExeName}"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

{ Waits up to QuitWaitMs, looking every QuitPollMs, until ShellX.exe is gone. }
procedure WaitForShellXToQuit();
var
  Start: DWord;
begin
  Start := GetTickCount;
  while ShellXRunning() and (GetTickCount - Start < QuitWaitMs) do
    Sleep(QuitPollMs);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  { A5a I1: ask a running agent to quit first. It watches quit.signal in its single-instance
    folder (path_provider's application-support directory, %APPDATA%\pro.shellx\ShellX, as in
    [UninstallDelete]) and quits as for the Windows Restart Manager: it saves its sessions as a
    clean exit, so the next launch restores them without the "closed unexpectedly" strip. }
  if ShellXRunning() then
  begin
    if SaveStringToFile(ExpandConstant('{userappdata}\pro.shellx\ShellX\quit.signal'), 'update', False) then
      WaitForShellXToQuit()
    else
      Log('quit signal could not be written');
  end;
  { Fallback: stop an agent that is still running: it keeps its exe and DLLs locked. Its terminal
    sessions end, exactly as when the agent quits (spec 7). }
  if not Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM "{#AppExeName}"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Log('taskkill could not be started');
  Result := '';
end;

{ A7 D8: "Install the shellx command for all terminals..." added the cli folder to the user's
  own Path (HKCU\Environment, REG_EXPAND_SZ). Drops every entry naming it (case-insensitive, a
  trailing backslash ignored), each with one separator; every other byte stays, empty entries
  included. Writes back only when it changed. }
procedure RemoveCliFromUserPath();
var
  OldPath, NewPath, Entry, Dir: String;
  P: Integer;
  Changed, First: Boolean;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OldPath) then
    exit;
  Dir := ExpandConstant('{localappdata}\ShellX\cli');
  NewPath := '';
  Changed := False;
  First := True;
  { One more separator than entries: the loop sees every entry, the last one too. }
  OldPath := OldPath + ';';
  while OldPath <> '' do
  begin
    P := Pos(';', OldPath);
    Entry := Copy(OldPath, 1, P - 1);
    Delete(OldPath, 1, P);
    if CompareText(RemoveBackslashUnlessRoot(Entry), Dir) = 0 then
      Changed := True
    else
    begin
      if not First then
        NewPath := NewPath + ';';
      NewPath := NewPath + Entry;
      First := False;
    end;
  end;
  if Changed then
    if not RegWriteExpandStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', NewPath) then
      Log('Path could not be updated');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveCliFromUserPath();
  { launch_at_startup (apps/desktop) registers the HKCU Run value "ShellX". }
  if CurUninstallStep = usPostUninstall then
    if not RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'ShellX') then
      Log('No ShellX Run value to remove');
end;
