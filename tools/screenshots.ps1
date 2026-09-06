# Renders every screen to a PNG so UI changes can actually be looked at.
#
# Builds a throwaway copy of source/ with tools/screenshots/main.lua swapped
# in as the entry point, runs it in the Simulator (it boots the real engine,
# walks the nav stack with fake data, and quits on its own), and drops the
# results in screenshots/. Nothing in source/ is touched.
#
#   .\tools\screenshots.ps1              # -> screenshots/
#   .\tools\screenshots.ps1 -Out other   # -> other/

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
# isn't ours to rely on.
$harness = Get-Content (Join-Path $PSScriptRoot "screenshots\main.lua") -Raw
$harness = $harness.Replace("@@OUTPUT_DIR@@", $outDir.Replace("\", "/"))
Set-Content -Path (Join-Path $src "main.lua") -Value $harness

# Named so it's unmistakable in the Simulator's title bar and recent list:
# "upload to device" ships whatever the Simulator currently has open, and
# what it has open after this script runs is the harness, not the app.
$pdx = Join-Path $build "NOT-THE-APP-screenshot-harness.pdx"
Write-Host "Building harness..." -ForegroundColor Cyan
& $pdc $src $pdx
if ($LASTEXITCODE -ne 0) { throw "pdc failed." }

Write-Host "Running (the Simulator quits itself)..." -ForegroundColor Cyan
& $simulator $pdx | Out-Null

$shots = Get-ChildItem $outDir -Filter *.png | Sort-Object Name
if ($shots.Count -eq 0) {
	Write-Host "No screenshots written -- the harness never got going." -ForegroundColor Red
	exit 1
}
foreach ($shot in $shots) { Write-Host "  $($shot.Name)" }

if (Test-Path (Join-Path $outDir "ERROR.png")) {
	Write-Host "Hit a runtime error -- open ERROR.png, it has the message." -ForegroundColor Red
	exit 1
}
Write-Host "$($shots.Count) screenshots in $outDir" -ForegroundColor Green

# Don't leave a harness build sitting on disk for someone to install by
# mistake. Rebuild it by running this script again.
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
