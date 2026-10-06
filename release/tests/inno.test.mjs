// Static checks on the Inno Setup script. The script is compiled for real on Windows by
// release-desktop.yml (there is no CI, decision V5); these checks pin the spec values.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const iss = readFileSync(new URL('../windows/shellx.iss', import.meta.url), 'utf8');
const vietnamese = readFileSync(new URL('../windows/Vietnamese.isl', import.meta.url));

test('installer file name is ShellX-Setup-<version>.exe (what the website and relay link to)', () => {
  assert.match(iss, /^OutputBaseFilename=ShellX-Setup-\{#AppVersion\}$/m);
});

test('installer targets Windows 10 1809+ on x64 and installs per user without UAC', () => {
  assert.match(iss, /^MinVersion=10\.0\.17763$/m);
  assert.match(iss, /^PrivilegesRequired=lowest$/m);
  assert.match(iss, /^ArchitecturesAllowed=x64compatible$/m);
  assert.match(iss, /^ArchitecturesInstallIn64BitMode=x64compatible$/m);
});

test('installs ShellX.exe, the executable apps/desktop builds', () => {
  assert.match(iss, /^#define AppExeName "ShellX\.exe"$/m);
});

test('installer offers English and the pinned Vietnamese translation', () => {
  assert.match(iss, /^Name: "english"; MessagesFile: "compiler:Default\.isl"$/m);
  assert.match(iss, /^Name: "vietnamese"; MessagesFile: "Vietnamese\.isl"$/m);
  assert.equal(
    createHash('sha256').update(vietnamese).digest('hex'),
    '826bc509b612d96ccfec89b81956640a3b56b547d194404e5ff95ae1a85babf0',
    'Vietnamese.isl must be the file from jrsoftware/issrc tag is-6_7_1',
  );
});

test('AppId is fixed so upgrades replace the existing install', () => {
  assert.match(iss, /^AppId=\{\{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE\}$/m);
});

test('a running agent is stopped before files are replaced and before uninstall', () => {
  assert.match(iss, /function PrepareToInstall[\s\S]*?taskkill\.exe[\s\S]*?\/F \/T \/IM/);
  assert.match(iss, /\[UninstallRun\][^[]*taskkill\.exe[^[]*\/F \/T \/IM/);
});

test('uninstall removes the agent\'s per-user data folder (device key, trusted-phone list, settings)', () => {
  assert.match(iss, /\[UninstallDelete\][^[]*Type: filesandordirs; Name: "\{userappdata\}\\pro\.shellx\\ShellX"/);
});

test('uninstall cleans up terminal sharing (spec 10.6): blocks via ShellX.exe, then bin and term', () => {
  assert.match(
    iss,
    /\[UninstallRun\][^[]*Filename: "\{app\}\\\{#AppExeName\}"; Parameters: "--terminal-sharing-cleanup"; Flags: runhidden waituntilterminated/,
  );
  assert.match(iss, /\[UninstallDelete\][^[]*Name: "\{localappdata\}\\ShellX\\bin"/);
  assert.match(iss, /\[UninstallDelete\][^[]*Name: "\{localappdata\}\\ShellX\\term"/);
});

test('uninstall removes the launch-at-login registry value', () => {
  assert.ok(
    iss.includes("RegDeleteValue(HKEY_CURRENT_USER, 'Software\\Microsoft\\Windows\\CurrentVersion\\Run', 'ShellX')"),
    'missing RegDeleteValue for HKCU Run\\ShellX',
  );
});

test('uninstall deletes the restore folder (A5a D22)', () => {
  assert.match(iss, /\[UninstallDelete\][^[]*Type: filesandordirs; Name: "\{localappdata\}\\ShellX\\restore"/);
});

test('an update asks a running ShellX to quit (A5a I1) before the taskkill fallback', () => {
  // The single-instance folder (path_provider's application-support directory) and the
  // signal's name must be exactly what the app watches.
  const dart = readFileSync(
    new URL('../../apps/desktop/lib/src/platform/single_instance.dart', import.meta.url),
    'utf8',
  );
  const name = dart.match(/static const String quitFileName = '([^']+)';/)?.[1];
  assert.equal(name, 'quit.signal');
  const prepare = iss.match(/function PrepareToInstall[\s\S]*?\nend;/)?.[0] ?? '';
  const signal = prepare.indexOf(`{userappdata}\\pro.shellx\\ShellX\\${name}`);
  const kill = prepare.indexOf('taskkill.exe');
  assert.ok(signal >= 0, 'PrepareToInstall must write the quit signal');
  assert.ok(kill > signal, 'taskkill /F /T stays, after the signal, as the fallback');
  assert.match(prepare, /WaitForShellXToQuit\(/);
  assert.match(iss, /^\s*QuitWaitMs = 8000;/m);
  assert.match(iss, /^\s*QuitPollMs = (2[5-9]\d|[34]\d\d|500);/m);
  const wait = iss.match(/procedure WaitForShellXToQuit[\s\S]*?\nend;/)?.[0] ?? '';
  assert.match(wait, /GetTickCount/);
  assert.match(wait, /Sleep\(QuitPollMs\)/);
  assert.match(wait, /ShellXRunning\(\)/);
});

test('uninstall removes the shellx command (A7 D7, D8): the cli folder and our HKCU Path entry', () => {
  assert.match(iss, /\[UninstallDelete\][^[]*Type: filesandordirs; Name: "\{localappdata\}\\ShellX\\cli"/);
  const step = iss.match(/procedure CurUninstallStepChanged[\s\S]*?\nend;/)?.[0] ?? '';
  // At usUninstall (before the files go), from the user's own Path only.
  assert.match(step, /CurUninstallStep = usUninstall/);
  assert.match(step, /RemoveCliFromUserPath\(\)/);
  const remove = iss.match(/procedure RemoveCliFromUserPath[\s\S]*?\nend;/)?.[0] ?? '';
  assert.ok(remove, 'RemoveCliFromUserPath must exist');
  assert.match(remove, /RegQueryStringValue\(HKEY_CURRENT_USER, 'Environment', 'Path', /);
  assert.match(remove, /ExpandConstant\('\{localappdata\}\\ShellX\\cli'\)/);
  // Case-insensitive, every copy, a trailing backslash ignored; written back as REG_EXPAND_SZ.
  assert.match(remove, /CompareText\(/);
  assert.match(remove, /RegWriteExpandStringValue\(HKEY_CURRENT_USER, 'Environment', 'Path', /);
  // Nothing written when our entry is not there.
  assert.match(remove, /if Changed then/);
  // New terminals learn of it (WM_SETTINGCHANGE from the uninstaller).
  assert.match(iss, /^ChangesEnvironment=yes$/m);
});
