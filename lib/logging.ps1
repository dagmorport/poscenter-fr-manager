# Shared logging module
# Source: . "$PSScriptRoot\logging.ps1"

$script:logScriptDir = (Get-Item $PSScriptRoot).Parent.FullName

function Write-AppLog {
    param([string]$msg, [string]$level = "INFO")
    $logDir = Join-Path $script:logScriptDir "logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $logFile = Join-Path $logDir "app_$(Get-Date -Format 'yyyy-MM-dd').log"
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$ts] [$level] $msg" -Encoding UTF8
}

function Add-UILog {
    param([System.Windows.Forms.TextBox]$LogBox, [string]$msg)
    $LogBox.AppendText("`r`n$msg")
    $LogBox.ScrollToCaret()
    Write-AppLog $msg
}

function Rotate-Logs {
    param([int]$MaxDays = 30)
    $logDir = Join-Path $script:logScriptDir "logs"
    if (-not (Test-Path $logDir)) { return }
    $cutoff = (Get-Date).AddDays(-$MaxDays)
    Get-ChildItem $logDir -Filter "app_*.log" -ErrorAction SilentlyContinue `
        | Where-Object { $_.LastWriteTime -lt $cutoff } `
        | Remove-Item -Force -ErrorAction SilentlyContinue
}
