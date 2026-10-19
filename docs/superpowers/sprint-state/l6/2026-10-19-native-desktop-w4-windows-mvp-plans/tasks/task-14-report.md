# Task 14 report (Phase A)

Status: Phase A done. Commit e3d75dec9d (windows/installer/* only), not pushed.
Files: shellx-native.iss (AppId {D322DA97-3B0D-49C7-BDB2-8EBFADBA1004}), Vietnamese.isl (verbatim from flutter-final), build-installer.ps1, check_coexistence.py, test_check_coexistence.py.
Tests: `python3 -m unittest` in windows/installer: 4 pass (installer_coexists_with_flutter, Flutter AppId fails, taskkill ShellX.exe fails, Flutter exe / term delete fail + native delete allowed). ISCC not run (Mac); compiled only in Phase B CI.

Notes / concerns
- Files section: shellx-desktop.exe + `*.dll` (skipifsourcedoesntexist) so staged DLLs ship if static CRT fails.
- No [UninstallDelete]/[InstallDelete]/[UninstallRun]; CloseApplications=yes. Shortcut name contains non-ASCII "thử nghiệm" (file is UTF-8; Inno 6.7 handles UTF-8 scripts, ISCC verifies in CI).
- Smoke assumes artifact `shellx-desktop` holds shellx-desktop.exe at its root; adjust if the app job stages differently.

## Phase B YAML (to add)
model job, after existing steps:
```yaml
      - name: Installer coexistence tests
        run: python3 -m unittest discover -s windows/installer -v
```
New job:
```yaml
  installer:
    needs: app
    runs-on: windows-2025
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: shellx-desktop
          path: staged
      - name: Build installer
        shell: pwsh
        run: ./windows/installer/build-installer.ps1 -Version 2.0.0 -SourceDir "$env:GITHUB_WORKSPACE\staged" -OutputDir "$env:GITHUB_WORKSPACE\dist" -AppIcon "$env:GITHUB_WORKSPACE\windows\shellx-app\resources\app_icon.ico"
      - name: Coexistence check
        run: python windows/installer/check_coexistence.py
      - name: Smoke install / run / uninstall
        shell: pwsh
        run: |
          $setup = "$env:GITHUB_WORKSPACE\dist\ShellX-Setup-2.0.0-sprint.exe"
          Start-Process $setup -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/CURRENTUSER',"/LOG=$env:GITHUB_WORKSPACE\install.log" -Wait
          $dir = "$env:LOCALAPPDATA\Programs\ShellX Native"
          if (-not (Test-Path "$dir\shellx-desktop.exe")) { throw 'exe missing after install' }
          & "$dir\shellx-desktop.exe" --smoke-ui-assets
          if ($LASTEXITCODE -ne 0) { throw "smoke-ui-assets exit $LASTEXITCODE" }
          Start-Process "$dir\unins000.exe" -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES' -Wait
          Start-Sleep -Seconds 3
          if (Test-Path $dir) { throw 'install dir still present after uninstall' }
      - uses: actions/upload-artifact@v4
        with:
          name: ShellX-Setup-2.0.0-sprint
          path: dist/ShellX-Setup-2.0.0-sprint.exe
          retention-days: 14
```
Also Phase B: windows/.cargo/config.toml with static CRT, verify dumpbin dependents.

## Phase B (local only, not pushed, CI not run)
Added windows/.cargo/config.toml (static CRT), python unittest step in `model`, dumpbin check in `app` that fails on VCRUNTIME140/MSVCP140, and the `installer` job (needs app). YAML parses (jobs: model, remote-e2e, app, installer). Untested on CI: static CRT link with libghostty-vt may fail; if so revert config and ship DLLs.

## Fix round 1
1. shellx-native.iss now has a UTF-8 BOM; check script and test read utf-8-sig. Smoke asserts the Start-menu shortcut name equals "ShellX 2 (thử nghiệm).lnk" built from code points (ử U+1EED, ệ U+1EC7; script line is NFC). Vietnamese.isl left verbatim: no BOM (starts with "; *").
2. Smoke checks installer and uninstaller exit codes; uninstall polls up to 30 s for the dir to vanish.
3. dumpbin missing now fails the step; also fails if the log lacks KERNEL32.
Tests: 4 pass; YAML parses. Not pushed, CI not run.
