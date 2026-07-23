# POScenter FR Manager - WinForms Version
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$localConfig = Join-Path $scriptDir "config.local.json"
$configFile = if (Test-Path $localConfig) { $localConfig } else { Join-Path $scriptDir "config.json" }

# Import modules
. "$scriptDir\lib\config.ps1"
. "$scriptDir\lib\ssh.ps1"
. "$scriptDir\lib\update.ps1"
. "$scriptDir\lib\logging.ps1"

try {
    $config = Read-Config $configFile
} catch {
    [System.Windows.Forms.MessageBox]::Show("Config error: $_", "POScenter FR Manager", "OK", "Error")
    exit 1
}
$plinkPath = Join-Path $scriptDir "plink.exe"
$testDriverPath = "C:\Program Files\Poscenter\DrvKKT\Bin\DrvFRTst.exe"
$repo = "dagmorport/poscenter-fr-manager"
$branch = "main"
$baseUrl = "https://raw.githubusercontent.com/$repo/$branch"

# Read version
$localVersionFile = Join-Path $scriptDir "version.txt"
$appVersion = if (Test-Path $localVersionFile) { (Get-Content $localVersionFile -Raw).Trim() } else { "0.0.0" }

# Global state
$script:connected = $false
$script:connectTime = $null
$script:connectedKassa = ""

# Colors - Material Design light palette
$colorPrimary   = [System.Drawing.Color]::FromArgb(25, 118, 210)
$colorBg        = [System.Drawing.Color]::FromArgb(250, 250, 250)
$colorSurface   = [System.Drawing.Color]::White
$colorSuccess   = [System.Drawing.Color]::FromArgb(76, 175, 80)
$colorError     = [System.Drawing.Color]::FromArgb(244, 67, 54)
$colorWarning   = [System.Drawing.Color]::FromArgb(255, 152, 0)
$colorDark      = [System.Drawing.Color]::FromArgb(33, 33, 33)

# Backwards compat aliases
$colorAccent    = $colorPrimary
$colorGreen     = $colorSuccess
$colorRed       = $colorError
$colorOrange    = $colorWarning
$colorPurple    = [System.Drawing.Color]::FromArgb(156, 39, 176)
$colorLightGray = [System.Drawing.Color]::FromArgb(158, 158, 158)

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "POScenter FR Manager v$appVersion"
$form.Size = New-Object System.Drawing.Size(500, 620)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.TopMost = $false
$form.BackColor = $colorBg
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Title bar with version
$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Location = New-Object System.Drawing.Point(0, 0)
$titlePanel.Size = New-Object System.Drawing.Size(500, 50)
$titlePanel.BackColor = $colorAccent
$form.Controls.Add($titlePanel)

$title = New-Object System.Windows.Forms.Label
$title.Text = "POScenter FR Manager"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::White
$title.Location = New-Object System.Drawing.Point(15, 12)
$title.AutoSize = $true
$titlePanel.Controls.Add($title)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = "v$appVersion"
$versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$versionLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 255, 255, 255)
$versionLabel.Location = New-Object System.Drawing.Point(420, 16)
$versionLabel.AutoSize = $true
$titlePanel.Controls.Add($versionLabel)

# Cash registers group
$groupKassas = New-Object System.Windows.Forms.GroupBox
$groupKassas.Text = "Cash Registers"
$groupKassas.Location = New-Object System.Drawing.Point(15, 60)
$groupKassas.Size = New-Object System.Drawing.Size(455, 160)
$groupKassas.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupKassas)

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10, 22)
$listView.Size = New-Object System.Drawing.Size(435, 128)
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$listView.Columns.Add("Name", 120) | Out-Null
$listView.Columns.Add("IP Address", 160) | Out-Null

foreach ($k in $config.kassas) {
    $item = New-Object System.Windows.Forms.ListViewItem($k.name)
    $item.SubItems.Add($k.ip) | Out-Null
    $listView.Items.Add($item) | Out-Null
}
$groupKassas.Controls.Add($listView)

# Connection group
$groupPassword = New-Object System.Windows.Forms.GroupBox
$groupPassword.Text = "Connection"
$groupPassword.Location = New-Object System.Drawing.Point(15, 230)
$groupPassword.Size = New-Object System.Drawing.Size(455, 85)
$groupPassword.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupPassword)

$pwLabel = New-Object System.Windows.Forms.Label
$pwLabel.Text = "Password:"
$pwLabel.Location = New-Object System.Drawing.Point(10, 25)
$pwLabel.AutoSize = $true
$groupPassword.Controls.Add($pwLabel)

