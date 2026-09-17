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
. "$scriptDir\lib\monitor.ps1"

try {
    $config = Read-Config $configFile
} catch {
    [System.Windows.Forms.MessageBox]::Show("Config error: $_", "POScenter FR Manager", "OK", "Error")
    exit 1
}
$plinkPath = Join-Path $scriptDir "plink.exe"
$testDriverPath = $config.test_driver_path
$repo = "dagmorport/poscenter-fr-manager"
$branch = "main"
$baseUrl = "https://raw.githubusercontent.com/$repo/$branch"

# Read version
$localVersionFile = Join-Path $scriptDir "version.txt"
$appVersion = if (Test-Path $localVersionFile) { (Get-Content $localVersionFile -Raw).Trim() } else { "0.0.0" }

# Global state (PSObject for better debugging)
$State = [PSCustomObject]@{
    Connected = $false
    ConnectTime = $null
    ConnectedKassa = ""
    ConnectedIP = ""
    ConnectedPw = ""
    TunnelPID = $null
    GraphicsKilled = $false
}

# Async state for Connect / KKT-monitor. MUST be script-scoped: locals of an
# event-handler script block (Add_Click) are NOT visible to nested handlers
# (the Timer's Add_Tick) in PowerShell 5.1, so $task/$ps/$runspace/$timer
# declared in the click handler resolved to $null in the tick — the completion
# branch never ran and the button stayed disabled forever.
$script:conn = @{ runspace = $null; ps = $null; task = $null; timer = $null }
$script:mon  = @{ runspace = $null; ps = $null; task = $null; timer = $null }

# Colors - Material Design light palette
$colorPrimary   = [System.Drawing.Color]::FromArgb(25, 118, 210)
$colorBg        = [System.Drawing.Color]::FromArgb(250, 250, 250)
$colorSurface   = [System.Drawing.Color]::White
$colorSuccess   = [System.Drawing.Color]::FromArgb(76, 175, 80)
$colorError     = [System.Drawing.Color]::FromArgb(244, 67, 54)
$colorWarning   = [System.Drawing.Color]::FromArgb(255, 152, 0)
$colorDark      = [System.Drawing.Color]::FromArgb(33, 33, 33)
$colorAccent    = $colorPrimary
$colorGreen     = $colorSuccess
$colorRed       = $colorError
$colorOrange    = $colorWarning
$colorLightGray = [System.Drawing.Color]::FromArgb(158, 158, 158)

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "POScenter FR Manager v$appVersion"
$form.Size = New-Object System.Drawing.Size(500, 770)
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
$listView.Font = New-Object System.Drawing.Font("Consolas", 9)
$listView.Columns.Add("Name", 120) | Out-Null
$listView.Columns.Add("IP Address", 160) | Out-Null

foreach ($k in $config.kassas) {
    $item = New-Object System.Windows.Forms.ListViewItem($k.name)
    $item.SubItems.Add($k.ip) | Out-Null
    $listView.Items.Add($item) | Out-Null
}
$groupKassas.Controls.Add($listView)

# System Commands group
$groupRemote = New-Object System.Windows.Forms.GroupBox
$groupRemote.Text = [char]0x0421 + [char]0x0438 + [char]0x0441 + [char]0x0442 + [char]0x0435 + [char]0x043C + [char]0x043D + [char]0x044B + [char]0x0435 + " " + [char]0x043A + [char]0x043E + [char]0x043C + [char]0x0430 + [char]0x043D + [char]0x0434 + [char]0x044B
$groupRemote.Location = New-Object System.Drawing.Point(15, 220)
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
$groupTerminal.Text = $config.terminal_name
$groupTerminal.Location = New-Object System.Drawing.Point(15, 305)
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

# ESM group
$groupEsm = New-Object System.Windows.Forms.GroupBox
$groupEsm.Text = [char]0x0415 + [char]0x0421 + [char]0x041C
$groupEsm.Location = New-Object System.Drawing.Point(15, 390)
$groupEsm.Size = New-Object System.Drawing.Size(455, 75)
$groupEsm.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupEsm)

$cmbEsm = New-Object System.Windows.Forms.ComboBox
$cmbEsm.Location = New-Object System.Drawing.Point(10, 25)
$cmbEsm.Size = New-Object System.Drawing.Size(280, 25)
$cmbEsm.DropDownStyle = "DropDownList"
$cmbEsm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$groupEsm.Controls.Add($cmbEsm)

$btnExecEsm = New-Object System.Windows.Forms.Button
$btnExecEsm.Text = [char]0x0412 + [char]0x044B + [char]0x043F + [char]0x043E + [char]0x043B + [char]0x043D + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnExecEsm.Location = New-Object System.Drawing.Point(300, 22)
$btnExecEsm.Size = New-Object System.Drawing.Size(140, 25)
$btnExecEsm.BackColor = $colorWarning
$btnExecEsm.ForeColor = [System.Drawing.Color]::White
$btnExecEsm.FlatStyle = "Flat"
$btnExecEsm.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnExecEsm.Cursor = [System.Windows.Forms.Cursors]::Hand
$groupEsm.Controls.Add($btnExecEsm)

