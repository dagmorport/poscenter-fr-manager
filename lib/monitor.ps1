# KKT monitor collection logic
# Source: . "$PSScriptRoot\monitor.ps1"
# Kept dependency-free (no parent scope access) so it runs inside a runspace/job
# and can be tested headlessly.

# Fast TCP check (skips unreachable cash registers without waiting for plink)
function Test-TcpPort {
    param(
        [string]$ComputerName,
        [int]$Port,
        [int]$TimeoutMs = 1500
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# ISO date (yyyy-MM-dd) -> dd.MM.yyyy (kkt_monitor format)
function ConvertTo-RuDate {
    param([string]$IsoDate)
    if (-not $IsoDate) { return "" }
    try {
        return [datetime]::ParseExact($IsoDate, "yyyy-MM-dd", $null).ToString("dd.MM.yyyy")
    } catch {
        return ""
    }
}

# 4-byte date inside the feature license hex string: day, month, year LE16
function ConvertFrom-LicenseDate {
    param([string]$Hex, [int]$ByteOffset)
    if (-not $Hex) { return "" }
    $i = $ByteOffset * 2
    if ($Hex.Length -lt $i + 8) { return "" }
    try {
        $day   = [Convert]::ToByte($Hex.Substring($i, 2), 16)
        $month = [Convert]::ToByte($Hex.Substring($i + 2, 2), 16)
        # year is stored little-endian: low byte first, then high byte
        $yearLo = [Convert]::ToByte($Hex.Substring($i + 4, 2), 16)
        $yearHi = [Convert]::ToByte($Hex.Substring($i + 6, 2), 16)
        $year = $yearHi * 256 + $yearLo
        if ($day -lt 1 -or $day -gt 31 -or $month -lt 1 -or $month -gt 12) { return "" }
        return ("{0:D2}.{1:D2}.{2}" -f $day, $month, $year)
    } catch {
        return ""
    }
}

# Parse TS PIOT info from cash register output
function Get-PiotInfo {
    param([string[]]$Output)

    $info = [PSCustomObject]@{
        ArtixModule = ""
        KktError55  = ""
        EsmService  = ""
        MarkVerify  = ""
        IsActive    = ""
        ValidTill   = ""
        DaysLeft    = ""
        SyncedAt    = ""
        Raw         = ""
    }

    $str = ($Output -join "`n")

    $m = [regex]::Match($str, "TSPIOT=(\d+)")
    if ($m.Success) { $info.ArtixModule = $m.Groups[1].Value }

    $m = [regex]::Match($str, "ERR55=(\d+)")
    if ($m.Success) { $info.KktError55 = $m.Groups[1].Value }

    $m = [regex]::Match($str, "ESMSVC=(\S+)")
    if ($m.Success) { $info.EsmService = $m.Groups[1].Value }

    $m = [regex]::Match($str, "MARKVER=(\S+)")
    if ($m.Success) { $info.MarkVerify = $m.Groups[1].Value }

    $m = [regex]::Match($str, "(?m)^PIOT=([^\r\n]*)")
    if ($m.Success) { $info.Raw = $m.Groups[1].Value.Trim() }

    $m = [regex]::Match($info.Raw, "is_active:(\w+)")
    if ($m.Success) { $info.IsActive = $m.Groups[1].Value }

    $m = [regex]::Match($info.Raw, "last_sync:""?(\d{4}-\d{2}-\d{2})")
    if ($m.Success) { $info.SyncedAt = $m.Groups[1].Value }

    $m = [regex]::Match($info.Raw, "(\d{4}-\d{2}-\d{2})")
    if ($m.Success) {
        $info.ValidTill = $m.Groups[1].Value
        try {
            $valid = [datetime]::ParseExact($info.ValidTill, "yyyy-MM-dd", $null)
            $info.DaysLeft = [string](($valid - (Get-Date)).Days)
        } catch {
            $info.DaysLeft = ""
        }
    }

    return $info
}

# Parse kkm.json fields from cash register output
function Get-KkmInfo {
    param([string[]]$Output)

    $info = [PSCustomObject]@{
        FnNum  = ""
        FnDate = ""
        Serial = ""
        Fw     = ""
    }

    $str = ($Output -join "`n")
    $m = [regex]::Match($str, "(?m)^KKM=(.*)")
    if (-not $m.Success) { return $info }

    try {
        $parsed = ($m.Groups[1].Value.Trim() | ConvertFrom-Json)
        $kkm = if ($parsed -is [array]) { $parsed[0] } else { $parsed }
        if ($kkm) {
            $info.FnNum = [string]$kkm.fn_number
            $info.FnDate = [string]$kkm.fn_time_end
            $info.Serial = [string]$kkm.number
            $info.Fw = [string]$kkm.firmware
        }
    } catch { }

    return $info
}

# Newest kkt_monitor*.html in the app folder
function Get-MonitorFile {
    param([string]$Folder)
    $files = Get-ChildItem -Path $Folder -Filter "kkt_monitor*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if (-not $files) { return $null }
    return @($files)[0].FullName
}

# KKT entries from the HTML data block
function Get-MonitorData {
    param([string]$Html)
    $m = [regex]::Match($Html, '(?s)<script type="application/json" id="kkt-data">(.*?)</script>')
    if (-not $m.Success) { return $null }
    try {
        return ($m.Groups[1].Value.Trim() | ConvertFrom-Json)
    } catch {
        return $null
    }
}

# Serialize entries the same way as JSON.stringify(data, null, 2) in the dashboard
function ConvertTo-MonitorJson {
    param($Entries)

    $fields = @("name", "lic", "piot", "fnNum", "fnDate", "serial", "fw")
    $list = @($Entries | Sort-Object name)
    $lines = @("[")

    for ($i = 0; $i -lt $list.Count; $i++) {
        $entry = $list[$i]
        $lines += "  {"
        for ($j = 0; $j -lt $fields.Count; $j++) {
            $field = $fields[$j]
            $value = [string]$entry.$field
            $value = $value.Replace("\", "\\").Replace('"', '\"')
            $comma = if ($j -lt $fields.Count - 1) { "," } else { "" }
            $lines += "    `"$field`": `"$value`"$comma"
        }
        $objComma = if ($i -lt $list.Count - 1) { "," } else { "" }
        $lines += "  }$objComma"
    }

    $lines += "]"
    return ($lines -join "`n")
}

# Read KKT feature licenses (commercial functions / TS PIOT) via the POScenter FR driver.
# Requires: SSH tunnel to the FR (127.0.0.1:local_port) and the cash GUI stopped,
# otherwise the driver hangs waiting for the FR socket held by artix-gui.
function Get-FeatureLicenses {
    param(
        [Parameter(Mandatory)] [string]$KassaIP,
        [Parameter(Mandatory)] [string]$PlinkPath,
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$KillGuiCmd,
        [Parameter(Mandatory)] [string]$GuiStateCmd
    )

    $result = [PSCustomObject]@{
        Commercial = ""   # commercial functions, dd.MM.yyyy
        Piot       = ""   # TS PIOT functions, dd.MM.yyyy
        Raw        = ""
        Error      = ""
    }

    # 1) kill the GUI so the driver can reach the FR
    & $PlinkPath -batch -ssh -P $Config.ssh_port -pw $Config.ssh_password -l $Config.ssh_user $KassaIP $KillGuiCmd 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    $state = (& $PlinkPath -batch -ssh -P $Config.ssh_port -pw $Config.ssh_password -l $Config.ssh_user $KassaIP $GuiStateCmd 2>&1) -join ""
    if ($state -notmatch "GUI_DEAD") {
        $result.Error = "GUI still alive"
        return $result
    }

    # 2) start the FR tunnel
    Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    $tunnel = Start-PlinkTunnel -PlinkPath $PlinkPath -HostName $KassaIP -Port $Config.ssh_port `
        -User $Config.ssh_user -Password $Config.ssh_password -LocalPort $Config.local_port `
        -RemoteHost $Config.fr_ip -RemotePort $Config.fr_port

    $portReady = $false
    for ($i = 1; $i -le 10; $i++) {
        Start-Sleep -Milliseconds 300
        if (netstat -ano | findstr ":$($Config.local_port).*LISTEN") { $portReady = $true; break }
    }

    if (-not $portReady) {
        $result.Error = "tunnel not ready on port $($Config.local_port)"
        try { Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue } catch {}
        return $result
    }

    # 3) read licenses via the COM driver in a background job
    #    (the driver Connect() blocks the calling thread)
    $job = Start-Job -ScriptBlock {
        param($port)
        $out = @{ Connected = $false; License = ""; Error = "" }
        try {
            $drv = New-Object -ComObject "Addin.DrvFR"
            $drv.Connect() | Out-Null
            if (-not $drv.Connected) { $out.Error = "driver rc=$($drv.ResultCode)"; return $out }
            $out.Connected = $true
            $drv.ReadFeatureLicenses() | Out-Null
            $out.License = [string]$drv.License
            $drv.Disconnect() | Out-Null
        } catch {
            $out.Error = $_.Exception.Message
        }
        return $out
    } -ArgumentList $Config.local_port

    if (Wait-Job $job -Timeout 30) {
        $lic = Receive-Job $job
        $result.Raw = $lic.License
        $result.Error = $lic.Error
        if ($lic.License) {
            # byte 40 = commercial functions date, byte 44 = TS PIOT functions date
            $result.Commercial = ConvertFrom-LicenseDate -Hex $lic.License -ByteOffset 40
            $result.Piot       = ConvertFrom-LicenseDate -Hex $lic.License -ByteOffset 44
        }
    } else {
        $result.Error = "driver timeout"
    }
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    # 4) stop the tunnel and restore the GUI
    try { Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue } catch {}
    & $PlinkPath -batch -ssh -P $Config.ssh_port -pw $Config.ssh_password -l $Config.ssh_user $KassaIP "systemctl restart getty@tty1" 2>&1 | Out-Null

    return $result
}

# Update kkt_monitor HTML from all cash registers (-DryRun: collect only, return JSON)
function Update-KktMonitor {
    param(
        [Parameter(Mandatory)] [string]$MonitorFile,
        [Parameter(Mandatory)] [string]$PlinkPath,
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$MonitorCmd,
        [Parameter(Mandatory)] [string]$KillGuiCmd,
        [Parameter(Mandatory)] [string]$GuiStateCmd,
        [switch]$DryRun
    )

    $summary = [PSCustomObject]@{
        File        = $MonitorFile
        Total       = 0
        Updated     = 0
        Added       = 0
        Failed      = 0
        NoData      = 0
        ExpiresSoon = 0
        Licenses    = 0
        Json        = ""
    }

    $html = [System.IO.File]::ReadAllText($MonitorFile)
    $parsed = Get-MonitorData -Html $html
    if ($null -eq $parsed) {
        Add-Log "Data block not found in $(Split-Path $MonitorFile -Leaf)"
        return $null
    }

    $entries = @($parsed)
    $kassaPw = $Config.ssh_password

    foreach ($k in $Config.kassas) {
        $summary.Total++

        if (-not $kassaPw) {
            $summary.Failed++
            Add-Log ("{0,-9} {1,-16} no ssh password in config" -f $k.name, $k.ip)
            continue
        }

        if (-not (Test-TcpPort -ComputerName $k.ip -Port $Config.ssh_port)) {
            $summary.Failed++
            Add-Log ("{0,-9} {1,-16} no SSH" -f $k.name, $k.ip)
            continue
        }

        $out = & $PlinkPath -batch -ssh -P $Config.ssh_port -pw $kassaPw -l $Config.ssh_user $k.ip $MonitorCmd 2>&1
        $outStr = ($out -join "`n")

        if ($outStr -match "Cannot confirm a host key") {
            $summary.Failed++
            $fp = [regex]::Match($outStr, "SHA256:[A-Za-z0-9/+=]+")
            Add-Log ("{0,-9} {1,-16} host key not cached {2}" -f $k.name, $k.ip, $fp.Value)
            continue
        }

        $piotInfo = Get-PiotInfo -Output $out
        $kkmInfo = Get-KkmInfo -Output $out
        $piotRu = ConvertTo-RuDate -IsoDate $piotInfo.ValidTill

        # Feature licenses via the FR driver (commercial functions + TS PIOT)
        $feat = Get-FeatureLicenses -KassaIP $k.ip -PlinkPath $PlinkPath -Config $Config `
            -KillGuiCmd $KillGuiCmd -GuiStateCmd $GuiStateCmd
        if ($feat.Error) {
            Add-Log ("{0,-9} {1,-16} driver: {2}" -f $k.name, $k.ip, $feat.Error)
        } elseif ($feat.Commercial -or $feat.Piot) {
            $summary.Licenses++
        }

        $idx = -1
        for ($i = 0; $i -lt $entries.Count; $i++) {
            if ($entries[$i].name -and $entries[$i].name.ToLower() -eq $k.name.ToLower()) { $idx = $i; break }
        }
        if ($idx -lt 0) {
            $entries += [PSCustomObject]@{
                name   = $k.name.ToLower()
                lic    = ""
                piot   = ""
                fnNum  = ""
                fnDate = ""
                serial = ""
                fw     = ""
            }
            $idx = $entries.Count - 1
            $summary.Added++
        }

        $changed = $false
        $piotFinal = if ($feat.Piot) { $feat.Piot } else { $piotRu }
        if ($feat.Commercial -and $entries[$idx].lic -ne $feat.Commercial) { $entries[$idx].lic = $feat.Commercial; $changed = $true }
        if ($piotFinal -and $entries[$idx].piot -ne $piotFinal) { $entries[$idx].piot = $piotFinal; $changed = $true }
        if ($kkmInfo.FnNum -and $entries[$idx].fnNum -ne $kkmInfo.FnNum) { $entries[$idx].fnNum = $kkmInfo.FnNum; $changed = $true }
        if ($kkmInfo.FnDate -and $entries[$idx].fnDate -ne $kkmInfo.FnDate) { $entries[$idx].fnDate = $kkmInfo.FnDate; $changed = $true }
        if ($kkmInfo.Serial -and $entries[$idx].serial -ne $kkmInfo.Serial) { $entries[$idx].serial = $kkmInfo.Serial; $changed = $true }
        if ($kkmInfo.Fw -and $entries[$idx].fw -ne $kkmInfo.Fw) { $entries[$idx].fw = $kkmInfo.Fw; $changed = $true }

        if ($changed) { $summary.Updated++ }
        if (-not $piotRu) { $summary.NoData++ }
        elseif ($piotInfo.DaysLeft -and [int]$piotInfo.DaysLeft -lt 60) { $summary.ExpiresSoon++ }

        $mark = if ($changed) { " updated" } else { "" }
        Add-Log ("{0,-9} {1,-16} lic={2,-11} piot={3,-11} fn={4} ({5}){6}" -f $k.name, $k.ip, $entries[$idx].lic, $entries[$idx].piot, $kkmInfo.FnNum, $kkmInfo.FnDate, $mark)
    }

    $json = ConvertTo-MonitorJson -Entries $entries
    $summary.Json = $json

    if (-not $DryRun) {
        $openTag = '<script type="application/json" id="kkt-data">'
        $si = $html.IndexOf($openTag)
        $ei = $html.IndexOf("</script>", $si + $openTag.Length)
        if ($si -ge 0 -and $ei -gt $si) {
            $newHtml = $html.Substring(0, $si + $openTag.Length) + "`n" + $json + "`n" + $html.Substring($ei)
            [System.IO.File]::WriteAllText($MonitorFile, $newHtml, (New-Object System.Text.UTF8Encoding($false)))
        } else {
            Add-Log "Could not locate data block boundaries - file left unchanged"
        }
    }

    return $summary
}
