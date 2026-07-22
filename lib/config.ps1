# Config reader with validation
# Source: . "$PSScriptRoot\config.ps1"

function Read-Config {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    try {
        $raw = Get-Content $ConfigPath -Raw -ErrorAction Stop
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse config.json: $_"
    }

    # Validate required fields
    $required = @("fr_ip", "fr_port", "local_port", "ssh_port", "ssh_user", "kassas")
    foreach ($field in $required) {
        if ($null -eq $config.$field) {
            throw "Missing required config field: $field"
        }
    }

    if ($config.kassas -isnot [array] -or $config.kassas.Count -eq 0) {
        throw "config.json: 'kassas' must be a non-empty array"
    }
    foreach ($k in $config.kassas) {
        if (-not $k.name -or -not $k.ip) {
            throw "config.json: each kassa must have 'name' and 'ip'"
        }
    }

    # Set defaults for optional fields (Add-Member safe for PSCustomObject)
    if (-not (Get-Member -InputObject $config -Name 'plink_path' -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        $config | Add-Member -NotePropertyName 'plink_path' -NotePropertyValue '' -Force
    }
    if (-not (Get-Member -InputObject $config -Name 'test_driver_path' -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        $config | Add-Member -NotePropertyName 'test_driver_path' -NotePropertyValue '' -Force
    }

    return $config
}