$lblEsmDesc = New-Object System.Windows.Forms.Label
$lblEsmDesc.Text = ""
$lblEsmDesc.Location = New-Object System.Drawing.Point(10, 55)
$lblEsmDesc.Size = New-Object System.Drawing.Size(435, 20)
$lblEsmDesc.ForeColor = $colorLightGray
$lblEsmDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$groupEsm.Controls.Add($lblEsmDesc)

# Populate command lists
if ($config.remote_commands) {
    foreach ($cmd in $config.remote_commands) {
        if ($cmd.group -eq "terminal") {
            $cmbTerminal.Items.Add($cmd.label) | Out-Null
        } elseif ($cmd.group -eq "esm") {
            $cmbEsm.Items.Add($cmd.label) | Out-Null
        } else {
            $cmbCommands.Items.Add($cmd.label) | Out-Null
        }
    }
    if ($cmbCommands.Items.Count -gt 0) { $cmbCommands.SelectedIndex = 0 }
    if ($cmbTerminal.Items.Count -gt 0) { $cmbTerminal.SelectedIndex = 0 }
    if ($cmbEsm.Items.Count -gt 0) { $cmbEsm.SelectedIndex = 0 }
}

$cmbCommands.Add_SelectedIndexChanged({
    if ($cmbCommands.SelectedIndex -ge 0) {
        $sel = $cmbCommands.SelectedItem
        $cmdObj = $config.remote_commands | Where-Object { $_.label -eq $sel } | Select-Object -First 1
        $lblCmdDesc.Text = if ($cmdObj -and $cmdObj.description) { $cmdObj.description } else { "" }
    }
})

$cmbTerminal.Add_SelectedIndexChanged({
    if ($cmbTerminal.SelectedIndex -ge 0) {
        $sel = $cmbTerminal.SelectedItem
        $cmdObj = $config.remote_commands | Where-Object { $_.label -eq $sel } | Select-Object -First 1
        $lblTermDesc.Text = if ($cmdObj -and $cmdObj.description) { $cmdObj.description } else { "" }
    }
})

$cmbEsm.Add_SelectedIndexChanged({
    if ($cmbEsm.SelectedIndex -ge 0) {
        $sel = $cmbEsm.SelectedItem
        $cmdObj = $config.remote_commands | Where-Object { $_.label -eq $sel } | Select-Object -First 1
        $lblEsmDesc.Text = if ($cmdObj -and $cmdObj.description) { $cmdObj.description } else { "" }
    }
})

# POScenter group (all buttons except Update)
$groupPoscenter = New-Object System.Windows.Forms.GroupBox
$groupPoscenter.Text = "POScenter"
$groupPoscenter.Location = New-Object System.Drawing.Point(15, 475)
$groupPoscenter.Size = New-Object System.Drawing.Size(455, 80)
$groupPoscenter.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupPoscenter)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text = [char]0x041F + [char]0x043E + [char]0x0434 + [char]0x043A + [char]0x043B
$btnConnect.Location = New-Object System.Drawing.Point(10, 20)
$btnConnect.Size = New-Object System.Drawing.Size(100, 25)
$btnConnect.BackColor = $colorPrimary
$btnConnect.ForeColor = [System.Drawing.Color]::White
$btnConnect.FlatStyle = "Flat"
$btnConnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnConnect.Cursor = [System.Windows.Forms.Cursors]::Hand
$groupPoscenter.Controls.Add($btnConnect)

$btnDisconnect = New-Object System.Windows.Forms.Button
$btnDisconnect.Text = [char]0x0421 + [char]0x0442 + [char]0x043E + [char]0x043F
$btnDisconnect.Location = New-Object System.Drawing.Point(120, 20)
$btnDisconnect.Size = New-Object System.Drawing.Size(100, 25)
$btnDisconnect.BackColor = $colorRed
$btnDisconnect.ForeColor = [System.Drawing.Color]::White
$btnDisconnect.FlatStyle = "Flat"
$btnDisconnect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDisconnect.Cursor = [System.Windows.Forms.Cursors]::Hand
$groupPoscenter.Controls.Add($btnDisconnect)

$btnTestDriver = New-Object System.Windows.Forms.Button
$btnTestDriver.Text = [char]0x0422 + [char]0x0435 + [char]0x0441 + [char]0x0442 + " " + [char]0x0434 + [char]0x0440 + [char]0x0430 + [char]0x0439 + [char]0x0432 + [char]0x0435 + [char]0x0440
$btnTestDriver.Location = New-Object System.Drawing.Point(230, 20)
$btnTestDriver.Size = New-Object System.Drawing.Size(150, 25)
$btnTestDriver.BackColor = $colorLightGray
$btnTestDriver.ForeColor = [System.Drawing.Color]::White
$btnTestDriver.FlatStyle = "Flat"
$btnTestDriver.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnTestDriver.Cursor = [System.Windows.Forms.Cursors]::Hand
$groupPoscenter.Controls.Add($btnTestDriver)

