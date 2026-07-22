# SSH helper - secure plink invocation (password via temp file)
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

    $pwFile = Join-Path $env:TEMP "plink_pw_$([System.Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllBytes($pwFile, [System.Text.Encoding]::ASCII.GetBytes($Password))

    try {
        $args = "-batch -ssh -P $Port -pwfile `"$pwFile`" -l $User $Host $Command"
        $output = cmd /c "`"$PlinkPath`" $args 2>&1"
        return $output
    } finally {
        Remove-Item $pwFile -Force -ErrorAction SilentlyContinue
    }
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

    $pwFile = Join-Path $env:TEMP "plink_pw_$([System.Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllBytes($pwFile, [System.Text.Encoding]::ASCII.GetBytes($Password))

    $tunnelArgs = "-batch -ssh -P $Port -pwfile `"$pwFile`" -l $User -L ${LocalPort}:${RemoteHost}:${RemotePort} -N $Host"
    $proc = Start-Process -FilePath $PlinkPath -ArgumentList $tunnelArgs -PassThru -WindowStyle Hidden

    # Cleanup pwfile after plink reads it
    $job = { param($pf) Start-Sleep 5; Remove-Item $pf -Force -ErrorAction SilentlyContinue }
    Start-Job -ScriptBlock $job -ArgumentList $pwFile | Out-Null

    return $proc
}

function Stop-PlinkTunnels {
    Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
