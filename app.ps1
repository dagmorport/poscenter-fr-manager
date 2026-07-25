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
$script:connectedIP = ""
$script:connectedPw = ""

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
$form.Size = New-Object System.Drawing.Size(500, 680)
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
$groupKassas.Text = [char]0x041A + [char]0x0430 + [char]0x0441 + [char]0x0441 + [char]0x044B
$groupKassas.Location = New-Object System.Drawing.Point(15, 60)
$groupKassas.Size = New-Object System.Drawing.Size(455, 150)
$groupKassas.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupKassas)

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10, 22)
$listView.Size = New-Object System.Drawing.Size(435, 118)
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.HideSelection = $false
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
$groupPassword.Text = [char]0x041F + [char]0x043E + [char]0x0434 + [char]0x043A + [char]0x043B + [char]0x044E + [char]0x0447 + [char]0x0435 + [char]0x043D + [char]0x0438 + [char]0x0435
$groupPassword.Location = New-Object System.Drawing.Point(15, 220)
$groupPassword.Size = New-Object System.Drawing.Size(455, 60)
$groupPassword.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupPassword)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = [char]0x0413 + [char]0x043E + [char]0x0442 + [char]0x043E + [char]0x0432
$lblStatus.Location = New-Object System.Drawing.Point(10, 18)
$lblStatus.Size = New-Object System.Drawing.Size(200, 20)
$lblStatus.ForeColor = $colorGreen
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$groupPassword.Controls.Add($lblStatus)

$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = "root@"
$lblUser.Location = New-Object System.Drawing.Point(220, 20)
$lblUser.AutoSize = $true
$lblUser.ForeColor = $colorLightGray
$lblUser.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$groupPassword.Controls.Add($lblUser)

# FR Address display
$lblFrAddr = New-Object System.Windows.Forms.Label
$lblFrAddr.Text = "FR: 127.0.0.1:$($config.local_port)"
$lblFrAddr.Location = New-Object System.Drawing.Point(10, 38)
$lblFrAddr.Size = New-Object System.Drawing.Size(250, 20)
$lblFrAddr.ForeColor = $colorAccent
$lblFrAddr.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$groupPassword.Controls.Add($lblFrAddr)

# Connection timer
$lblTimer = New-Object System.Windows.Forms.Label
$lblTimer.Text = ""
$lblTimer.Location = New-Object System.Drawing.Point(270, 38)
$lblTimer.Size = New-Object System.Drawing.Size(170, 20)
$lblTimer.ForeColor = $colorOrange
$lblTimer.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblTimer.TextAlign = "MiddleRight"
$groupPassword.Controls.Add($lblTimer)

# System Commands group
$groupRemote = New-Object System.Windows.Forms.GroupBox
$groupRemote.Text = [char]0x0421 + [char]0x0438 + [char]0x0441 + [char]0x0442 + [char]0x0435 + [char]0x043C + [char]0x043D + [char]0x044B + [char]0x0435 + " " + [char]0x043A + [char]0x043E + [char]0x043C + [char]0x0430 + [char]0x043D + [char]0x0434 + [char]0x044B
$groupRemote.Location = New-Object System.Drawing.Point(15, 290)
$groupRemote.Size = New-Object System.Drawing.Size(455, 75)
$groupRemote.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupRemote)

$cmbCommands = New-Object System.Windows.Forms.ComboBox
$cmbCommands.Location = New-Object System.Drawing.Point(10, 25)
$cmbCommands.Size = New-Object System.Drawing.Size(280, 25)
$cmbCommands.DropDownStyle = "DropDownList"
$cmbCommands.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$groupRemote.Controls.Add($cmbCommands)

