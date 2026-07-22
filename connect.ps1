# Connect to FR Poscenter via SSH tunnel (plink + password)
# Disables graphics on cash register (required for FR connection)

param(
    [string]$IP,
    [string]$Name
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"
$pidDir = Join-Path $scriptDir "pids"

# Read config
. "$scriptDir\lib\config.ps1"
. "$scriptDir\lib\ssh.ps1"
try {
    $config = Read-Config $configPath
} catch {
    Write-Host "Config error: $_" -ForegroundColor Red
    exit 1
}

# Find target cash register
$target = $null

if ($IP) {
    $target = $config.kassas | Where-Object { $_.ip -eq $IP }
    if (-not $target) {
        $target = [PSCustomObject]@{ name = "Kassa ($IP)"; ip = $IP }
    }
} elseif ($Name) {
    $target = $config.kassas | Where-Object { $_.name -eq $Name }
    if (-not $target) {
        Write-Host "Cash register '$Name' not found in config.json" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "Available cash registers:" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $config.kassas.Count; $i++) {
        $k = $config.kassas[$i]
        Write-Host ("  {0}. {1,-15} ({2})" -f ($i + 1), $k.name, $k.ip)
    }
    Write-Host ""
    $choice = Read-Host "Select cash register (number, IP or name)"

    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $config.kassas.Count) {
            Write-Host "Invalid number" -ForegroundColor Red
            exit 1
        }
        $target = $config.kassas[$idx]
    } else {
        $target = $config.kassas | Where-Object { $_.ip -eq $choice -or $_.name -eq $choice } | Select-Object -First 1
        if (-not $target) {
            $target = [PSCustomObject]@{ name = "Kassa ($choice)"; ip = $choice }
        }
    }
}

$kassaIP = $target.ip
$kassaName = $target.name
$frIP = $config.fr_ip
$frPort = $config.fr_port
$localPort = $config.local_port
$sshPort = $config.ssh_port
$sshUser = $config.ssh_user

# Get plink path from config or default to script directory
$plinkPath = if ($config.plink_path) { $config.plink_path } else { Join-Path $scriptDir "plink.exe" }
if (-not (Test-Path $plinkPath)) {
    $plinkPath = Join-Path $scriptDir "plink.exe"
}

Write-Host ""
Write-Host "Connecting to: $kassaName ($kassaIP)" -ForegroundColor Cyan
Write-Host "FR: ${frIP}:${frPort}" -ForegroundColor Cyan
Write-Host "Local port: ${localPort}" -ForegroundColor Cyan
Write-Host ""

# Check plink exists
if (-not (Test-Path $plinkPath)) {
    Write-Host "plink not found at: $plinkPath" -ForegroundColor Red
    Write-Host "Update plink_path in config.json" -ForegroundColor Red
    exit 1
}

# Stop existing tunnels
Stop-PlinkTunnels

# Clean up PID files
if (-not (Test-Path $pidDir)) {
    New-Item -ItemType Directory -Path $pidDir | Out-Null
}

# Get password
$securePassword = Read-Host "Enter root password for $kassaIP" -AsSecureString
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
)

# Test connection
Write-Host "Testing connection..." -ForegroundColor Gray
try {
    $testResult = Invoke-Plink -PlinkPath $plinkPath -Host $kassaIP -Port $sshPort `
        -User $sshUser -Password $password -Command "echo CONNECTION_OK"
    $testStr = ($testResult -join "`n")
} catch {
    $testStr = ""
}
if ($testStr -notmatch "CONNECTION_OK") {
    Write-Host "Connection failed. Check password and IP." -ForegroundColor Red
    exit 1
}
Write-Host "Connection OK" -ForegroundColor Green

# Disable graphics (required for FR tunnel to work)
Write-Host "Disabling graphics on cash register..." -ForegroundColor Yellow

# Find and kill Xorg by PID
try {
    $xorgOut = Invoke-Plink -PlinkPath $plinkPath -Host $kassaIP -Port $sshPort `
        -User $sshUser -Password $password -Command "pgrep Xorg"
    $xorgStr = ($xorgOut -join "`n")
} catch {
    $xorgStr = ""
}

if ($xorgStr -match '\d+') {
    $pid = $xorgStr.Trim()
    Write-Host "  Found Xorg PID: $pid" -ForegroundColor Gray
    try {
        Invoke-Plink -PlinkPath $plinkPath -Host $kassaIP -Port $sshPort `
            -User $sshUser -Password $password -Command "sudo kill -INT $pid" | Out-Null
    } catch {}
    Write-Host "  Graphics disabled" -ForegroundColor Green
} else {
    Write-Host "  Xorg not running (already disabled)" -ForegroundColor Gray
}

Start-Sleep -Seconds 2

# Start tunnel
Write-Host "Starting SSH tunnel..." -ForegroundColor Yellow

try {
    $tunnelProc = Start-PlinkTunnel -PlinkPath $plinkPath -Host $kassaIP -Port $sshPort `
        -User $sshUser -Password $password `
        -LocalPort $localPort -RemoteHost $frIP -RemotePort $frPort
    Write-Host "plink started (PID: $($tunnelProc.Id))" -ForegroundColor Gray
} catch {
    Write-Host "FAILED to start plink: $_" -ForegroundColor Red
    exit 1
}

# Retry port check (up to 10 seconds)
$maxRetries = 10
$listening = $false
for ($i = 1; $i -le $maxRetries; $i++) {
    Start-Sleep -Seconds 1
    $check = netstat -ano | findstr ":$localPort.*LISTEN"
    if ($check) {
        $listening = $true
        break
    }
}
if ($listening) {
    Write-Host ""
    Write-Host "=== TUNNEL ACTIVE ===" -ForegroundColor Green
    Write-Host "Connect FR driver to: 127.0.0.1:${localPort}" -ForegroundColor Green
    Write-Host "To disconnect: .\disconnect.ps1" -ForegroundColor Gray
    exit 0
}

# Tunnel failed
Write-Host ""
Write-Host "Failed to start tunnel to $kassaName ($kassaIP)" -ForegroundColor Red
Write-Host "Check:" -ForegroundColor Red
Write-Host "  - Cash register availability (ping $kassaIP)" -ForegroundColor Red
Write-Host "  - SSH port (Test-NetConnection $kassaIP -Port $sshPort)" -ForegroundColor Red
Write-Host "  - FR settings in config.json" -ForegroundColor Red
exit 1
