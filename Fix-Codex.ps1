# Command-line interface for Windows PowerShell / pwsh.
[CmdletBinding()]
param(
    [ValidateSet('Scan', 'Repair', 'Restore')]
    [string]$Action = 'Scan',
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'src\CodexFixer.Core.ps1')
try {
    $context = Get-LLContext
    switch ($Action) {
        'Scan' {
            $plan = Get-LLPlan -Context $context
            Write-Host "Codex 版本：$($context.CodexVersion)"
            if ($plan.Runtime) { Write-Host "Node 运行时：$($plan.Runtime.Id)" }
            else { Write-Warning '未发现完整的正式 Node 运行时' }
            foreach ($part in @($plan.ManifestPlans)) {
                Write-Host "`n$($part.Source.Name)：可修复 $($part.Changes) 项"
                foreach ($issue in $part.Issues) { Write-Host " - $issue" }
            }
            foreach ($warning in $plan.Warnings) { Write-Warning $warning }
            Write-Host "`n合计可修复字段：$($plan.Changes)"
        }
        'Repair' {
            if (-not $Yes) { throw '为保护数据，修复需要明确指定 -Yes。请先退出 Codex 和 Chrome。' }
            $result = Invoke-LLRepair -Context $context
            Write-Host $result.Message
            if ($result.BackupFolder) { Write-Host "备份目录：$($result.BackupFolder)" }
        }
        'Restore' {
            if (-not $Yes) { throw '为保护数据，恢复需要明确指定 -Yes。请先退出 Codex 和 Chrome。' }
            $result = Invoke-LLRestore -Context $context
            Write-Host "恢复了 $($result.Restored) 个清单。备份：$($result.BackupFolder)"
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