$btnExecCmd = New-Object System.Windows.Forms.Button
$btnExecCmd.Text = [char]0x0412 + [char]0x044B + [char]0x043F + [char]0x043E + [char]0x043B + [char]0x043D + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnExecCmd.Location = New-Object System.Drawing.Point(300, 22)
$btnExecCmd.Size = New-Object System.Drawing.Size(140, 25)
$btnExecCmd.BackColor = $colorPrimary
$btnExecCmd.ForeColor = [System.Drawing.Color]::White
$btnExecCmd.FlatStyle = "Flat"
$btnExecCmd.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnExecCmd.Cursor = [System.Windows.Forms.Cursors]::Hand
$groupRemote.Controls.Add($btnExecCmd)

$lblCmdDesc = New-Object System.Windows.Forms.Label
$lblCmdDesc.Text = ""
$lblCmdDesc.Location = New-Object System.Drawing.Point(10, 55)
$lblCmdDesc.Size = New-Object System.Drawing.Size(435, 20)
$lblCmdDesc.ForeColor = $colorLightGray
$lblCmdDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$groupRemote.Controls.Add($lblCmdDesc)

# Terminal Commands group
$groupTerminal = New-Object System.Windows.Forms.GroupBox
$groupTerminal.Text = [char]0x0422 + [char]0x0435 + [char]0x0440 + [char]0x043C + [char]0x0438 + [char]0x043D + [char]0x0430 + [char]0x043B + " " + [char]0x0421 + [char]0x0431 + [char]0x0435 + [char]0x0440 + [char]0x0431 + [char]0x0430 + [char]0x043D + [char]0x043A
$groupTerminal.Location = New-Object System.Drawing.Point(15, 370)
$groupTerminal.Size = New-Object System.Drawing.Size(455, 75)
$groupTerminal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupTerminal)

$cmbTerminal = New-Object System.Windows.Forms.ComboBox
$cmbTerminal.Location = New-Object System.Drawing.Point(10, 25)
$cmbTerminal.Size = New-Object System.Drawing.Size(280, 25)
$cmbTerminal.DropDownStyle = "DropDownList"
$cmbTerminal.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$groupTerminal.Controls.Add($cmbTerminal)

$btnExecTerminal = New-Object System.Windows.Forms.Button
$btnExecTerminal.Text = [char]0x0412 + [char]0x044B + [char]0x043F + [char]0x043E + [char]0x043B + [char]0x043D + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnExecTerminal.Location = New-Object System.Drawing.Point(300, 22)
$btnExecTerminal.Size = New-Object System.Drawing.Size(140, 25)
$btnExecTerminal.BackColor = $colorSuccess
$btnExecTerminal.ForeColor = [System.Drawing.Color]::White
$btnExecTerminal.FlatStyle = "Flat"
$btnExecTerminal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnExecTerminal.Cursor = [System.Windows.Forms.Cursors]::Hand
$groupTerminal.Controls.Add($btnExecTerminal)

$lblTermDesc = New-Object System.Windows.Forms.Label
$lblTermDesc.Text = ""
$lblTermDesc.Location = New-Object System.Drawing.Point(10, 55)
$lblTermDesc.Size = New-Object System.Drawing.Size(435, 20)
$lblTermDesc.ForeColor = $colorLightGray
$lblTermDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$groupTerminal.Controls.Add($lblTermDesc)

# Populate command lists
if ($config.remote_commands) {
    foreach ($cmd in $config.remote_commands) {
        if ($cmd.group -eq "terminal") {
            $cmbTerminal.Items.Add($cmd.label) | Out-Null
        } else {
            $cmbCommands.Items.Add($cmd.label) | Out-Null
        }
    }
    if ($cmbCommands.Items.Count -gt 0) { $cmbCommands.SelectedIndex = 0 }
    if ($cmbTerminal.Items.Count -gt 0) { $cmbTerminal.SelectedIndex = 0 }
}

$cmbCommands.Add_SelectedIndexChanged({
    if ($cmbCommands.SelectedIndex -ge 0) {
        $sel = $cmbCommands.SelectedItem
        $cmdObj = $config.remote_commands | Where-Object { $_.label -eq $sel } | Select-Object -First 1
        if ($cmdObj -and $cmdObj.description) {
            $lblCmdDesc.Text = $cmdObj.description
        } else {
            $lblCmdDesc.Text = ""
        }
    }
})

