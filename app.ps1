# POScenter FR Manager - WinForms Version
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$config = Get-Content "$scriptDir\config.json" -Raw | ConvertFrom-Json
$plinkPath = Join-Path $scriptDir "plink.exe"
$repo = "dagmorport/poscenter-fr-manager"
$branch = "main"
$baseUrl = "https://raw.githubusercontent.com/$repo/$branch"

function Write-AppLog {
    param([string]$msg, [string]$level = "INFO")
    $logDir = Join-Path $scriptDir "logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $logFile = Join-Path $logDir "app_$(Get-Date -Format 'yyyy-MM-dd').log"
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$ts] [$level] $msg" -Encoding UTF8
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "POScenter FR Manager"
$form.Size = New-Object System.Drawing.Size(480, 550)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.TopMost = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

$title = New-Object System.Windows.Forms.Label
$title.Text = "POScenter FR Manager"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(15, 15)
$title.AutoSize = $true
$form.Controls.Add($title)

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(15, 50)
$listView.Size = New-Object System.Drawing.Size(430, 150)
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.Columns.Add("Name", 100) | Out-Null
$listView.Columns.Add("IP Address", 150) | Out-Null

foreach ($k in $config.kassas) {
    $item = New-Object System.Windows.Forms.ListViewItem($k.name)
    $item.SubItems.Add($k.ip) | Out-Null
    $listView.Items.Add($item) | Out-Null
}
$form.Controls.Add($listView)

$pwLabel = New-Object System.Windows.Forms.Label
$pwLabel.Text = "Password:"
$pwLabel.Location = New-Object System.Drawing.Point(15, 215)
$pwLabel.AutoSize = $true
$form.Controls.Add($pwLabel)

$pwBox = New-Object System.Windows.Forms.TextBox
$pwBox.Location = New-Object System.Drawing.Point(85, 212)
$pwBox.Size = New-Object System.Drawing.Size(200, 25)
$pwBox.UseSystemPasswordChar = $true
$form.Controls.Add($pwBox)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = "Connect"
$btnConnect.Location = New-Object System.Drawing.Point(15, 250)
$btnConnect.Size = New-Object System.Drawing.Size(100, 35)
$btnConnect.BackColor = [System.Drawing.Color]::FromArgb(76, 175, 80)
$btnConnect.ForeColor = [System.Drawing.Color]::White
$btnConnect.FlatStyle = "Flat"
$form.Controls.Add($btnConnect)

$btnDisconnect = New-Object System.Windows.Forms.Button
$btnDisconnect.Text = "Disconnect"
$btnDisconnect.Location = New-Object System.Drawing.Point(125, 250)
$btnDisconnect.Size = New-Object System.Drawing.Size(100, 35)
$btnDisconnect.BackColor = [System.Drawing.Color]::FromArgb(244, 67, 54)
$btnDisconnect.ForeColor = [System.Drawing.Color]::White
$btnDisconnect.FlatStyle = "Flat"
$form.Controls.Add($btnDisconnect)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Copy FR Address"
$btnCopy.Location = New-Object System.Drawing.Point(235, 250)
$btnCopy.Size = New-Object System.Drawing.Size(130, 35)
$btnCopy.BackColor = [System.Drawing.Color]::FromArgb(33, 150, 243)
$btnCopy.ForeColor = [System.Drawing.Color]::White
$btnCopy.FlatStyle = "Flat"
$form.Controls.Add($btnCopy)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = "Check Update"
$btnUpdate.Location = New-Object System.Drawing.Point(375, 250)
$btnUpdate.Size = New-Object System.Drawing.Size(70, 35)
$btnUpdate.BackColor = [System.Drawing.Color]::FromArgb(156, 39, 176)
$btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.FlatStyle = "Flat"
$btnUpdate.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$form.Controls.Add($btnUpdate)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, 295)
$logBox.Size = New-Object System.Drawing.Size(430, 170)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(34, 34, 34)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 0)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($logBox)

function Add-Log {
    param([string]$msg)
    $logBox.AppendText("`r`n$msg")
    $logBox.ScrollToCaret()
    Write-AppLog $msg
}

