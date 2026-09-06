# Renders every screen to a PNG in $Out by running tools/screenshots/main.lua
# in the Simulator on a copy of source/. source/ itself is not touched.

param(
	[string]$Out = "screenshots"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$sdk = $env:PLAYDATE_SDK_PATH
if (-not $sdk) { throw "PLAYDATE_SDK_PATH is not set." }
$pdc = Join-Path $sdk "bin\pdc.exe"
$simulator = Join-Path $sdk "bin\PlaydateSimulator.exe"

$outDir = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $root $Out }
$build = Join-Path ([System.IO.Path]::GetTempPath()) "conexiuni-screenshots"

if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
New-Item -ItemType Directory -Path $outDir | Out-Null
New-Item -ItemType Directory -Path $build | Out-Null

$src = Join-Path $build "source"
Copy-Item (Join-Path $root "source") $src -Recurse

# The harness writes to an absolute path; the Simulator's working directory
# is not ours to rely on.
$harness = Get-Content (Join-Path $PSScriptRoot "screenshots\main.lua") -Raw
$harness = $harness.Replace("@@OUTPUT_DIR@@", $outDir.Replace("\", "/"))
Set-Content -Path (Join-Path $src "main.lua") -Value $harness

# Named loudly: the Simulator's "upload to device" ships whatever it has
# open, which after this script is the harness.
$pdx = Join-Path $build "NOT-THE-APP-screenshot-harness.pdx"
Write-Host "Building harness..." -ForegroundColor Cyan
& $pdc $src $pdx
if ($LASTEXITCODE -ne 0) { throw "pdc failed." }

Write-Host "Running (the Simulator quits itself)..." -ForegroundColor Cyan
& $simulator $pdx | Out-Null

$shots = Get-ChildItem $outDir -Filter *.png | Sort-Object Name
if ($shots.Count -eq 0) {
	Write-Host "No screenshots written; the harness never got going." -ForegroundColor Red
	exit 1
}
foreach ($shot in $shots) { Write-Host "  $($shot.Name)" }

if (Test-Path (Join-Path $outDir "ERROR.png")) {
	Write-Host "Runtime error; the message is in ERROR.png." -ForegroundColor Red
	exit 1
}
Write-Host "$($shots.Count) screenshots in $outDir" -ForegroundColor Green

# Don't leave a harness build on disk for someone to install by mistake.
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