$cmbTerminal.Add_SelectedIndexChanged({
    if ($cmbTerminal.SelectedIndex -ge 0) {
        $sel = $cmbTerminal.SelectedItem
        $cmdObj = $config.remote_commands | Where-Object { $_.label -eq $sel } | Select-Object -First 1
        if ($cmdObj -and $cmdObj.description) {
            $lblTermDesc.Text = $cmdObj.description
        } else {
            $lblTermDesc.Text = ""
        }
    }
})

# Buttons panel
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Location = New-Object System.Drawing.Point(15, 455)
$btnPanel.Size = New-Object System.Drawing.Size(455, 55)
$form.Controls.Add($btnPanel)

# Row 1 - Primary actions
$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = [char]0x041F + [char]0x043E + [char]0x0434 + [char]0x043A + [char]0x043B
$btnConnect.Location = New-Object System.Drawing.Point(0, 2)
$btnConnect.Size = New-Object System.Drawing.Size(90, 25)
$btnConnect.BackColor = $colorPrimary
$btnConnect.ForeColor = [System.Drawing.Color]::White
$btnConnect.FlatStyle = "Flat"
$btnConnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnConnect.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPanel.Controls.Add($btnConnect)

$btnDisconnect = New-Object System.Windows.Forms.Button
$btnDisconnect.Text = [char]0x0421 + [char]0x0442 + [char]0x043E + [char]0x043F
$btnDisconnect.Location = New-Object System.Drawing.Point(100, 2)
$btnDisconnect.Size = New-Object System.Drawing.Size(90, 25)
$btnDisconnect.BackColor = $colorRed
$btnDisconnect.ForeColor = [System.Drawing.Color]::White
$btnDisconnect.FlatStyle = "Flat"
$btnDisconnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDisconnect.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPanel.Controls.Add($btnDisconnect)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = [char]0x041A + [char]0x043E + [char]0x043F + [char]0x0438 + [char]0x0440 + [char]0x043E + [char]0x0432 + [char]0x0430 + [char]0x0442 + [char]0x044C
$btnCopy.Location = New-Object System.Drawing.Point(200, 2)
$btnCopy.Size = New-Object System.Drawing.Size(120, 25)
$btnCopy.BackColor = $colorPrimary
$btnCopy.ForeColor = [System.Drawing.Color]::White
$btnCopy.FlatStyle = "Flat"
$btnCopy.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnCopy.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPanel.Controls.Add($btnCopy)

# Row 2 - Utility actions
$btnTestDriver = New-Object System.Windows.Forms.Button
$btnTestDriver.Text = [char]0x0422 + [char]0x0435 + [char]0x0441 + [char]0x0442 + " " + [char]0x0434 + [char]0x0440 + [char]0x0430 + [char]0x0439 + [char]0x0432 + [char]0x0435 + [char]0x0440
$btnTestDriver.Location = New-Object System.Drawing.Point(0, 30)
$btnTestDriver.Size = New-Object System.Drawing.Size(150, 22)
$btnTestDriver.BackColor = $colorLightGray
$btnTestDriver.ForeColor = [System.Drawing.Color]::White
$btnTestDriver.FlatStyle = "Flat"
$btnTestDriver.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnTestDriver.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPanel.Controls.Add($btnTestDriver)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = [char]0x041E + [char]0x0431 + [char]0x043D + [char]0x043E + [char]0x0432 + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnUpdate.Location = New-Object System.Drawing.Point(160, 30)
$btnUpdate.Size = New-Object System.Drawing.Size(100, 22)
$btnUpdate.BackColor = $colorLightGray
$btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.FlatStyle = "Flat"
$btnUpdate.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnUpdate.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPanel.Controls.Add($btnUpdate)

