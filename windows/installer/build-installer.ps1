# Compiles windows/installer/shellx-native.iss with Inno Setup 6 into
# <OutputDir>\ShellX-Setup-<Version>.exe. SourceDir must contain shellx-desktop.exe
# (statically linked CRT, no VC++ redistributable needed). Used by the "installer" CI job.
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$AppIcon = ''
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $SourceDir 'shellx-desktop.exe'))) { throw "shellx-desktop.exe not found in $SourceDir" }

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
# merged and echoed, and the error line is repeated in the thrown message.
$saved = $ErrorActionPreference
$ErrorActionPreference = 'Continue'  # stderr lines are output here, not terminating errors
$log = & $iscc.FullName @defines (Join-Path $PSScriptRoot 'shellx-native.iss') 2>&1 | ForEach-Object { "$_" }
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