# FR Status button
$btnFrStatus = New-Object System.Windows.Forms.Button
$btnFrStatus.Text = [char]0x0421 + [char]0x0442 + [char]0x0430 + [char]0x0442 + [char]0x0443 + [char]0x0441 + " " + [char]0x0424 + [char]0x0420
$btnFrStatus.Location = New-Object System.Drawing.Point(10, 48)
$btnFrStatus.Size = New-Object System.Drawing.Size(100, 25)
$btnFrStatus.BackColor = $colorSuccess
$btnFrStatus.ForeColor = [System.Drawing.Color]::White
$btnFrStatus.FlatStyle = "Flat"
$btnFrStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnFrStatus.Cursor = [System.Windows.Forms.Cursors]::Hand
$groupPoscenter.Controls.Add($btnFrStatus)

# KKT monitor update button (all cash registers -> kkt_monitor*.html)
$btnMonitor = New-Object System.Windows.Forms.Button
$btnMonitor.Text = [char]0x041E + [char]0x0431 + [char]0x043D + [char]0x043E + [char]0x0432 + [char]0x0438 + [char]0x0442 + [char]0x044C + " " + [char]0x043C + [char]0x043E + [char]0x043D + [char]0x0438 + [char]0x0442 + [char]0x043E + [char]0x0440 + [char]0x0438 + [char]0x043D + [char]0x0433 + " " + [char]0x041A + [char]0x041A + [char]0x0422
$btnMonitor.Location = New-Object System.Drawing.Point(120, 48)
$btnMonitor.Size = New-Object System.Drawing.Size(200, 25)
$btnMonitor.BackColor = $colorPrimary
$btnMonitor.ForeColor = [System.Drawing.Color]::White
$btnMonitor.FlatStyle = "Flat"
$btnMonitor.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnMonitor.Cursor = [System.Windows.Forms.Cursors]::Hand
$groupPoscenter.Controls.Add($btnMonitor)

# Kill cash GUI on Connect so the FR socket is free for the KKT driver
$chkKillGraphics = New-Object System.Windows.Forms.CheckBox
$chkKillGraphics.Text = [char]0x0413 + [char]0x0430 + [char]0x0441 + [char]0x0438 + [char]0x0442 + [char]0x044C + " " + [char]0x0433 + [char]0x0440 + [char]0x0430 + [char]0x0444 + [char]0x0438 + [char]0x043A + [char]0x0443
$chkKillGraphics.Location = New-Object System.Drawing.Point(330, 52)
$chkKillGraphics.AutoSize = $true
$chkKillGraphics.Checked = $true
$chkKillGraphics.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$groupPoscenter.Controls.Add($chkKillGraphics)

# Log area
$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = [char]0x0416 + [char]0x0443 + [char]0x0440 + [char]0x043D + [char]0x0430 + [char]0x043B
$logLabel.Location = New-Object System.Drawing.Point(15, 565)
$logLabel.AutoSize = $true
$logLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($logLabel)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = [char]0x041E + [char]0x0431 + [char]0x043D + [char]0x043E + [char]0x0432 + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnUpdate.Location = New-Object System.Drawing.Point(340, 563)
$btnUpdate.Size = New-Object System.Drawing.Size(75, 20)
$btnUpdate.BackColor = $colorLightGray
$btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.FlatStyle = "Flat"
$btnUpdate.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$btnUpdate.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnUpdate)

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = [char]0x041E + [char]0x0447 + [char]0x0438 + [char]0x0441 + [char]0x0442 + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnClearLog.Location = New-Object System.Drawing.Point(420, 563)
$btnClearLog.Size = New-Object System.Drawing.Size(50, 20)
$btnClearLog.BackColor = $colorLightGray
$btnClearLog.ForeColor = [System.Drawing.Color]::White
$btnClearLog.FlatStyle = "Flat"
$btnClearLog.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$btnClearLog.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnClearLog)

$btnClearLog.Add_Click({ $logBox.Clear() })

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, 587)
$logBox.Size = New-Object System.Drawing.Size(455, 130)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = $colorDark
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 0)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($logBox)

# Helper functions
function Add-Log {
    param([string]$msg)
    Add-UILog -LogBox $logBox -msg $msg
}

# Highlight active kassa
function Set-ActiveKassa {
    param($item, [bool]$active)
    if ($active) {
        $item.BackColor = [System.Drawing.Color]::FromArgb(200, 230, 201)
        $item.ForeColor = [System.Drawing.Color]::FromArgb(27, 94, 32)
    } else {
        $item.BackColor = [System.Drawing.Color]::Empty
        $item.ForeColor = [System.Drawing.Color]::Empty
    }
}