# Log area
$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = [char]0x0416 + [char]0x0443 + [char]0x0440 + [char]0x043D + [char]0x0430 + [char]0x043B
$logLabel.Location = New-Object System.Drawing.Point(15, 520)
$logLabel.AutoSize = $true
$logLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($logLabel)

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = [char]0x041E + [char]0x0447 + [char]0x0438 + [char]0x0441 + [char]0x0442 + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnClearLog.Location = New-Object System.Drawing.Point(420, 518)
$btnClearLog.Size = New-Object System.Drawing.Size(50, 20)
$btnClearLog.BackColor = $colorLightGray
$btnClearLog.ForeColor = [System.Drawing.Color]::White
$btnClearLog.FlatStyle = "Flat"
$btnClearLog.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$btnClearLog.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnClearLog)

$btnClearLog.Add_Click({
    $logBox.Clear()
})

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, 542)
$logBox.Size = New-Object System.Drawing.Size(455, 130)
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

    $btnConnect.Enabled = $false
    $selected = $listView.SelectedItems[0]
    $kassaIP = $selected.SubItems[1].Text
    $kassaName = $selected.Text
    $pw = $config.ssh_password

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
        $script:connectedIP = $kassaIP
        $script:connectedPw = $pw
        $timer.Start()
    } else {
        Add-Log "   Port NOT listening after ${maxRetries}s"
        Add-Log "   TUNNEL FAILED"
        Set-Status "Tunnel Failed" "red"
        Stop-PlinkTunnels
    }

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
    $script:connectedIP = ""
    $script:connectedPw = ""
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

