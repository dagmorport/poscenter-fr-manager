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
. "$scriptDir\lib\fr.ps1"

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
$colorAccent    = [System.Drawing.Color]::FromArgb(0, 188, 212)
$colorBg        = [System.Drawing.Color]::FromArgb(250, 250, 250)
$colorSurface   = [System.Drawing.Color]::White
$colorOnSurface = [System.Drawing.Color]::FromArgb(33, 33, 33)
$colorOnSurface2 = [System.Drawing.Color]::FromArgb(158, 158, 158)
$colorDivider   = [System.Drawing.Color]::FromArgb(224, 224, 224)
$colorSuccess   = [System.Drawing.Color]::FromArgb(76, 175, 80)
$colorWarning   = [System.Drawing.Color]::FromArgb(255, 152, 0)
$colorError     = [System.Drawing.Color]::FromArgb(244, 67, 54)
$colorDark      = [System.Drawing.Color]::FromArgb(33, 33, 33)

# Backwards compatibility aliases
$colorGreen = $colorSuccess
$colorRed   = $colorError
$colorPurple = [System.Drawing.Color]::FromArgb(156, 39, 176)
$colorOrange = $colorWarning
$colorLightGray = $colorOnSurface2

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "POScenter FR Manager v$appVersion"
$form.Size = New-Object System.Drawing.Size(520, 660)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.TopMost = $false
$form.BackColor = $colorBg
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Title bar with version
$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Location = New-Object System.Drawing.Point(0, 0)
$titlePanel.Size = New-Object System.Drawing.Size(500, 50)
$titlePanel.BackColor = $colorPrimary
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

# Tab strip
$tabStrip = New-Object System.Windows.Forms.Panel
$tabStrip.Location = New-Object System.Drawing.Point(0, 50)
$tabStrip.Size = New-Object System.Drawing.Size(520, 42)
$tabStrip.BackColor = $colorPrimary
$form.Controls.Add($tabStrip)

$tabConnect = New-Object System.Windows.Forms.Button
$tabConnect.Text = "Connect"
$tabConnect.Location = New-Object System.Drawing.Point(8, 4)
$tabConnect.Size = New-Object System.Drawing.Size(100, 34)
$tabConnect.FlatStyle = "Flat"
$tabConnect.FlatAppearance.BorderSize = 0
$tabConnect.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 255, 50)
$tabConnect.ForeColor = [System.Drawing.Color]::White
$tabConnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$tabStrip.Controls.Add($tabConnect)

$tabFrStatus = New-Object System.Windows.Forms.Button
$tabFrStatus.Text = "FR Status"
$tabFrStatus.Location = New-Object System.Drawing.Point(112, 4)
$tabFrStatus.Size = New-Object System.Drawing.Size(100, 34)
$tabFrStatus.FlatStyle = "Flat"
$tabFrStatus.FlatAppearance.BorderSize = 0
$tabFrStatus.BackColor = [System.Drawing.Color]::Transparent
$tabFrStatus.ForeColor = [System.Drawing.Color]::FromArgb(200, 255, 255, 255)
$tabFrStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$tabStrip.Controls.Add($tabFrStatus)

# Tab panels
$panelConnect = New-Object System.Windows.Forms.Panel
$panelConnect.Location = New-Object System.Drawing.Point(10, 100)
$panelConnect.Size = New-Object System.Drawing.Size(490, 460)
$panelConnect.BackColor = $colorSurface
$panelConnect.Visible = $true
$form.Controls.Add($panelConnect)

$panelFrStatus = New-Object System.Windows.Forms.Panel
$panelFrStatus.Location = New-Object System.Drawing.Point(10, 100)
$panelFrStatus.Size = New-Object System.Drawing.Size(490, 460)
$panelFrStatus.BackColor = $colorSurface
$panelFrStatus.Visible = $false
$form.Controls.Add($panelFrStatus)

# Tab switching
$tabConnect.Add_Click({
    $tabConnect.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 255, 50)
    $tabConnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $tabFrStatus.BackColor = [System.Drawing.Color]::Transparent
    $tabFrStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $panelConnect.Visible = $true
    $panelFrStatus.Visible = $false
})
$tabFrStatus.Add_Click({
    $tabFrStatus.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 255, 50)
    $tabFrStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $tabConnect.BackColor = [System.Drawing.Color]::Transparent
    $tabConnect.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $panelConnect.Visible = $false
    $panelFrStatus.Visible = $true
})

