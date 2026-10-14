# Codex Extension Fixer — graphical interface (Windows PowerShell 5.1+)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\CodexFixer.Core.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Codex Extension Fixer  |  浏览器扩展修复工具'
$form.Width = 810
$form.Height = 590
$form.MinimumSize = New-Object System.Drawing.Size(760, 550)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(19, 24, 35)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Codex Extension Fixer'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 19, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(234, 240, 255)
$title.SetBounds(28, 22, 710, 44)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = '修复更新后 Chrome 扩展 nodePath / 运行时 / resourcesPath 失效问题'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(166, 182, 205)
$subtitle.SetBounds(30, 72, 725, 30)
$form.Controls.Add($subtitle)

$status = New-Object System.Windows.Forms.Label
$status.Text = '状态：尚未检测'
$status.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
$status.ForeColor = [System.Drawing.Color]::FromArgb(108, 190, 255)
$status.SetBounds(30, 118, 725, 35)
$form.Controls.Add($status)

$info = New-Object System.Windows.Forms.Label
$info.Text = '当前版本：未知    |    有效 Node 运行时：未知'
$info.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 225)
$info.SetBounds(30, 155, 725, 30)
$form.Controls.Add($info)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.BackColor = [System.Drawing.Color]::FromArgb(27, 34, 48)
$log.ForeColor = [System.Drawing.Color]::FromArgb(221, 232, 243)
$log.BorderStyle = 'FixedSingle'
$log.Font = New-Object System.Drawing.Font('Consolas', 10)
$log.SetBounds(30, 200, 735, 255)
$log.Anchor = 'Top,Left,Right,Bottom'
$form.Controls.Add($log)

$note = New-Object System.Windows.Forms.Label
$note.Text = '默认只读扫描；修复前创建备份。不会删除对话、插件、MCP 或登录数据。修复/恢复前请退出 Chrome 和 Codex。'
$note.ForeColor = [System.Drawing.Color]::FromArgb(155, 173, 196)
$note.SetBounds(30, 466, 735, 43)
$note.Anchor = 'Left,Right,Bottom'
$form.Controls.Add($note)

function New-LLButton([string]$label, [int]$x, [int]$width, [System.Drawing.Color]$color) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $label
    $btn.SetBounds($x, 516, $width, 35)
    $btn.Anchor = 'Left,Bottom'
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $color
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Cursor = 'Hand'
    $form.Controls.Add($btn)
    return $btn
}
$scan = New-LLButton '检测问题' 30 135 ([System.Drawing.Color]::FromArgb(55,105,195))
$repair = New-LLButton '备份并修复' 178 145 ([System.Drawing.Color]::FromArgb(32,134,106))
$restore = New-LLButton '恢复上次备份' 336 152 ([System.Drawing.Color]::FromArgb(115,80,158))
$open = New-LLButton '打开备份目录' 501 145 ([System.Drawing.Color]::FromArgb(66,83,107))

$script:context = $null
$script:lastPlan = $null
function Update-LLScan {
    $log.Clear()
    $status.Text = '状态：检测中...'
    $form.Refresh()
    try {
        $script:context = Get-LLContext
        $script:lastPlan = Get-LLPlan -Context $script:context
        $node = if ($null -eq $script:lastPlan.Runtime) { '未找到完整运行时' } else { $script:lastPlan.Runtime.Id }
        $info.Text = "当前版本：$($script:context.CodexVersion)    |    有效 Node 运行时：$node"
        foreach ($part in @($script:lastPlan.ManifestPlans)) {
            $log.AppendText("[$($part.Source.Name)]  可修复字段：$($part.Changes)`r`n")
            foreach ($issue in @($part.Issues)) { $log.AppendText("  - $issue`r`n") }
            if ($part.Issues.Count -eq 0) { $log.AppendText("  未发现已知异常`r`n") }
            $log.AppendText("`r`n")
        }
        foreach ($warning in @($script:lastPlan.Warnings)) { $log.AppendText("[提醒] $warning`r`n") }
        if ($script:lastPlan.Changes -gt 0) {
            $status.Text = "状态：发现 $($script:lastPlan.Changes) 处可修复配置"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(245,190,100)
        } else {
            $status.Text = '状态：未发现可自动修复的路径'
            $status.ForeColor = [System.Drawing.Color]::FromArgb(99,211,160)
        }
        $repair.Enabled = ($script:lastPlan.Changes -gt 0)
    } catch {
        $status.Text = '状态：检测失败'
        $status.ForeColor = [System.Drawing.Color]::FromArgb(251,123,133)
        $log.AppendText("错误：$($_.Exception.Message)`r`n")
        $repair.Enabled = $false
    }
    $restore.Enabled = ($null -ne $script:context -and @(Get-LLBackups -Context $script:context).Count -gt 0)
}

$scan.Add_Click({ Update-LLScan })
$repair.Add_Click({
    if ($null -eq $script:context) { Update-LLScan; return }
    $msg = '即将修复检测出的失效路径，并将两个清单的原始内容备份到本机。请先正常退出 Chrome 与 Codex。是否继续？'
    if ([System.Windows.Forms.MessageBox]::Show($msg, '确认修复', 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        $result = Invoke-LLRepair -Context $script:context
        [System.Windows.Forms.MessageBox]::Show("$($result.Message)`r`n备份：$($result.BackupFolder)`r`n`r`n请重新打开 Codex 和 Chrome 验证。", '修复完成', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '修复失败', 'OK', 'Error') | Out-Null
    }
    Update-LLScan
})
$restore.Add_Click({
    if ($null -eq $script:context) { Update-LLScan; return }
    $backups = @(Get-LLBackups -Context $script:context)
    if ($backups.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('没有可恢复的备份。', '提示') | Out-Null
        return
    }
    $msg = "将从以下备份恢复原始清单：`r`n$($backups[0].Folder)`r`n`r`n仅当文件自修复后未被 Codex 更新程序改变时才允许恢复。继续？"
    if ([System.Windows.Forms.MessageBox]::Show($msg, '确认恢复', 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        $result = Invoke-LLRestore -Context $script:context
        [System.Windows.Forms.MessageBox]::Show("已恢复 $($result.Restored) 份清单。请重启 Chrome 和 Codex。", '恢复完成', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '无法恢复', 'OK', 'Warning') | Out-Null
    }
    Update-LLScan
})
$open.Add_Click({
    try {
        if ($null -eq $script:context) { $script:context = Get-LLContext }
        if (-not (Test-Path -LiteralPath $script:context.BackupRoot)) {
            $null = New-Item -ItemType Directory -Path $script:context.BackupRoot -Force
        }
        Start-Process explorer.exe -ArgumentList ('"' + $script:context.BackupRoot + '"')
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '无法打开备份目录') | Out-Null
    }
})
$form.Add_Shown({ Update-LLScan })
[void]$form.ShowDialog()
