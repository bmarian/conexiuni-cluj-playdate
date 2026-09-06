# Rebuilds ConexiuniCluj.pdx whenever a file under source/ changes, since pdc
# has no watch mode. Press Ctrl-R in the Simulator after each rebuild.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $root "source"
$output = Join-Path $root "ConexiuniCluj.pdx"

function Build {
	Write-Host "Building..." -ForegroundColor Cyan
	pdc $sourceDir $output
	if ($LASTEXITCODE -eq 0) {
		Write-Host "Build OK. Press Ctrl-R in the Simulator to reload." -ForegroundColor Green
	} else {
		Write-Host "Build failed." -ForegroundColor Red
	}
}

function LatestWriteTime {
	Get-ChildItem $sourceDir -Recurse -File |
		Measure-Object -Property LastWriteTimeUtc -Maximum |
		Select-Object -ExpandProperty Maximum
}

Build
$lastSeen = LatestWriteTime

Write-Host "Watching $sourceDir for changes. Ctrl-C to stop."
while ($true) {
	Start-Sleep -Milliseconds 500
	$current = LatestWriteTime
	if ($current -ne $lastSeen) {
		$lastSeen = $current
		Build
	}
}
