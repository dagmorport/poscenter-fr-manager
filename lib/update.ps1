# Shared version comparison and remote version check
# Source: . "$PSScriptRoot\update.ps1"

function Compare-SemVer {
    param([string]$Version1, [string]$Version2)
    $parts1 = $Version1.Split('.')
    $parts2 = $Version2.Split('.')
    for ($i = 0; $i -lt [Math]::Max($parts1.Count, $parts2.Count); $i++) {
        $a = if ($i -lt $parts1.Count) { [int]$parts1[$i] } else { 0 }
        $b = if ($i -lt $parts2.Count) { [int]$parts2[$i] } else { 0 }
        if ($a -lt $b) { return -1 }
        if ($a -gt $b) { return 1 }
    }
    return 0
}

function Get-RemoteVersion {
    param([string]$BaseUrl)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    return (Invoke-WebRequest -Uri "$BaseUrl/version.txt" -UseBasicParsing -TimeoutSec 10).Content.Trim()
}

function Test-UpdateAvailable {
    param([string]$LocalVersion, [string]$RemoteVersion)
    return (Compare-SemVer $LocalVersion $RemoteVersion) -lt 0
}