# Stop plink by saved PID (precise kill)
function Stop-PlinkTunnels {
    if ($State.TunnelPID) {
        try {
            Stop-Process -Id $State.TunnelPID -Force -ErrorAction SilentlyContinue
        } catch {}
        $State.TunnelPID = $null
    }
    # Fallback: kill any remaining plink processes
    Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Remote command: collect TS PIOT license info (single quotes are safe for plink)
$piotCmd = "printf 'TSPIOT='; grep -c tspiotesm /linuxcash/cash/data/info/license.json 2>/dev/null; printf '\nERR55='; grep -ac 'error=55' /linuxcash/logs/current/fr_drv_ng.log 2>/dev/null; printf '\nESMSVC='; /linuxcash/cash/bin/currentsettings -s plugins:esmservice 2>/dev/null; printf '\nMARKVER='; /linuxcash/cash/bin/currentsettings -s MarkedGoods:markVerifyCrptService 2>/dev/null; printf '\nPIOT='; grep -ahorE 'licenses:\{[^}]*\}|licenseValidTo.{0,25}|active_till.{0,30}' /var/log/esp/esm/um/esm-orchestrator.log /var/log/esp/esm/um/esm-cm_*.log 2>/dev/null | tail -1"

# Parse TS PIOT info from cash register output
# (moved to lib/monitor.ps1 together with the monitor collection logic)

# Remote command: TS PIOT info + kkm.json fields (for kkt_monitor update)
$monitorCmd = $piotCmd + "; printf '\nKKM='; cat /linuxcash/cash/data/info/kkm.json 2>/dev/null"

# Kill cash GUI so the FR socket is free for the KKT driver (mirrors the Connect button)
$killGuiCmd = 'kill -9 `pgrep -x artix-gui | head -1` 2>/dev/null; kill -9 `pgrep Xorg | head -1` 2>/dev/null'
$guiStateCmd = 'pgrep -x artix-gui >/dev/null && echo GUI_ALIVE || echo GUI_DEAD'

# Execute selected command (DRY - shared logic)
function Invoke-SelectedCommand {
    param(
        [System.Windows.Forms.ComboBox]$comboBox,
        [System.Windows.Forms.Button]$btnExec
    )

    if ($comboBox.SelectedIndex -lt 0) {
        Add-Log "Select a command"
        return
    }

    $selectedLabel = $comboBox.SelectedItem
    $cmdObj = $config.remote_commands | Where-Object { $_.label -eq $selectedLabel } | Select-Object -First 1
    if (-not $cmdObj) {
        Add-Log "Command not found: $selectedLabel"
        return
    }

    $btnExec.Enabled = $false
    Add-Log ">>> ${selectedLabel}: $($cmdObj.command)"
    Add-Log "--- output start ---"

    try {
        if ($cmdObj.local) {
            $scriptPath = Join-Path $scriptDir $cmdObj.command
            $result = if (Test-Path $scriptPath) {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Silent 2>&1
            } else {
                & $cmdObj.command 2>&1
            }
        } else {
            $kassaIP = $State.ConnectedIP
            $kassaPw = $State.ConnectedPw

            if (-not $State.Connected) {
                if ($listView.SelectedItems.Count -eq 0) {
                    Add-Log "Select a cash register"
                    Add-Log "--- output end ---"
                    $btnExec.Enabled = $true
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
                    $btnExec.Enabled = $true
                    return
                }
                Add-Log "SSH OK"
            }

            $result = Invoke-Plink -PlinkPath $plinkPath -HostName $kassaIP -Port $config.ssh_port `
                -User $config.ssh_user -Password $kassaPw -Command $cmdObj.command
        }
        if ($result -and $result.Count -gt 0) {
            foreach ($line in $result) { Add-Log "$line" }
        } else {
            Add-Log "(no output)"
        }
    } catch {
        Add-Log "Error: $_"
    }

    Add-Log "--- output end ---"
    $btnExec.Enabled = $true
}

# Button hover effects
function Add-ButtonHover {
    param([System.Windows.Forms.Button]$btn, [System.Drawing.Color]$normalColor)
    $hoverColor = [System.Drawing.Color]::FromArgb(
        [Math]::Min(255, $normalColor.R + 30),
        [Math]::Min(255, $normalColor.G + 30),
        [Math]::Min(255, $normalColor.B + 30)
    )
    $btn.Tag = @{ Normal = $normalColor; Hover = $hoverColor }
    $btn.Add_MouseEnter({ $this.BackColor = $this.Tag.Hover })
    $btn.Add_MouseLeave({ $this.BackColor = $this.Tag.Normal })
}

Add-ButtonHover $btnConnect $colorPrimary
Add-ButtonHover $btnDisconnect $colorRed
Add-ButtonHover $btnTestDriver $colorLightGray
Add-ButtonHover $btnFrStatus $colorSuccess
Add-ButtonHover $btnMonitor $colorPrimary
Add-ButtonHover $btnUpdate $colorLightGray
Add-ButtonHover $btnExecCmd $colorPrimary
Add-ButtonHover $btnExecTerminal $colorSuccess
Add-ButtonHover $btnExecEsm $colorWarning
Add-ButtonHover $btnClearLog $colorLightGray

# Check for updates (async using Task.Run)
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
            $form.Invoke([Action]{ Add-Log "Already up to date (v$localVersion)" })
        }
    } catch {
        $form.Invoke([Action]{ Add-Log "Update check failed: $_" })
    }
}

# Async connect (prevent UI freeze)
$btnConnect.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        Add-Log "Select a cash register"
        return
    }

    # Don't start a second connect while one is in flight
    if ($script:conn.task -and -not $script:conn.task.IsCompleted) {
        Add-Log "Connection already in progress, please wait..."
        return
    }

    $btnConnect.Enabled = $false
    $selected = $listView.SelectedItems[0]
    $kassaIP = $selected.SubItems[1].Text
    $kassaName = $selected.Text
    $pw = $config.ssh_password
    $killGraphics = $chkKillGraphics.Checked

    Add-Log "=== Connecting to $kassaName ($kassaIP) ==="

    # Run connect in background runspace
    $script:conn.runspace = [runspacefactory]::CreateRunspace()
    $script:conn.runspace.Open()

    $script:conn.ps = [powershell]::Create()
    $script:conn.ps.Runspace = $script:conn.runspace
    $script:conn.ps.AddScript({
        param($plinkPath, $kassaIP, $kassaName, $pw, $config, $killGraphics)

        # Kill old plink
        Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500

        # Test SSH
        $test = & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "echo SSH_OK" 2>&1
        $testStr = ($test -join "`n").Trim()

        if ($testStr -notmatch "SSH_OK") {
            return @{ Success = $false; Error = "SSH_FAILED"; GraphicsKilled = $false }
        }

        # Disable graphics (optional - some FRs allow a second connection)
        $graphicsKilled = $false
        if ($killGraphics) {
            $xorgOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "pgrep Xorg | head -1" 2>&1
            $xorgStr = ($xorgOut -join "`n").Trim()
            $pidStr = ""
            if ($xorgStr -match '(\d+)') { $pidStr = $Matches[1] }
            if ($pidStr -match '^\d+$') {
                & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "sudo kill -INT $pidStr" 2>&1 | Out-Null
            }
            Start-Sleep -Seconds 1
            $graphicsKilled = $true
        }

        # Start tunnel
        Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500

        $tunnelArgs = "-batch -ssh -P $($config.ssh_port) -pw $pw -l $($config.ssh_user) -L $($config.local_port):$($config.fr_ip):$($config.fr_port) -N $kassaIP"
        $proc = Start-Process -FilePath $plinkPath -ArgumentList $tunnelArgs -PassThru -WindowStyle Hidden

        # Retry port check
        $maxRetries = $config.connection_timeout
        $portReady = $false
        for ($i = 1; $i -le $maxRetries; $i++) {
            Start-Sleep -Seconds 1
            $portCheck = netstat -ano | findstr ":$($config.local_port).*LISTEN"
            if ($portCheck) {
                $portReady = $true
                break
            }
        }

        return @{
            Success = $portReady
            PID = $proc.Id
            KassaName = $kassaName
            KassaIP = $kassaIP
            Password = $pw
            GraphicsKilled = $graphicsKilled
            Error = if ($portReady) { $null } else { "TUNNEL_FAILED" }
        }
    }).AddArgument($plinkPath).AddArgument($kassaIP).AddArgument($kassaName).AddArgument($pw).AddArgument($config).AddArgument($killGraphics)

    # Async execution
    $script:conn.task = $script:conn.ps.BeginInvoke()
    # Watchdog: never leave the button disabled forever (e.g. SSH hangs)
    $script:conn.deadline = (Get-Date).AddSeconds(60)

    # Poll for completion without blocking UI
    $script:conn.timer = New-Object System.Windows.Forms.Timer
    $script:conn.timer.Interval = 100
    $script:conn.timer.Add_Tick({
        if (-not $script:conn.task) {
            $script:conn.timer.Stop()
            $btnConnect.Enabled = $true
            return
        }

        if (-not $script:conn.task.IsCompleted) {
            # Watchdog: abort a stuck connection attempt
            if ((Get-Date) -gt $script:conn.deadline) {
                $script:conn.timer.Stop()
                Add-Log "   TIMEOUT - aborting connection attempt"
                try { $script:conn.runspace.Stop() } catch {}
                try { $script:conn.ps.Dispose() } catch {}
                try { $script:conn.runspace.Close() } catch {}
                $script:conn.task = $null
                $script:conn.ps = $null
                $script:conn.runspace = $null
                Stop-PlinkTunnels
                $btnConnect.Enabled = $true
                Write-AppLog "Connection attempt timed out"
            }
            return
        }

        $script:conn.timer.Stop()
        $result = $null
        try {
            $result = $script:conn.ps.EndInvoke($script:conn.task)
        } catch {
            Add-Log "   Error: $_"
        }
        try { $script:conn.ps.Dispose() } catch {}
        try { $script:conn.runspace.Close() } catch {}
        $script:conn.task = $null
        $script:conn.ps = $null
        $script:conn.runspace = $null

        if ($result -and $result.Success) {
            Add-Log "   SSH OK"
            if ($result.GraphicsKilled) { Add-Log "   Graphics disabled" }
            Add-Log "   === CONNECTED ==="
            $State.Connected = $true
            $State.ConnectTime = Get-Date
            $State.ConnectedKassa = $result.KassaName
            $State.ConnectedIP = $result.KassaIP
            $State.ConnectedPw = $result.Password
            $State.TunnelPID = $result.PID
            $State.GraphicsKilled = $result.GraphicsKilled
            Add-Log "   plink PID: $($result.PID)"
            # Highlight active kassa
            if ($listView.SelectedItems.Count -gt 0) {
                Set-ActiveKassa $listView.SelectedItems[0] $true
            }
        } else {
            Add-Log "   FAILED - $(if ($result) { $result.Error } else { 'UNKNOWN' })"
            Stop-PlinkTunnels
        }

        $btnConnect.Enabled = $true
        Write-AppLog "Connection attempt completed"
    })
    $script:conn.timer.Start()
})