# === CONNECT TAB ===
# Cash registers group
$groupKassas = New-Object System.Windows.Forms.GroupBox
$groupKassas.Text = "Cash Registers"
$groupKassas.Location = New-Object System.Drawing.Point(10, 10)
$groupKassas.Size = New-Object System.Drawing.Size(470, 160)
$groupKassas.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$panelConnect.Controls.Add($groupKassas)

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10, 22)
$listView.Size = New-Object System.Drawing.Size(450, 128)
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$listView.Columns.Add("Name", 130) | Out-Null
$listView.Columns.Add("IP Address", 170) | Out-Null

foreach ($k in $config.kassas) {
    $item = New-Object System.Windows.Forms.ListViewItem($k.name)
    $item.SubItems.Add($k.ip) | Out-Null
    $listView.Items.Add($item) | Out-Null
}
$groupKassas.Controls.Add($listView)

# Connection group
$groupPassword = New-Object System.Windows.Forms.GroupBox
$groupPassword.Text = "Connection"
$groupPassword.Location = New-Object System.Drawing.Point(10, 180)
$groupPassword.Size = New-Object System.Drawing.Size(470, 90)
$groupPassword.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$panelConnect.Controls.Add($groupPassword)

$pwLabel = New-Object System.Windows.Forms.Label
$pwLabel.Text = "Password:"
$pwLabel.Location = New-Object System.Drawing.Point(10, 28)
$pwLabel.AutoSize = $true
$groupPassword.Controls.Add($pwLabel)

$pwBox = New-Object System.Windows.Forms.TextBox
$pwBox.Location = New-Object System.Drawing.Point(85, 25)
$pwBox.Size = New-Object System.Drawing.Size(200, 28)
$pwBox.UseSystemPasswordChar = $true
$pwBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$groupPassword.Controls.Add($pwBox)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready"
$lblStatus.Location = New-Object System.Drawing.Point(295, 28)
$lblStatus.Size = New-Object System.Drawing.Size(160, 20)
$lblStatus.ForeColor = $colorGreen
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblStatus.TextAlign = "MiddleRight"
$groupPassword.Controls.Add($lblStatus)

# FR Address display
$lblFrAddr = New-Object System.Windows.Forms.Label
$lblFrAddr.Text = "FR: 127.0.0.1:$($config.local_port)"
$lblFrAddr.Location = New-Object System.Drawing.Point(10, 58)
$lblFrAddr.Size = New-Object System.Drawing.Size(250, 20)
$lblFrAddr.ForeColor = $colorPrimary
$lblFrAddr.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$groupPassword.Controls.Add($lblFrAddr)

# Connection timer
$lblTimer = New-Object System.Windows.Forms.Label
$lblTimer.Text = ""
$lblTimer.Location = New-Object System.Drawing.Point(270, 58)
$lblTimer.Size = New-Object System.Drawing.Size(185, 20)
$lblTimer.ForeColor = $colorOrange
$lblTimer.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblTimer.TextAlign = "MiddleRight"
$groupPassword.Controls.Add($lblTimer)

# Buttons panel
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Location = New-Object System.Drawing.Point(10, 280)
$btnPanel.Size = New-Object System.Drawing.Size(470, 45)
$panelConnect.Controls.Add($btnPanel)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = "Connect"
$btnConnect.Location = New-Object System.Drawing.Point(0, 5)
$btnConnect.Size = New-Object System.Drawing.Size(85, 35)
$btnConnect.BackColor = $colorSuccess
$btnConnect.ForeColor = [System.Drawing.Color]::White
$btnConnect.FlatStyle = "Flat"
$btnConnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnConnect)

$btnDisconnect = New-Object System.Windows.Forms.Button
$btnDisconnect.Text = "Disconnect"
$btnDisconnect.Location = New-Object System.Drawing.Point(95, 5)
$btnDisconnect.Size = New-Object System.Drawing.Size(85, 35)
$btnDisconnect.BackColor = $colorError
$btnDisconnect.ForeColor = [System.Drawing.Color]::White
$btnDisconnect.FlatStyle = "Flat"
$btnDisconnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnDisconnect)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Copy Address"
$btnCopy.Location = New-Object System.Drawing.Point(190, 5)
$btnCopy.Size = New-Object System.Drawing.Size(100, 35)
$btnCopy.BackColor = $colorPrimary
$btnCopy.ForeColor = [System.Drawing.Color]::White
$btnCopy.FlatStyle = "Flat"
$btnCopy.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnCopy)

