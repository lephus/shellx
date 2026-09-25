// Static checks on the Inno Setup script. The script is compiled for real on Windows by the
// "Installer compiles" CI job and by release-desktop.yml; these checks pin the spec values.
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
  assert.match(iss, /\[UninstallRun\][^[]*taskkill\.exe/);
});

test('uninstall removes the agent\'s per-user data folder (device key, trusted-phone list, settings)', () => {
  assert.match(iss, /\[UninstallDelete\][^[]*Type: filesandordirs; Name: "\{userappdata\}\\pro\.shellx\\ShellX"/);
});

test('uninstall removes the launch-at-login registry value', () => {
  assert.ok(
    iss.includes("RegDeleteValue(HKEY_CURRENT_USER, 'Software\\Microsoft\\Windows\\CurrentVersion\\Run', 'ShellX')"),
    'missing RegDeleteValue for HKCU Run\\ShellX',
  );
});