$pwBox = New-Object System.Windows.Forms.TextBox
$pwBox.Location = New-Object System.Drawing.Point(80, 22)
$pwBox.Size = New-Object System.Drawing.Size(200, 25)
$pwBox.UseSystemPasswordChar = $true
$pwBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$groupPassword.Controls.Add($pwBox)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready"
$lblStatus.Location = New-Object System.Drawing.Point(290, 25)
$lblStatus.Size = New-Object System.Drawing.Size(150, 20)
$lblStatus.ForeColor = $colorGreen
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblStatus.TextAlign = "MiddleRight"
$groupPassword.Controls.Add($lblStatus)

# FR Address display
$lblFrAddr = New-Object System.Windows.Forms.Label
$lblFrAddr.Text = "FR: 127.0.0.1:$($config.local_port)"
$lblFrAddr.Location = New-Object System.Drawing.Point(10, 52)
$lblFrAddr.Size = New-Object System.Drawing.Size(250, 20)
$lblFrAddr.ForeColor = $colorAccent
$lblFrAddr.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$groupPassword.Controls.Add($lblFrAddr)

# Connection timer
$lblTimer = New-Object System.Windows.Forms.Label
$lblTimer.Text = ""
$lblTimer.Location = New-Object System.Drawing.Point(270, 52)
$lblTimer.Size = New-Object System.Drawing.Size(170, 20)
$lblTimer.ForeColor = $colorOrange
$lblTimer.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblTimer.TextAlign = "MiddleRight"
$groupPassword.Controls.Add($lblTimer)

# Buttons panel
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Location = New-Object System.Drawing.Point(15, 325)
$btnPanel.Size = New-Object System.Drawing.Size(455, 45)
$form.Controls.Add($btnPanel)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = "Connect"
$btnConnect.Location = New-Object System.Drawing.Point(0, 5)
$btnConnect.Size = New-Object System.Drawing.Size(85, 35)
$btnConnect.BackColor = $colorGreen
$btnConnect.ForeColor = [System.Drawing.Color]::White
$btnConnect.FlatStyle = "Flat"
$btnConnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnConnect)

$btnDisconnect = New-Object System.Windows.Forms.Button
$btnDisconnect.Text = "Disconnect"
$btnDisconnect.Location = New-Object System.Drawing.Point(95, 5)
$btnDisconnect.Size = New-Object System.Drawing.Size(85, 35)
$btnDisconnect.BackColor = $colorRed
$btnDisconnect.ForeColor = [System.Drawing.Color]::White
$btnDisconnect.FlatStyle = "Flat"
$btnDisconnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnDisconnect)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Copy Address"
$btnCopy.Location = New-Object System.Drawing.Point(190, 5)
$btnCopy.Size = New-Object System.Drawing.Size(95, 35)
$btnCopy.BackColor = $colorAccent
$btnCopy.ForeColor = [System.Drawing.Color]::White
$btnCopy.FlatStyle = "Flat"
$btnCopy.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnCopy)

$btnTestDriver = New-Object System.Windows.Forms.Button
$btnTestDriver.Text = [char]0x0422 + [char]0x0435 + [char]0x0441 + [char]0x0442 + " " + [char]0x0434 + [char]0x0440 + [char]0x0430 + [char]0x0439 + [char]0x0432 + [char]0x0435 + [char]0x0440
$btnTestDriver.Location = New-Object System.Drawing.Point(295, 5)
$btnTestDriver.Size = New-Object System.Drawing.Size(95, 35)
$btnTestDriver.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136)
$btnTestDriver.ForeColor = [System.Drawing.Color]::White
$btnTestDriver.FlatStyle = "Flat"
$btnTestDriver.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnTestDriver)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = "Update"
$btnUpdate.Location = New-Object System.Drawing.Point(400, 5)
$btnUpdate.Size = New-Object System.Drawing.Size(55, 35)
$btnUpdate.BackColor = $colorPurple
$btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.FlatStyle = "Flat"
$btnUpdate.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnUpdate)

# Log area
$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = "Log"
$logLabel.Location = New-Object System.Drawing.Point(15, 380)
$logLabel.AutoSize = $true
$logLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($logLabel)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, 400)
$logBox.Size = New-Object System.Drawing.Size(455, 180)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = $colorDark
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 0)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($logBox)

# Timer for connection duration
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($script:connected -and $script:connectTime) {
        $elapsed = (Get-Date) - $script:connectTime
        $hours = $elapsed.Hours.ToString("D2")
        $mins = $elapsed.Minutes.ToString("D2")
        $secs = $elapsed.Seconds.ToString("D2")
        $lblTimer.Text = "Connected: ${hours}:${mins}:${secs}"
    }
})

function Add-Log {
    param([string]$msg)
    Add-UILog -LogBox $logBox -msg $msg
}

function Set-Status {
    param([string]$text, [string]$color = "green")
    $lblStatus.Text = $text
    switch ($color) {
        "green"  { $lblStatus.ForeColor = $colorGreen }
        "red"    { $lblStatus.ForeColor = $colorRed }
        "yellow" { $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 193, 7) }
        "gray"   { $lblStatus.ForeColor = $colorLightGray }
    }
}

