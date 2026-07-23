# FR (Fiscal Register) TCP communication module
# Sends hex commands via TCP tunnel (127.0.0.1:local_port -> FR)
# Source: . "$PSScriptRoot\fr.ps1"

function Send-FrCommand {
    param(
        [string]$FrHost,
        [int]$Port,
        [byte[]]$Command,
        [int]$TimeoutMs = 3000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.ReceiveTimeout = $TimeoutMs
        $client.SendTimeout = $TimeoutMs
        $client.Connect($FrHost, $Port)

        $stream = $client.GetStream()
        $stream.Write($Command, 0, $Command.Count)
        Start-Sleep -Milliseconds 200

        $buf = New-Object byte[] 1024
        $resp = [System.Collections.Generic.List[byte]]::new()
        try {
            while ($true) {
                $n = $stream.Read($buf, 0, 1024)
                if ($n -eq 0) { break }
                $resp.AddRange($buf[0..($n - 1)])
            }
        } catch {}
        return ,$resp.ToArray()
    } finally {
        $client.Close()
    }
}

function Get-FrShortStatus {
    param([string]$FrHost, [int]$Port, [byte]$Password = 0x1E)
    $resp = Send-FrCommand $FrHost $Port @(0x10, $Password)
    if ($resp.Count -lt 3 -or $resp[1] -ne 0) { return $null }

    $b = $resp
    $flags = @{}
    if ($resp.Count -ge 8) {
        $flags.ShiftOpen    = ($b[3] -band 1) -ne 0
        $flags.Shift24h     = ($b[3] -band 2) -ne 0
        $flags.ReceiptOpen  = ($b[3] -band 4) -ne 0
        $flags.PaperOut     = ($b[4] -band 4) -ne 0
        $flags.CoverOpen    = ($b[4] -band 8) -ne 0
        $flags.FatalError   = ($b[4] -band 0x20) -ne 0
        $flags.FnReady      = ($b[7] -band 0x80) -ne 0
        $flags.FnFiscalized = ($b[7] -band 2) -ne 0
        $flags.FnOverflow   = ($b[7] -band 8) -ne 0
        $flags.FnExpired    = ($b[7] -band 0x10) -ne 0
    }
    return @{
        ResultCode = $resp[1]
        Flags = $flags
        RawHex = ($resp | ForEach-Object { $_.ToString("X2") }) -join " "
    }
}

function Get-FrFullStatus {
    param([string]$FrHost, [int]$Port, [byte]$Password = 0x1E)
    $resp = Send-FrCommand $FrHost $Port @(0x11, $Password)
    if ($resp.Count -lt 21 -or $resp[1] -ne 0) { return $null }

    $b = $resp
    return @{
        ResultCode = $b[1]
        Model  = [System.Text.Encoding]::ASCII.GetString($b[21..29]).TrimEnd([char]0)
        Serial = if ($resp.Count -ge 40) { [System.Text.Encoding]::ASCII.GetString($b[30..39]).TrimEnd([char]0) } else { "" }
        Firmware = "$([int]$b[12]).$([int]$b[13])"
        FWDate   = "{0:D2}.{1:D2}.{2:D2}" -f $b[16], $b[17], $b[18]
        Protocol = "$([int]$b[9]).$([int]$b[10])"
        Mode     = $b[7]
        RawHex   = ($resp | ForEach-Object { $_.ToString("X2") }) -join " "
    }
}

function Get-FrDeviceType {
    param([string]$FrHost, [int]$Port)
    $resp = Send-FrCommand $FrHost $Port @(0xFC)
    if ($resp.Count -lt 3) { return $null }
    return [System.Text.Encoding]::ASCII.GetString($resp[2..($resp.Count-1)]).TrimEnd([char]0)
}
