# Disconnect SSH tunnel to FR Poscenter
param(
    [string]$IP,
    [switch]$All
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidDir = Join-Path $scriptDir "pids"

# Stop all plink processes
$plinkProcs = Get-Process plink -ErrorAction SilentlyContinue
if ($plinkProcs) {
    $plinkProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped $($plinkProcs.Count) plink process(es)" -ForegroundColor Green
} else {
    Write-Host "No active plink processes" -ForegroundColor Yellow
}

# Clean up PID files
if (Test-Path $pidDir) {
    Remove-Item -Path (Join-Path $pidDir "tunnel_*.pid") -Force -ErrorAction SilentlyContinue
}

Write-Host "All tunnels disconnected" -ForegroundColor Green
