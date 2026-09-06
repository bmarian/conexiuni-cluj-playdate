# Rebuilds ConexiuniCluj.pdx whenever a file under source/ changes.
# pdc has no built-in watch mode. This is the missing piece: run this, then
# in the Simulator press Ctrl-R after each rebuild to reload the game.

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

Build

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $sourceDir
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

$action = {
	Start-Sleep -Milliseconds 200 # debounce
	Build
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null
Register-ObjectEvent $watcher Deleted -Action $action | Out-Null
Register-ObjectEvent $watcher Renamed -Action $action | Out-Null

Write-Host "Watching $sourceDir for changes. Ctrl-C to stop."
while ($true) { Start-Sleep -Seconds 1 }
