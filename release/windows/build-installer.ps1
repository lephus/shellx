# Compiles release/windows/shellx.iss with Inno Setup 6 into <OutputDir>\ShellX-Setup-<Version>.exe.
# SourceDir must contain ShellX.exe. Used by .github/workflows/release-desktop.yml and by the
# "Installer compiles" CI job.
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$AppIcon = ''
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $SourceDir 'ShellX.exe'))) { throw "ShellX.exe not found in $SourceDir" }

# A Flutter Windows app needs the Visual C++ runtime next to the exe on a clean PC
# (https://docs.flutter.dev/platform-integration/windows/building). release-desktop.yml copies
# these from the Visual Studio VC++ redistributable after signing; fail loudly if they are missing
# so a clean-PC install cannot silently ship without them.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  if (-not (Test-Path (Join-Path $SourceDir $dll))) {
    throw "$dll not found in $SourceDir (the Visual C++ runtime must ship next to ShellX.exe)"
  }
}

# Inno Setup 6 only: Vietnamese.isl is pinned to the 6.7.1 message set.
function Find-Iscc {
  Get-ChildItem -Path "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1
}

$iscc = Find-Iscc
if (-not $iscc) {
  choco install innosetup --version=6.7.1 -y --no-progress
  if ($LASTEXITCODE -ne 0) { throw 'choco install innosetup failed' }
  $iscc = Find-Iscc
}
if (-not $iscc) { throw 'Inno Setup 6 ISCC.exe not found after installing it' }

if ($AppIcon -and -not (Test-Path $AppIcon)) { throw "AppIcon $AppIcon not found" }
$defines = @("/DAppVersion=$Version", "/DSourceDir=$SourceDir", "/DOutputDir=$OutputDir")
if ($AppIcon) { $defines += "/DAppIcon=$AppIcon" }

# ISCC prints progress on stdout and "Error on line N in <file>: <message>" on stderr: both are
# merged and echoed, so the error sits under the last status line in the log, and the error line is
# repeated in the thrown message (the job's annotation) instead of only the exit code.
$saved = $ErrorActionPreference
$ErrorActionPreference = 'Continue'  # stderr lines are output here, not terminating errors
$log = & $iscc.FullName @defines (Join-Path $PSScriptRoot 'shellx.iss') 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
$ErrorActionPreference = $saved
$log | ForEach-Object { Write-Host $_ }
if ($code -ne 0) {
  $errorLine = ($log | Where-Object { $_ -match '^Error' } | Select-Object -Last 1)
  if (-not $errorLine) { $errorLine = '(ISCC printed no error line)' }
  throw "ISCC failed with exit code ${code}: $errorLine"
}

$setup = Join-Path $OutputDir "ShellX-Setup-$Version.exe"
if (-not (Test-Path $setup)) { throw "ISCC did not produce $setup" }
Write-Host "Built $setup"
