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
}

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
$form.Size = New-Object System.Drawing.Size(500, 660)
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

# POScenter group (all buttons except Update)
$groupPoscenter = New-Object System.Windows.Forms.GroupBox
$groupPoscenter.Text = "POScenter"
$groupPoscenter.Location = New-Object System.Drawing.Point(15, 385)
$groupPoscenter.Size = New-Object System.Drawing.Size(455, 55)
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

# Log area
$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = [char]0x0416 + [char]0x0443 + [char]0x0440 + [char]0x043D + [char]0x0430 + [char]0x043B
$logLabel.Location = New-Object System.Drawing.Point(15, 450)
$logLabel.AutoSize = $true
$logLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($logLabel)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = [char]0x041E + [char]0x0431 + [char]0x043D + [char]0x043E + [char]0x0432 + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnUpdate.Location = New-Object System.Drawing.Point(340, 448)
$btnUpdate.Size = New-Object System.Drawing.Size(75, 20)
$btnUpdate.BackColor = $colorLightGray
$btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.FlatStyle = "Flat"
$btnUpdate.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$btnUpdate.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnUpdate)

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = [char]0x041E + [char]0x0447 + [char]0x0438 + [char]0x0441 + [char]0x0442 + [char]0x0438 + [char]0x0442 + [char]0x044C
$btnClearLog.Location = New-Object System.Drawing.Point(420, 448)
$btnClearLog.Size = New-Object System.Drawing.Size(50, 20)
$btnClearLog.BackColor = $colorLightGray
$btnClearLog.ForeColor = [System.Drawing.Color]::White
$btnClearLog.FlatStyle = "Flat"
$btnClearLog.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$btnClearLog.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnClearLog)

$btnClearLog.Add_Click({ $logBox.Clear() })

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, 472)
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
Add-ButtonHover $btnUpdate $colorLightGray
Add-ButtonHover $btnExecCmd $colorPrimary
Add-ButtonHover $btnExecTerminal $colorSuccess
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

    $btnConnect.Enabled = $false
    $selected = $listView.SelectedItems[0]
    $kassaIP = $selected.SubItems[1].Text
    $kassaName = $selected.Text
    $pw = $config.ssh_password

    Add-Log "=== Connecting to $kassaName ($kassaIP) ==="

    # Run connect in background runspace
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript({
        param($plinkPath, $kassaIP, $kassaName, $pw, $config)

        # Kill old plink
        Get-Process plink -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500

        # Test SSH
        $test = & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "echo SSH_OK" 2>&1
        $testStr = ($test -join "`n").Trim()

        if ($testStr -notmatch "SSH_OK") {
            return @{ Success = $false; Error = "SSH_FAILED" }
        }

        # Disable graphics
        $xorgOut = & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "pgrep Xorg | head -1" 2>&1
        $xorgStr = ($xorgOut -join "`n").Trim()
        $pidStr = ""
        if ($xorgStr -match '(\d+)') { $pidStr = $Matches[1] }
        if ($pidStr -match '^\d+$') {
            & $plinkPath -batch -ssh -P $config.ssh_port -pw $pw -l $config.ssh_user $kassaIP "sudo kill -INT $pidStr" 2>&1 | Out-Null
        }

        Start-Sleep -Seconds 1

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
            Error = if ($portReady) { $null } else { "TUNNEL_FAILED" }
        }
    }).AddArgument($plinkPath).AddArgument($kassaIP).AddArgument($kassaName).AddArgument($pw).AddArgument($config)

    # Async execution
    $task = $ps.BeginInvoke()

    # Poll for completion without blocking UI
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100
    $timer.Add_Tick({
        if ($task.IsCompleted) {
            $timer.Stop()
            $result = $ps.EndInvoke($task)
            $ps.Dispose()
            $runspace.Close()

            if ($result.Success) {
                Add-Log "   SSH OK"
                Add-Log "   Graphics disabled"
                Add-Log "   === CONNECTED ==="
                $State.Connected = $true
                $State.ConnectTime = Get-Date
                $State.ConnectedKassa = $result.KassaName
                $State.ConnectedIP = $result.KassaIP
                $State.ConnectedPw = $result.Password
                $State.TunnelPID = $result.PID
                Add-Log "   plink PID: $($result.PID)"
                # Highlight active kassa
                if ($listView.SelectedItems.Count -gt 0) {
                    Set-ActiveKassa $listView.SelectedItems[0] $true
                }
            } else {
                Add-Log "   FAILED - $($result.Error)"
                Stop-PlinkTunnels
            }

            $btnConnect.Enabled = $true
            Write-AppLog "Connection attempt completed"
        }
    })
    $timer.Start()
})

# Disconnect button
$btnDisconnect.Add_Click({
    Stop-PlinkTunnels
    Add-Log "Disconnected"
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

# Remote command execute buttons
$btnExecCmd.Add_Click({ Invoke-SelectedCommand $cmbCommands $btnExecCmd })
$btnExecTerminal.Add_Click({ Invoke-SelectedCommand $cmbTerminal $btnExecTerminal })

# Startup
Rotate-Logs
Add-Log "Application started v$appVersion"
Add-Log "Cash registers: $($config.kassas.Count)"

# Check for updates on startup (async using Task)
$null = [System.Threading.Tasks.Task]::Run([Action]{ Check-Update })

$form.ShowDialog() | Out-Null