# Disconnect button
$btnDisconnect.Add_Click({
    $ip = $State.ConnectedIP
    $pw = $State.ConnectedPw
    # Fallback: use selected kassa if state is empty
    if (-not $ip -and $listView.SelectedItems.Count -gt 0) {
        $ip = $listView.SelectedItems[0].SubItems[1].Text
        $pw = $config.ssh_password
    }
    Stop-PlinkTunnels
    Add-Log "Disconnected"
    # Restart GUI on cash register (was killed for FR tunnel)
    if ($ip -and $pw) {
        Add-Log "Restarting GUI on $ip..."
        try {
            $null = Invoke-Plink -PlinkPath $plinkPath -HostName $ip -Port $config.ssh_port -User $config.ssh_user -Password $pw -Command "systemctl restart getty@tty1" 2>&1
            Add-Log "GUI restarted"
        } catch {
            Add-Log "Failed to restart GUI: $_"
        }
    }
    $State.Connected = $false
    $State.ConnectTime = $null
    $State.ConnectedIP = ""
    $State.ConnectedPw = ""
    # Reset active kassa highlight
    foreach ($item in $listView.Items) {
        Set-ActiveKassa $item $false
    }
})

# Update button
$btnUpdate.Add_Click({
    Add-Log "Checking for updates..."
    $btnUpdate.Enabled = $false
    $task = [System.Threading.Tasks.Task]::Run([Action]{ Check-Update })
    $btnUpdate.Enabled = $true
})