# Remote command execute button
$btnExecCmd.Add_Click({
    if ($cmbCommands.SelectedIndex -lt 0) {
        Add-Log "Select a command"
        return
    }

    $selectedLabel = $cmbCommands.SelectedItem
    $cmdObj = $config.remote_commands | Where-Object { $_.label -eq $selectedLabel } | Select-Object -First 1
    if (-not $cmdObj) {
        Add-Log "Command not found: $selectedLabel"
        return
    }

    $btnExecCmd.Enabled = $false
    Add-Log ">>> ${selectedLabel}: $($cmdObj.command)"
    Add-Log "--- output start ---"

    try {
        if ($cmdObj.local) {
            # Local command execution
            $scriptPath = Join-Path $scriptDir $cmdObj.command
            if (Test-Path $scriptPath) {
                $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Silent 2>&1
            } else {
                $result = & $cmdObj.command 2>&1
            }
        } else {
            # Remote SSH command - auto-connect if needed
            $kassaIP = $script:connectedIP
            $kassaPw = $script:connectedPw

            if (-not $script:connected) {
                # Use selected kassa from list and password from input
                if ($listView.SelectedItems.Count -eq 0) {
                    Add-Log "Select a cash register"
                    Add-Log "--- output end ---"
                    $btnExecCmd.Enabled = $true
                    return
                }
                $kassaIP = $listView.SelectedItems[0].SubItems[1].Text
                $kassaPw = $config.ssh_password
                Add-Log "Connecting to $kassaIP..."

                # Test SSH connection
                $test = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP "echo SSH_OK" 2>&1
                $testStr = ($test -join "`n").Trim()
                if ($testStr -notmatch "SSH_OK") {
                    Add-Log "SSH error - check password/IP"
                    Add-Log "--- output end ---"
                    $btnExecCmd.Enabled = $true
                    return
                }
                Add-Log "SSH OK"
            }

            $result = Invoke-Plink -PlinkPath $plinkPath -HostName $kassaIP -Port $config.ssh_port `
                -User $config.ssh_user -Password $kassaPw -Command $cmdObj.command
        }
        if ($result -and $result.Count -gt 0) {
            foreach ($line in $result) {
                Add-Log "$line"
            }
        } else {
            Add-Log "(no output)"
        }
    } catch {
        Add-Log "Error: $_"
    }

    Add-Log "--- output end ---"
    $btnExecCmd.Enabled = $true
})

# Terminal command execute button
$btnExecTerminal.Add_Click({
    if ($cmbTerminal.SelectedIndex -lt 0) {
        Add-Log "Select a command"
        return
    }

    $selectedLabel = $cmbTerminal.SelectedItem
    $cmdObj = $config.remote_commands | Where-Object { $_.label -eq $selectedLabel } | Select-Object -First 1
    if (-not $cmdObj) {
        Add-Log "Command not found: $selectedLabel"
        return
    }

    $btnExecTerminal.Enabled = $false
    Add-Log ">>> ${selectedLabel}: $($cmdObj.command)"
    Add-Log "--- output start ---"

    try {
        if ($cmdObj.local) {
            $scriptPath = Join-Path $scriptDir $cmdObj.command
            if (Test-Path $scriptPath) {
                $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Silent 2>&1
            } else {
                $result = & $cmdObj.command 2>&1
            }
        } else {
            $kassaIP = $script:connectedIP
            $kassaPw = $script:connectedPw

            if (-not $script:connected) {
                if ($listView.SelectedItems.Count -eq 0) {
                    Add-Log "Select a cash register"
                    Add-Log "--- output end ---"
                    $btnExecTerminal.Enabled = $true
                    return
                }
                $kassaIP = $listView.SelectedItems[0].SubItems[1].Text
                $kassaPw = $config.ssh_password
                Add-Log "Connecting to $kassaIP..."

                $test = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP "echo SSH_OK" 2>&1
                $testStr = ($test -join "`n").Trim()
                if ($testStr -notmatch "SSH_OK") {
                    Add-Log "SSH error - check password/IP"
                    Add-Log "--- output end ---"
                    $btnExecTerminal.Enabled = $true
                    return
                }
                Add-Log "SSH OK"
            }

            $result = Invoke-Plink -PlinkPath $plinkPath -HostName $kassaIP -Port $config.ssh_port `
                -User $config.ssh_user -Password $kassaPw -Command $cmdObj.command
        }
        if ($result -and $result.Count -gt 0) {
            foreach ($line in $result) {
                Add-Log "$line"
            }
        } else {
            Add-Log "(no output)"
        }
    } catch {
        Add-Log "Error: $_"
    }

    Add-Log "--- output end ---"
    $btnExecTerminal.Enabled = $true
})

# Button hover effects
function Add-ButtonHover {
    param([System.Windows.Forms.Button]$btn, [System.Drawing.Color]$normalColor)
    $hoverColor = [System.Drawing.Color]::FromArgb(
        [Math]::Min(255, $normalColor.R + 30),
        [Math]::Min(255, $normalColor.G + 30),
        [Math]::Min(255, $normalColor.B + 30)
    )
    $btn.Add_MouseEnter({ $this.BackColor = $hoverColor })
    $btn.Add_MouseLeave({ $this.BackColor = $normalColor })
}

Add-ButtonHover $btnConnect $colorPrimary
Add-ButtonHover $btnDisconnect $colorRed
Add-ButtonHover $btnCopy $colorPrimary
Add-ButtonHover $btnTestDriver $colorLightGray
Add-ButtonHover $btnUpdate $colorLightGray
Add-ButtonHover $btnExecCmd $colorPrimary
Add-ButtonHover $btnExecTerminal $colorSuccess
Add-ButtonHover $btnClearLog $colorLightGray

# Startup
Rotate-Logs
Add-Log "Application started v$appVersion"
Add-Log "FR address: 127.0.0.1:$($config.local_port)"
Add-Log "Cash registers: $($config.kassas.Count)"

# Check for updates on startup (async, uses shared Check-Update)
Start-Job -ScriptBlock { Check-Update } | Out-Null

$form.ShowDialog() | Out-Null
$timer.Stop()
