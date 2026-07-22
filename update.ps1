# Auto-updater for POScenter FR Manager
# Checks GitHub for new version and downloads updates

param(
    [switch]$Silent
)

$repo = "dagmorport/poscenter-fr-manager"
$branch = "main"
$baseUrl = "https://raw.githubusercontent.com/$repo/$branch"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-UpdateLog {
    param([string]$msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg" -ForegroundColor Gray
}

# Files to update (excluding config and local data)
$updateFiles = @(
    "app.ps1",
    "connect.ps1",
    "disconnect.ps1",
    "run.bat",
    "version.txt",
    "README.md"
)

Write-Host ""
Write-Host "=== POScenter FR Manager - Updater ===" -ForegroundColor Cyan
Write-Host ""

# Read local version
$localVersionFile = Join-Path $scriptDir "version.txt"
if (-not (Test-Path $localVersionFile)) {
    Write-Host "Local version file not found. Using 0.0.0" -ForegroundColor Yellow
    $localVersion = "0.0.0"
} else {
    $localVersion = (Get-Content $localVersionFile -Raw).Trim()
}
Write-Host "Local version: $localVersion" -ForegroundColor Gray

# Check remote version
Write-Host "Checking for updates..." -ForegroundColor Yellow
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $remoteVersion = (Invoke-WebRequest -Uri "$baseUrl/version.txt" -UseBasicParsing -TimeoutSec 10).Content.Trim()
    Write-Host "Remote version: $remoteVersion" -ForegroundColor Gray
} catch {
    Write-Host "Failed to check for updates: $_" -ForegroundColor Red
    exit 1
}

# Compare versions
function Compare-Versions {
    param([string]$v1, [string]$v2)
    $parts1 = $v1.Split('.')
    $parts2 = $v2.Split('.')
    for ($i = 0; $i -lt [Math]::Max($parts1.Count, $parts2.Count); $i++) {
        $a = if ($i -lt $parts1.Count) { [int]$parts1[$i] } else { 0 }
        $b = if ($i -lt $parts2.Count) { [int]$parts2[$i] } else { 0 }
        if ($a -lt $b) { return -1 }
        if ($a -gt $b) { return 1 }
    }
    return 0
}

$cmp = Compare-Versions $localVersion $remoteVersion

if ($cmp -ge 0) {
    Write-Host ""
    Write-Host "Already up to date ($localVersion)" -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "New version available: $remoteVersion" -ForegroundColor Green
Write-Host ""

if (-not $Silent) {
    $confirm = Read-Host "Update now? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Update cancelled" -ForegroundColor Yellow
        exit 0
    }
}

# Download and update files
Write-Host ""
Write-Host "Downloading updates..." -ForegroundColor Yellow

$updated = 0
foreach ($file in $updateFiles) {
    try {
        $url = "$baseUrl/$file"
        $dest = Join-Path $scriptDir $file
        $tempDest = "$dest.tmp"

        Invoke-WebRequest -Uri $url -OutFile $tempDest -UseBasicParsing -TimeoutSec 15

        # Replace file
        if (Test-Path $dest) {
            Remove-Item $dest -Force
        }
        Rename-Item $tempDest $dest

        Write-Host "  Updated: $file" -ForegroundColor Green
        $updated++
    } catch {
        Write-Host "  Failed: $file - $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Update complete ===" -ForegroundColor Green
Write-Host "Updated $updated file(s) to version $remoteVersion" -ForegroundColor Green
Write-Host ""
Write-Host "Restart the application to use the new version." -ForegroundColor Cyan
