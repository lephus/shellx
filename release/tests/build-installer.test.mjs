// Static checks on the Inno Setup build script. ISCC.exe only runs for real on Windows, in
// release-desktop.yml (there is no CI, decision V5); these checks pin the Visual C++ runtime
// guard: a Flutter Windows app needs msvcp140.dll, vcruntime140.dll and vcruntime140_1.dll next
// to the exe on a clean PC (https://docs.flutter.dev/platform-integration/windows/building).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const script = readFileSync(new URL('../windows/build-installer.ps1', import.meta.url), 'utf8');

test('fails with a clear error when a Visual C++ runtime DLL is missing from -SourceDir', () => {
  assert.match(script, /foreach \(\$dll in 'msvcp140\.dll', 'vcruntime140\.dll', 'vcruntime140_1\.dll'\)/);
  assert.match(script, /if \(-not \(Test-Path \(Join-Path \$SourceDir \$dll\)\)\)/);
  assert.match(script, /throw "\$dll not found in \$SourceDir/);
});

test('the DLL check runs before ISCC is invoked', () => {
  const dllCheckIndex = script.indexOf('vcruntime140_1.dll');
  const isccIndex = script.indexOf('& $iscc.FullName');
  assert.ok(dllCheckIndex > -1 && isccIndex > -1 && dllCheckIndex < isccIndex);
});