$btnTestDriver = New-Object System.Windows.Forms.Button
$btnTestDriver.Text = [char]0x0422 + [char]0x0435 + [char]0x0441 + [char]0x0442 + " " + [char]0x0434 + [char]0x0440 + [char]0x0430 + [char]0x0439 + [char]0x0432 + [char]0x0435 + [char]0x0440
$btnTestDriver.Location = New-Object System.Drawing.Point(300, 5)
$btnTestDriver.Size = New-Object System.Drawing.Size(100, 35)
$btnTestDriver.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136)
$btnTestDriver.ForeColor = [System.Drawing.Color]::White
$btnTestDriver.FlatStyle = "Flat"
$btnTestDriver.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnTestDriver)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = "Update"
$btnUpdate.Location = New-Object System.Drawing.Point(410, 5)
$btnUpdate.Size = New-Object System.Drawing.Size(60, 35)
$btnUpdate.BackColor = $colorPurple
$btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.FlatStyle = "Flat"
$btnUpdate.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnPanel.Controls.Add($btnUpdate)

# Log area (inside connect tab)
$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = "Log"
$logLabel.Location = New-Object System.Drawing.Point(10, 335)
$logLabel.AutoSize = $true
$logLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$panelConnect.Controls.Add($logLabel)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(10, 355)
$logBox.Size = New-Object System.Drawing.Size(470, 95)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = $colorDark
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 0)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$panelConnect.Controls.Add($logBox)

# === FR STATUS TAB ===
# Query button
$btnQueryFr = New-Object System.Windows.Forms.Button
$btnQueryFr.Text = "Query FR Status"
$btnQueryFr.Location = New-Object System.Drawing.Point(10, 10)
$btnQueryFr.Size = New-Object System.Drawing.Size(470, 40)
$btnQueryFr.BackColor = $colorPrimary
$btnQueryFr.ForeColor = [System.Drawing.Color]::White
$btnQueryFr.FlatStyle = "Flat"
$btnQueryFr.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$panelFrStatus.Controls.Add($btnQueryFr)

# Status cards
$cardFn = New-Object System.Windows.Forms.Panel
$cardFn.Location = New-Object System.Drawing.Point(10, 60)
$cardFn.Size = New-Object System.Drawing.Size(470, 60)
$cardFn.BackColor = $colorSurface
$cardFn.BorderStyle = "FixedSingle"
$panelFrStatus.Controls.Add($cardFn)

$lblFnTitle = New-Object System.Windows.Forms.Label
$lblFnTitle.Text = "Fiscal Storage (FN)"
$lblFnTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblFnTitle.AutoSize = $true
$lblFnTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$cardFn.Controls.Add($lblFnTitle)

$lblFnStatus = New-Object System.Windows.Forms.Label
$lblFnStatus.Text = "Not checked"
$lblFnStatus.Location = New-Object System.Drawing.Point(10, 25)
$lblFnStatus.AutoSize = $true
$lblFnStatus.ForeColor = $colorOnSurface2
$cardFn.Controls.Add($lblFnStatus)

$cardShift = New-Object System.Windows.Forms.Panel
$cardShift.Location = New-Object System.Drawing.Point(10, 130)
$cardShift.Size = New-Object System.Drawing.Size(230, 60)
$cardShift.BackColor = $colorSurface
$cardShift.BorderStyle = "FixedSingle"
$panelFrStatus.Controls.Add($cardShift)

$lblShiftTitle = New-Object System.Windows.Forms.Label
$lblShiftTitle.Text = "Shift"
$lblShiftTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblShiftTitle.AutoSize = $true
$lblShiftTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$cardShift.Controls.Add($lblShiftTitle)

$lblShiftStatus = New-Object System.Windows.Forms.Label
$lblShiftStatus.Text = "Not checked"
$lblShiftStatus.Location = New-Object System.Drawing.Point(10, 25)
$lblShiftStatus.AutoSize = $true
$lblShiftStatus.ForeColor = $colorOnSurface2
$cardShift.Controls.Add($lblShiftStatus)

$cardDevice = New-Object System.Windows.Forms.Panel
$cardDevice.Location = New-Object System.Drawing.Point(250, 130)
$cardDevice.Size = New-Object System.Drawing.Size(230, 60)
$cardDevice.BackColor = $colorSurface
$cardDevice.BorderStyle = "FixedSingle"
$panelFrStatus.Controls.Add($cardDevice)

$lblDeviceTitle = New-Object System.Windows.Forms.Label
$lblDeviceTitle.Text = "Device"
$lblDeviceTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblDeviceTitle.AutoSize = $true
$lblDeviceTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$cardDevice.Controls.Add($lblDeviceTitle)

$lblDeviceStatus = New-Object System.Windows.Forms.Label
$lblDeviceStatus.Text = "Not checked"
$lblDeviceStatus.Location = New-Object System.Drawing.Point(10, 25)
$lblDeviceStatus.AutoSize = $true
$lblDeviceStatus.ForeColor = $colorOnSurface2
$cardDevice.Controls.Add($lblDeviceStatus)

