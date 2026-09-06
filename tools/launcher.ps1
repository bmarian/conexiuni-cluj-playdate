# Regenerates the launcher art in source/launcher/ (card, icon, launch image)
# by running tools/launcher/main.lua in the Simulator on a copy of source/.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$sdk = $env:PLAYDATE_SDK_PATH
if (-not $sdk) { throw "PLAYDATE_SDK_PATH is not set." }
$pdc = Join-Path $sdk "bin\pdc.exe"
$simulator = Join-Path $sdk "bin\PlaydateSimulator.exe"

$outDir = Join-Path $root "source\launcher"
$build = Join-Path ([System.IO.Path]::GetTempPath()) "conexiuni-launcher"

New-Item -ItemType Directory -Path $outDir -Force | Out-Null
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
New-Item -ItemType Directory -Path $build | Out-Null

$src = Join-Path $build "source"
Copy-Item (Join-Path $root "source") $src -Recurse
# The generator must not bundle last run's art into its own build.
Remove-Item (Join-Path $src "launcher") -Recurse -Force -ErrorAction SilentlyContinue

$generator = Get-Content (Join-Path $PSScriptRoot "launcher\main.lua") -Raw
$generator = $generator.Replace("@@OUTPUT_DIR@@", $outDir.Replace("\", "/"))
Set-Content -Path (Join-Path $src "main.lua") -Value $generator

$pdx = Join-Path $build "NOT-THE-APP-launcher-art.pdx"
Write-Host "Building generator..." -ForegroundColor Cyan
& $pdc $src $pdx
if ($LASTEXITCODE -ne 0) { throw "pdc failed." }

Write-Host "Drawing (the Simulator quits itself)..." -ForegroundColor Cyan
& $simulator $pdx | Out-Null

$expected = @("card.png", "icon.png", "launchImage.png")
$missing = $expected | Where-Object { -not (Test-Path (Join-Path $outDir $_)) }
if ($missing) {
	Write-Host "Missing: $($missing -join ', ')" -ForegroundColor Red
	exit 1
}
foreach ($name in $expected) { Write-Host "  source/launcher/$name" }
Write-Host "Launcher art written." -ForegroundColor Green

Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