function Check-Update {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $localVersionFile = Join-Path $scriptDir "version.txt"
        $localVersion = if (Test-Path $localVersionFile) { (Get-Content $localVersionFile -Raw).Trim() } else { "0.0.0" }
        $remoteVersion = (Invoke-WebRequest -Uri "$baseUrl/version.txt" -UseBasicParsing -TimeoutSec 10).Content.Trim()

        $parts1 = $localVersion.Split('.')
        $parts2 = $remoteVersion.Split('.')
        $newer = $false
        for ($i = 0; $i -lt [Math]::Max($parts1.Count, $parts2.Count); $i++) {
            $a = if ($i -lt $parts1.Count) { [int]$parts1[$i] } else { 0 }
            $b = if ($i -lt $parts2.Count) { [int]$parts2[$i] } else { 0 }
            if ($b -gt $a) { $newer = $true; break }
            if ($b -lt $a) { break }
        }

        if ($newer) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "New version available: $remoteVersion (current: $localVersion)`n`nDownload update?",
                "Update Available",
                "YesNo",
                "Information"
            )
            if ($result -eq "Yes") {
                Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\update.ps1`"" -Wait
                [System.Windows.Forms.Application]::Restart()
            }
        }
    } catch {
        # Silent fail - don't annoy user if update check fails
    }
}

$btnConnect.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        Add-Log "Select a cash register"
        return
    }
    if ([string]::IsNullOrEmpty($pwBox.Text)) {
        Add-Log "Enter password"
        return
    }

    $btnConnect.Enabled = $false
    $selected = $listView.SelectedItems[0]
    $kassaIP = $selected.SubItems[1].Text
    $kassaName = $selected.Text
    $pw = $pwBox.Text

    Add-Log "=== Connecting to $kassaName ($kassaIP) ==="

    # Kill old plink
    Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    # Test SSH
    Add-Log "1. Testing SSH..."
    $test = & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "echo SSH_OK" 2>&1
    $testStr = ($test -join "`n").Trim()
    Add-Log "   Result: $testStr"

    if ($testStr -match "SSH_OK") {
        Add-Log "   SSH OK"
    } else {
        Add-Log "   FAILED - check password/IP"
        $btnConnect.Enabled = $true
        return
    }

    # Disable graphics
    Add-Log "2. Disabling graphics..."
    $xorgOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "pgrep Xorg | head -1" 2>&1
    $xorgStr = ($xorgOut -join "`n").Trim()
    Add-Log "   pgrep output: '$xorgStr'"

    $pidStr = ""
    if ($xorgStr -match '(\d+)') { $pidStr = $Matches[1] }

    if ($pidStr -match '^\d+$') {
        Add-Log "   Found Xorg PID: $pidStr"
        & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "sudo kill -INT $pidStr" 2>&1 | Out-Null
        Add-Log "   Graphics killed"
    } else {
        Add-Log "   Xorg not running (already disabled)"
    }

    Start-Sleep -Seconds 1

    # Start tunnel
    Add-Log "3. Starting tunnel..."
    Add-Log "   FR: $($config.fr_ip):$($config.fr_port)"
    Add-Log "   Local port: $($config.local_port)"

    Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    $tunnelArgs = "-batch -ssh -P $($config.ssh_port) -pw $pw -l $($config.ssh_user) -L $($config.local_port):$($config.fr_ip):$($config.fr_port) -N $kassaIP"
    $proc = Start-Process -FilePath $plinkPath -ArgumentList $tunnelArgs -PassThru -WindowStyle Hidden
    Add-Log "   plink started (PID: $($proc.Id))"

    Start-Sleep -Seconds 4

    $portCheck = netstat -ano | findstr ":$($config.local_port).*LISTEN"
    if ($portCheck) {
        Add-Log "   Port $($config.local_port) is listening"
        Add-Log "   === CONNECTED ==="
        Add-Log "   FR address: 127.0.0.1:$($config.local_port)"
    } else {
        Add-Log "   Port NOT listening"
        Add-Log "   TUNNEL FAILED"
    }

    $btnConnect.Enabled = $true
    Write-AppLog "Connection attempt completed"
})

$btnDisconnect.Add_Click({
    Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Add-Log "Disconnected"
})

$btnCopy.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText("127.0.0.1:$($config.local_port)")
    Add-Log "Copied: 127.0.0.1:$($config.local_port)"
})

$btnUpdate.Add_Click({
    Add-Log "Checking for updates..."
    $btnUpdate.Enabled = $false
    Check-Update
    $btnUpdate.Enabled = $true
})

Add-Log "Application started"
Add-Log "FR address: 127.0.0.1:$($config.local_port)"
Add-Log "Cash registers: $($config.kassas.Count)"

# Check for updates on startup
$localVersionFile = Join-Path $scriptDir "version.txt"
$localVersion = if (Test-Path $localVersionFile) { (Get-Content $localVersionFile -Raw).Trim() } else { "unknown" }
Add-Log "Version: $localVersion"

$updateCheck = {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteVersion = (Invoke-WebRequest -Uri "$baseUrl/version.txt" -UseBasicParsing -TimeoutSec 10).Content.Trim()
        $localV = if (Test-Path "$scriptDir\version.txt") { (Get-Content "$scriptDir\version.txt" -Raw).Trim() } else { "0.0.0" }

        $parts1 = $localV.Split('.')
        $parts2 = $remoteVersion.Split('.')
        $newer = $false
        for ($i = 0; $i -lt [Math]::Max($parts1.Count, $parts2.Count); $i++) {
            $a = if ($i -lt $parts1.Count) { [int]$parts1[$i] } else { 0 }
            $b = if ($i -lt $parts2.Count) { [int]$parts2[$i] } else { 0 }
            if ($b -gt $a) { $newer = $true; break }
            if ($b -lt $a) { break }
        }

        if ($newer) {
            $form.Invoke([Action]{
                $result = [System.Windows.Forms.MessageBox]::Show(
                    "New version available: $remoteVersion (current: $localV)`n`nDownload update?",
                    "Update Available",
                    "YesNo",
                    "Information"
                )
                if ($result -eq "Yes") {
                    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\update.ps1`"" -Wait
                    [System.Windows.Forms.Application]::Restart()
                }
            })
        }
    } catch {}
}
$updateCheck.BeginInvoke($null, $null) | Out-Null

$form.ShowDialog() | Out-Null