# Raw hex textbox
$lblRawTitle = New-Object System.Windows.Forms.Label
$lblRawTitle.Text = "Raw response (hex)"
$lblRawTitle.Location = New-Object System.Drawing.Point(10, 200)
$lblRawTitle.AutoSize = $true
$lblRawTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$panelFrStatus.Controls.Add($lblRawTitle)

$txtRawHex = New-Object System.Windows.Forms.TextBox
$txtRawHex.Location = New-Object System.Drawing.Point(10, 220)
$txtRawHex.Size = New-Object System.Drawing.Size(470, 230)
$txtRawHex.Multiline = $true
$txtRawHex.ScrollBars = "Vertical"
$txtRawHex.ReadOnly = $true
$txtRawHex.BackColor = $colorDark
$txtRawHex.ForeColor = [System.Drawing.Color]::FromArgb(100, 255, 100)
$txtRawHex.Font = New-Object System.Drawing.Font("Consolas", 9)
$panelFrStatus.Controls.Add($txtRawHex)

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

$btnQueryFr.Add_Click({
    if (-not $script:connected) {
        $lblFnStatus.Text = "Not connected. Connect first."
        $lblFnStatus.ForeColor = $colorError
        return
    }
    $btnQueryFr.Enabled = $false
    $lblFnStatus.Text = "Querying..."
    $lblFnStatus.ForeColor = $colorWarning
    $lblShiftStatus.Text = "Querying..."
    $lblDeviceStatus.Text = "Querying..."
    $txtRawHex.Text = ""

    try {
        $pw = [byte]$config.operator_password
        $frHost = "127.0.0.1"
        $frPort = $config.local_port

        $short = Get-FrShortStatus $frHost $frPort $pw
        $full  = Get-FrFullStatus $frHost $frPort $pw
        $dev   = Get-FrDeviceType $frHost $frPort

        # FN status
        if ($short -and $short.Flags) {
            $f = $short.Flags
            $fnParts = @()
            if ($f.FnReady) { $fnParts += "Ready" } else { $fnParts += "NOT READY" }
            if ($f.FnFiscalized) { $fnParts += "Fiscalized" }
            if ($f.FnOverflow) { $fnParts += "OVERFLOW!" }
            if ($f.FnExpired) { $fnParts += "EXPIRED!" }
            $lblFnStatus.Text = ($fnParts -join " | ")
            $lblFnStatus.ForeColor = if ($f.FnReady -and -not $f.FnOverflow -and -not $f.FnExpired) { $colorSuccess } else { $colorError }

            # Shift
            $shParts = @()
            if ($f.ShiftOpen) { $shParts += "Open" } else { $shParts += "Closed" }
            if ($f.Shift24h) { $shParts += ">24h WARNING!" }
            if ($f.ReceiptOpen) { $shParts += "Receipt open" }
            $lblShiftStatus.Text = ($shParts -join " | ")
            $lblShiftStatus.ForeColor = if ($f.Shift24h) { $colorWarning } else { $colorSuccess }

            # Error flags
            $errParts = @()
            if ($f.PaperOut) { $errParts += "NO PAPER" }
            if ($f.CoverOpen) { $errParts += "COVER OPEN" }
            if ($f.FatalError) { $errParts += "FATAL ERROR" }
            if ($errParts) {
                $lblFnStatus.Text += " | ERR: " + ($errParts -join ", ")
                $lblFnStatus.ForeColor = $colorError
            }

            # Raw hex
            $txtRawHex.AppendText("Short (10h): $($short.RawHex)`r`n`r`n")
        } else {
            $lblFnStatus.Text = "No response (10h)"
            $lblFnStatus.ForeColor = $colorError
        }

        # Device info
        if ($full) {
            $lblDeviceStatus.Text = "$($full.Model) | FW: $($full.Firmware) | $($full.FWDate)"
            if ($full.Serial) { $lblDeviceStatus.Text += "`r`nSN: $($full.Serial)" }
            $lblDeviceStatus.ForeColor = $colorSuccess
            $txtRawHex.AppendText("Full (11h): $($full.RawHex)`r`n`r`n")
        } elseif ($dev) {
            $lblDeviceStatus.Text = "Type: $dev"
            $lblDeviceStatus.ForeColor = $colorSuccess
        } else {
            $lblDeviceStatus.Text = "No device info"
            $lblDeviceStatus.ForeColor = $colorOnSurface2
        }

    } catch {
        $lblFnStatus.Text = "Error: $_"
        $lblFnStatus.ForeColor = $colorError
    }
    $btnQueryFr.Enabled = $true
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