function Check-Update {
    try {
        $localVersion = if (Test-Path $localVersionFile) { (Get-Content $localVersionFile -Raw).Trim() } else { "0.0.0" }
        $remoteVersion = Get-RemoteVersion -BaseUrl $baseUrl

        if (Test-UpdateAvailable $localVersion $remoteVersion) {
            $form.Invoke([Action]{
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
            })
        } else {
            Add-Log "Already up to date (v$localVersion)"
        }
    } catch {
        Add-Log "Update check failed: $_"
    }
}

# Connect button
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

    Set-Status "Connecting..." "yellow"
    Add-Log "=== Connecting to $kassaName ($kassaIP) ==="

    # Kill old plink
    Stop-PlinkTunnels
    Start-Sleep -Milliseconds 500

    # Test SSH
    Add-Log "1. Testing SSH..."
    $test = & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "echo SSH_OK" 2>&1
    $testStr = ($test -join "`n").Trim()

    if ($testStr -match "SSH_OK") {
        Add-Log "   SSH OK"
    } else {
        Add-Log "   FAILED - check password/IP"
        Set-Status "SSH Failed" "red"
        $pwBox.Text = [string]::Empty
        $btnConnect.Enabled = $true
        return
    }

    # Disable graphics
    Add-Log "2. Disabling graphics..."
    $xorgOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "pgrep Xorg | head -1" 2>&1
    $xorgStr = ($xorgOut -join "`n").Trim()

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

    Stop-PlinkTunnels
    Start-Sleep -Milliseconds 500

    $tunnelArgs = "-batch -ssh -P $($config.ssh_port) -pw $pw -l $($config.ssh_user) -L $($config.local_port):$($config.fr_ip):$($config.fr_port) -N $kassaIP"
    $proc = Start-Process -FilePath $plinkPath -ArgumentList $tunnelArgs -PassThru -WindowStyle Hidden
    Add-Log "   plink started (PID: $($proc.Id))"

    # Retry port check (up to 10 seconds)
    $maxRetries = 10
    $portReady = $false
    for ($i = 1; $i -le $maxRetries; $i++) {
        Start-Sleep -Seconds 1
        $portCheck = netstat -ano | findstr ":$($config.local_port).*LISTEN"
        if ($portCheck) {
            $portReady = $true
            Add-Log "   Port listening after ${i}s"
            break
        }
    }

    if ($portReady) {
        Add-Log "   === CONNECTED ==="
        Add-Log "   FR address: 127.0.0.1:$($config.local_port)"
        Set-Status "Connected to $kassaName" "green"
        $script:connected = $true
        $script:connectTime = Get-Date
        $script:connectedKassa = $kassaName
        $timer.Start()
    } else {
        Add-Log "   Port NOT listening after ${maxRetries}s"
        Add-Log "   TUNNEL FAILED"
        Set-Status "Tunnel Failed" "red"
        Stop-PlinkTunnels
    }

    $pwBox.Text = [string]::Empty
    $btnConnect.Enabled = $true
    Write-AppLog "Connection attempt completed"
})

# Disconnect button
$btnDisconnect.Add_Click({
    Stop-PlinkTunnels
    Add-Log "Disconnected"
    Set-Status "Disconnected" "gray"
    $script:connected = $false
    $script:connectTime = $null
    $timer.Stop()
    $lblTimer.Text = ""
})

# Copy address button
$btnCopy.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText("127.0.0.1:$($config.local_port)")
    Add-Log "Copied: 127.0.0.1:$($config.local_port)"
})

# Update button
$btnUpdate.Add_Click({
    Add-Log "Checking for updates..."
    $btnUpdate.Enabled = $false
    Check-Update
    $btnUpdate.Enabled = $true
})

$btnTestDriver.Add_Click({
    if (Test-Path $testDriverPath) {
        Add-Log "Launching test driver..."
        Start-Process -FilePath $testDriverPath
    } else {
        Add-Log "Test driver not found: $testDriverPath"
        [System.Windows.Forms.MessageBox]::Show(
            "DrvFRTst.exe not found at:`n$testDriverPath`n`nInstall Poscenter DrvKKT driver.",
            "File Not Found",
            "OK",
            "Warning"
        )
    }
})

# Startup
Rotate-Logs
Add-Log "Application started v$appVersion"
Add-Log "FR address: 127.0.0.1:$($config.local_port)"
Add-Log "Cash registers: $($config.kassas.Count)"

# Check for updates on startup (async, uses shared Check-Update)
Start-Job -ScriptBlock { Check-Update } | Out-Null

$form.ShowDialog() | Out-Null
$timer.Stop()