$btnTestDriver.Add_Click({
    if ($testDriverPath -and (Test-Path $testDriverPath)) {
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

# FR Status button - get full FR status via SSH
$btnFrStatus.Add_Click({
    $kassaIP = $State.ConnectedIP
    $kassaPw = $State.ConnectedPw

    if (-not $State.Connected) {
        if ($listView.SelectedItems.Count -eq 0) {
            Add-Log "Select a cash register"
            return
        }
        $kassaIP = $listView.SelectedItems[0].SubItems[1].Text
        $kassaPw = $config.ssh_password
        Add-Log "Connecting to $kassaIP..."

        $test = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP "echo SSH_OK" 2>&1
        $testStr = ($test -join "`n").Trim()
        if ($testStr -notmatch "SSH_OK") {
            Add-Log "SSH error - check password/IP"
            return
        }
        Add-Log "SSH OK"
    }

    Add-Log "========================================"
    Add-Log "FR Status: $kassaIP"
    Add-Log "========================================"

    # Get InfoClient data
    $infoClient = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP "/linuxcash/cash/bin/InfoClient 2>&1" 2>&1
    $infoStr = ($infoClient -join "`n").Trim()

    if ($infoStr -and $infoStr.Length -gt 10) {
        $pairs = $infoStr -split "&"
        $parsed = @{}
        foreach ($pair in $pairs) {
            $kv = $pair -split "=", 2
            if ($kv.Count -eq 2) {
                $parsed[$kv[0]] = $kv[1]
            }
        }

        Add-Log ""
        Add-Log "--- KKM Info ---"
        if ($parsed.modelName) { Add-Log "Model: $($parsed.modelName)" }
        if ($parsed.model) { Add-Log "Model Code: $($parsed.model)" }
        if ($parsed.number) { Add-Log "Serial: $($parsed.number)" }
        if ($parsed.firmware) { Add-Log "Firmware: $($parsed.firmware)" }
        if ($parsed.ffd_version) { Add-Log "FFD Version: $($parsed.ffd_version)" }
        if ($parsed.producer) { Add-Log "Producer: $($parsed.producer)" }

        Add-Log ""
        Add-Log "--- FN Info ---"
        if ($parsed.fn) { Add-Log "FN Present: $($parsed.fn)" }
        if ($parsed.fn_number) { Add-Log "FN Number: $($parsed.fn_number)" }
        if ($parsed.fn_version) { Add-Log "FN Version: $($parsed.fn_version)" }
        if ($parsed.fn_time_end) {
            Add-Log "FN Expiry: $($parsed.fn_time_end)"
            if ($parsed.fn_days_left) {
                $days = [int]$parsed.fn_days_left
                if ($days -lt 30) {
                    Add-Log "WARNING: FN expires in $days days!"
                } else {
                    Add-Log "FN Days Left: $days"
                }
            }
        }
        if ($parsed.fn_registration_count) { Add-Log "Reg Remaining: $($parsed.fn_registration_count)" }
        if ($parsed.fn_registration_used) { Add-Log "Reg Used: $($parsed.fn_registration_used)" }

        Add-Log ""
        Add-Log "--- Documents ---"
        if ($parsed.fn_last_doc_num) { Add-Log "Last Doc #: $($parsed.fn_last_doc_num)" }
        if ($parsed.fn_last_doc_date) { Add-Log "Last Doc Date: $($parsed.fn_last_doc_date)" }
        if ($parsed.fn_not_send_doc_count) {
            $notSent = [int]$parsed.fn_not_send_doc_count
            if ($notSent -gt 0) {
                Add-Log "NOT SENT TO OFD: $notSent"
            } else {
                Add-Log "Not Sent to OFD: 0 (all sent)"
            }
        }
        if ($parsed.fn_earliest_not_send_doc_date) { Add-Log "Earliest Not Sent: $($parsed.fn_earliest_not_send_doc_date)" }

        Add-Log ""
        Add-Log "--- Status ---"
        if ($parsed.fn_connection_status) {
            $ofdStatus = $parsed.fn_connection_status
            if ($ofdStatus -eq "true") {
                Add-Log "OFD Connection: OK"
            } else {
                Add-Log "OFD Connection: NOT CONNECTED"
            }
        }
        if ($parsed.fpcountleft) {
            $shifts = [int]$parsed.fpcountleft
            if ($shifts -eq 0) {
                Add-Log "Shifts Left: 0 (FISCAL MEMORY FULL)"
            } else {
                Add-Log "Shifts Left: $shifts"
            }
        }
        if ($parsed.fn_att_flags) { Add-Log "FN Warning Flags: $($parsed.fn_att_flags)" }
        if ($parsed.ism_not_sent_count) { Add-Log "ISM Not Sent: $($parsed.ism_not_sent_count)" }
    } else {
        Add-Log "InfoClient not available, trying JSON..."
        $jsonOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP "cat /linuxcash/cash/data/info/kkm.json 2>&1" 2>&1
        $jsonStr = ($jsonOut -join "`n").Trim()

        if ($jsonStr -and $jsonStr.Length -gt 10) {
            try {
                $json = $jsonStr | ConvertFrom-Json
                Add-Log "--- KKM Info (JSON) ---"
                Add-Log "Model: $($json.modelName)"
                Add-Log "Serial: $($json.number)"
                Add-Log "FN Number: $($json.fn_number)"
                Add-Log "FN Expiry: $($json.fn_time_end)"
                Add-Log "Last Doc: $($json.fn_last_doc_num)"
                Add-Log "Not Sent: $($json.fn_not_send_doc_count)"
                Add-Log "OFD: $($json.fn_connection_status)"
                Add-Log "Shifts: $($json.fpcountleft)"
            } catch {
                Add-Log "JSON parse error: $_"
            }
        } else {
            Add-Log "Could not retrieve FR status"
        }
    }

    # Get License info
    Add-Log ""
    Add-Log "--- License ---"
    $licOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP "cat /linuxcash/cash/data/info/license.json 2>&1" 2>&1
    $licStr = ($licOut -join "`n").Trim()

    if ($licStr -and $licStr.Length -gt 10) {
        try {
            $lic = $licStr | ConvertFrom-Json
            if ($lic.key) { Add-Log "License Key: $($lic.key)" }
            if ($lic.type) { Add-Log "Type: $($lic.type)" }
            if ($lic.exp_date_str) { Add-Log "Expiry: $($lic.exp_date_str)" }
            if ($lic.time_left) { Add-Log "Time Left: $($lic.time_left) sec" }
            if ($lic.product) { Add-Log "Product: $($lic.product)" }
        } catch {
            Add-Log "License parse error"
        }
    } else {
        Add-Log "License info not available"
    }

    # Get TS PIOT license info (Artix module + FR license + ESM/ESP license term)
    Add-Log ""
    Add-Log "--- TS PIOT ---"
    $piotOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP $piotCmd 2>&1
    $piot = Get-PiotInfo -Output $piotOut

    if ($piot.ArtixModule -eq "0") {
        Add-Log "Artix tspiotesm: NO (needs reissued license for the cash register key)"
    } elseif ($piot.ArtixModule) {
        Add-Log "Artix tspiotesm: YES"
    } else {
        Add-Log "Artix tspiotesm: unknown"
    }

    if ($piot.KktError55 -and [int]$piot.KktError55 -gt 0) {
        Add-Log "KKT error=55: $($piot.KktError55) (FR has no TS PIOT license - contact service center)"
    } else {
        Add-Log "KKT error=55: none"
    }

    if ($piot.EsmService -or $piot.MarkVerify) {
        Add-Log "esmservice: $($piot.EsmService)  markVerifyCrptService: $($piot.MarkVerify)"
    }

    if ($piot.ValidTill) {
        if ($piot.IsActive) { Add-Log "ESM license is_active: $($piot.IsActive)" }
        $syncNote = if ($piot.SyncedAt) { " [last sync: $($piot.SyncedAt)]" } else { "" }
        Add-Log "TS PIOT license active till: $($piot.ValidTill) ($($piot.DaysLeft) days left)$syncNote"
        if ($piot.DaysLeft -and [int]$piot.DaysLeft -lt 60) {
            Add-Log "WARNING: TS PIOT license expires soon!"
        }
    } else {
        Add-Log "TS PIOT license term: not found (ESM/TS PIOT is not used on this cash register)"
    }

    # Get Version info
    Add-Log ""
    Add-Log "--- Version ---"
    $verOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP "cat /linuxcash/cash/data/info/version.json 2>&1" 2>&1
    $verStr = ($verOut -join "`n").Trim()

    if ($verStr -and $verStr.Length -gt 5) {
        try {
            $ver = $verStr | ConvertFrom-Json
            if ($ver.Count -ge 1) { Add-Log "Artix Version: $($ver[0])" }
            if ($ver.Count -ge 2) { Add-Log "Build Date: $($ver[1])" }
            if ($ver.Count -ge 3) { Add-Log "Revision: $($ver[2])" }
        } catch {
            Add-Log "Version parse error"
        }
    } else {
        Add-Log "Version info not available"
    }

    # Check RNDIS status
    Add-Log ""
    Add-Log "--- RNDIS/OFD ---"
    $rndisOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $kassaPw -l $config.ssh_user $kassaIP "tail -3 /linuxcash/logs/current/rndis.log 2>&1" 2>&1
    $rndisStr = ($rndisOut -join "`n").Trim()
    if ($rndisStr -and $rndisStr.Length -gt 5) {
        foreach ($line in $rndisStr.Split("`n")) {
            if ($line -match "RNDIS|interface|Check") {
                Add-Log $line.Trim()
            }
        }
    } else {
        Add-Log "RNDIS log not available"
    }

    Add-Log ""
    Add-Log "========================================"
    Add-Log "End FR Status"
    Add-Log "========================================"
})

# KKT monitor button - collect data from all cash registers into kkt_monitor*.html
$btnMonitor.Add_Click({
    $monitorFile = Get-MonitorFile -Folder $scriptDir
    if (-not $monitorFile) {
        Add-Log "kkt_monitor*.html not found in $scriptDir"
        return
    }

    $btnMonitor.Enabled = $false
    Add-Log "========================================"
    Add-Log "KKT monitor: $(Split-Path $monitorFile -Leaf)"
    Add-Log "========================================"

    $backup = "$monitorFile.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    try {
        Copy-Item $monitorFile $backup -Force
        Add-Log "Backup: $(Split-Path $backup -Leaf)"
    } catch {
        Add-Log "Backup error: $_"
    }

    # Run in the background: each kassa needs the GUI stopped and a tunnel,
    # which would freeze the UI for minutes if run on the main thread.
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    $cmd = $ps.AddScript({
        param($MonitorFile, $PlinkPath, $Config, $MonitorCmd, $KillGuiCmd, $GuiStateCmd, $ScriptDir, $LogBox)
        . "$ScriptDir\lib\ssh.ps1"
        . "$ScriptDir\lib\logging.ps1"
        . "$ScriptDir\lib\monitor.ps1"
        function Add-Log { param([string]$msg) Add-UILog -LogBox $LogBox -msg $msg }
        try {
            $res = Update-KktMonitor -MonitorFile $MonitorFile -PlinkPath $PlinkPath -Config $Config `
                -MonitorCmd $MonitorCmd -KillGuiCmd $KillGuiCmd -GuiStateCmd $GuiStateCmd
            if ($res) {
                Add-Log "----------------------------------------"
                Add-Log "Total: $($res.Total)  updated: $($res.Updated)  added: $($res.Added)  failed: $($res.Failed)"
                Add-Log "Feature licenses read: $($res.Licenses)  no PIOT data: $($res.NoData)  expires in <60 days: $($res.ExpiresSoon)"
                Add-Log "Saved: $($res.File)"
                Add-Log "In the browser press 'Reset DB' to drop cached IndexedDB data"
            }
        } catch {
            Add-Log "Update error: $_"
        }
        Add-Log "========================================"
    })
    $cmd.AddArgument($monitorFile) | Out-Null
    $cmd.AddArgument($plinkPath)   | Out-Null
    $cmd.AddArgument($config)      | Out-Null
    $cmd.AddArgument($monitorCmd)  | Out-Null
    $cmd.AddArgument($killGuiCmd)  | Out-Null
    $cmd.AddArgument($guiStateCmd) | Out-Null
    $cmd.AddArgument($scriptDir)   | Out-Null
    $cmd.AddArgument($logBox)      | Out-Null

    $task = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 300
    $timer.Add_Tick({
        if ($task.IsCompleted) {
            $timer.Stop()
            try { $ps.EndInvoke($task) } catch {}
            $ps.Dispose()
            $runspace.Close()
            $btnMonitor.Enabled = $true
            Write-AppLog "KKT monitor update finished"
        }
    })
    $timer.Start()
})

# Remote command execute buttons
$btnExecCmd.Add_Click({ Invoke-SelectedCommand $cmbCommands $btnExecCmd })
$btnExecTerminal.Add_Click({ Invoke-SelectedCommand $cmbTerminal $btnExecTerminal })
$btnExecEsm.Add_Click({ Invoke-SelectedCommand $cmbEsm $btnExecEsm })

# Startup
Rotate-Logs
Add-Log "Application started v$appVersion"
Add-Log "Cash registers: $($config.kassas.Count)"

# Check for updates on startup (async using Task)
$null = [System.Threading.Tasks.Task]::Run([Action]{ Check-Update })

$form.ShowDialog() | Out-Null
