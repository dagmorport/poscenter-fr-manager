# SSH helper for plink
# Source: . "$PSScriptRoot\ssh.ps1"

function Invoke-Plink {
    param(
        [Parameter(Mandatory)] [string]$PlinkPath,
        [Parameter(Mandatory)] [string]$Host,
        [Parameter(Mandatory)] [int]$Port,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password,
        [string]$Command
    )
    if (-not (Test-Path $PlinkPath)) {
        throw "plink.exe not found: $PlinkPath"
    }

    $output = & $PlinkPath -batch -ssh -P $Port -pw $Password -l $User $Host $Command 2>&1
    return $output
}

function Start-PlinkTunnel {
    param(
        [Parameter(Mandatory)] [string]$PlinkPath,
        [Parameter(Mandatory)] [string]$Host,
        [Parameter(Mandatory)] [int]$Port,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password,
        [Parameter(Mandatory)] [int]$LocalPort,
        [Parameter(Mandatory)] [string]$RemoteHost,
        [Parameter(Mandatory)] [int]$RemotePort
    )
    if (-not (Test-Path $PlinkPath)) {
        throw "plink.exe not found: $PlinkPath"
    }

    $tunnelArgs = "-batch -ssh -P $Port -pw $Password -l $User -L ${LocalPort}:${RemoteHost}:${RemotePort} -N $Host"
    $proc = Start-Process -FilePath $PlinkPath -ArgumentList $tunnelArgs -PassThru -WindowStyle Hidden
    return $proc
}

function Stop-PlinkTunnels {
    Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
