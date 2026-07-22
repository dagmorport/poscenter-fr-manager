# SSH helper - secure plink invocation (password via temp file, never in CLI args)
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

    $pwFile = [System.IO.Path]::GetTempFileName()
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($pwFile, $Password, $utf8)

    try {
        $args = @("-batch", "-ssh", "-P", $Port, "-pwfile", $pwFile, "-l", $User, $Host, $Command)
        return & $PlinkPath $args 2>&1
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

    $pwFile = [System.IO.Path]::GetTempFileName()
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($pwFile, $Password, $utf8)

    $tunnelArgs = "-batch -ssh -P $Port -pwfile `"$pwFile`" -l $User -L ${LocalPort}:${RemoteHost}:${RemotePort} -N $Host"
    $proc = Start-Process -FilePath $PlinkPath -ArgumentList $tunnelArgs -PassThru -WindowStyle Hidden

    # Cleanup temp pwfile after plink reads it
    $cleanup = { param($pf) Start-Sleep 3; Remove-Item $pf -Force -ErrorAction SilentlyContinue }
    Start-Job -ScriptBlock $cleanup -ArgumentList $pwFile | Out-Null

    return $proc
}

function Stop-PlinkTunnels {
    Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
