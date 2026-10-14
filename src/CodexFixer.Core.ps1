# Copyright (c) 2026 Codex Extension Fixer contributors. MIT License.
# Windows PowerShell 5.1+; intentionally avoids downloading tools or modifying Codex user data.

function Get-LLContext {
    $pkg = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop |
        Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($null -eq $pkg) { throw '未检测到 OpenAI.Codex。请先安装 Codex Windows 桌面版。' }
    $resources = Join-Path $pkg.InstallLocation 'app\resources'
    if (-not (Test-Path -LiteralPath $resources -PathType Container)) {
        throw "当前 Codex 资源目录不存在：$resources"
    }
    [pscustomobject]@{
        CodexVersion = [string]$pkg.Version
        RuntimeRoot  = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
        ResourcesPath = $resources
        BackupRoot   = Join-Path $env:LOCALAPPDATA 'Codex-Extension-Fixer\Backups'
        Manifests    = @(
            [pscustomobject]@{ Id = 'appdata'; Name = 'AppData 清单'; Path = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\chrome-native-hosts-v2.json' }
            [pscustomobject]@{ Id = 'profile'; Name = '.codex 清单'; Path = Join-Path $env:USERPROFILE '.codex\chrome-native-hosts-v2.json' }
        )
    }
}

function Get-LLRuntime {
    param([Parameter(Mandatory)] $Context)
    if (-not (Test-Path -LiteralPath $Context.RuntimeRoot -PathType Container)) { return $null }
    $dirs = @(Get-ChildItem -LiteralPath $Context.RuntimeRoot -Directory -ErrorAction Stop |
        Where-Object { $_.Name -cmatch '^[0-9a-f]{16}$' } |
        Sort-Object -Property LastWriteTime -Descending)
    foreach ($dir in $dirs) {
        $bin = Join-Path $dir.FullName 'bin'
        $node = Join-Path $bin 'node.exe'
        $repl = Join-Path $bin 'node_repl.exe'
        $modules = Join-Path $bin 'node_modules'
        if ((Test-Path -LiteralPath $node -PathType Leaf) -and
            (Test-Path -LiteralPath $repl -PathType Leaf) -and
            (Test-Path -LiteralPath $modules -PathType Container)) {
            return [pscustomobject]@{ Id = $dir.Name; NodePath = $node; NodeReplPath = $repl; NodeModuleDirs = $modules }
        }
    }
    return $null
}

function Test-LLStagingPath {
    param($Value)
    if ($Value -isnot [string]) { return $false }
    return ($Value -match '[\\/]runtimes[\\/]cua_node[\\/]\.staging-')
}

function Get-LLFileHash {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Get-LLPlan {
    param([Parameter(Mandatory)] $Context)
    $runtime = Get-LLRuntime -Context $Context
    $manifestPlans = @()
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $total = 0

    foreach ($source in $Context.Manifests) {
        if (-not (Test-Path -LiteralPath $source.Path -PathType Leaf)) {
            $warnings.Add("$($source.Name)：清单不存在（跳过）")
            continue
        }
        $obj = $null
        try {
            $obj = Get-Content -LiteralPath $source.Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $warnings.Add("$($source.Name)：不是有效 JSON，已跳过。$($_.Exception.Message)")
            continue
        }
        if ($null -eq $obj -or $null -eq $obj.PSObject.Properties['entries'] -or $null -eq $obj.entries) {
            $warnings.Add("$($source.Name)：未识别 entries 结构，已跳过以保护数据。")
            continue
        }
        $issues = New-Object 'System.Collections.Generic.List[string]'
        $changed = 0
        foreach ($entry in @($obj.entries)) {
            if ($null -eq $entry) { continue }
            $p = $entry
            if ($null -ne $entry.PSObject.Properties['paths'] -and $null -ne $entry.paths) { $p = $entry.paths }
            if ($null -eq $p) { continue }
            $names = @($p.PSObject.Properties.Name)
            # Ignore non-browser entries to avoid rewriting unrelated host or plugin configurations.
            $browserEntry = (($names -contains 'extensionHostPath') -or
                             ($names -contains 'browserClientPath') -or
                             ($names -contains 'browserServicePath'))
            if (-not $browserEntry) { continue }

            $runtimeMap = @{}
            if ($null -ne $runtime) {
                $runtimeMap = @{
                    nodePath = $runtime.NodePath
                    nodeReplPath = $runtime.NodeReplPath
                    nodeModuleDirs = $runtime.NodeModuleDirs
                }
            }
            foreach ($key in @('nodePath', 'nodeReplPath', 'nodeModuleDirs')) {
                $prop = $p.PSObject.Properties[$key]
                if ($null -eq $prop) {
                    $issues.Add("缺少 $key 字段")
                    if ($null -ne $runtime) {
                        $p | Add-Member -MemberType NoteProperty -Name $key -Value $runtimeMap[$key]
                        $changed++
                    }
                    continue
                }
                $value = $prop.Value
                if ($key -eq 'nodeModuleDirs' -and $value -is [array]) {
                    $updated = @()
                    $fixed = $false
                    foreach ($item in $value) {
                        if ($item -is [string] -and
                            (-not (Test-Path -LiteralPath $item)) -and
                            ($item -match '[\\/]runtimes[\\/]cua_node[\\/]') -and
                            $null -ne $runtime) {
                            $updated += $runtime.NodeModuleDirs
                            $fixed = $true
                            $issues.Add('nodeModuleDirs 中存在失效的 Codex 运行时目录')
                        } elseif ((Test-LLStagingPath $item) -and $null -ne $runtime) {
                            $updated += $runtime.NodeModuleDirs
                            $fixed = $true
                            $issues.Add('nodeModuleDirs 使用临时 staging 目录')
                        } else {
                            $updated += $item
                            if ($item -is [string] -and -not (Test-Path -LiteralPath $item)) {
                                $issues.Add('nodeModuleDirs 中有其他失效目录（未自动修改）')
                            }
                        }
                    }
                    if ($fixed) { $prop.Value = $updated; $changed++ }
                    continue
                }
                $invalid = ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value))
                if (-not $invalid) { $invalid = (-not (Test-Path -LiteralPath $value)) -or (Test-LLStagingPath $value) }
                if ($invalid) {
                    $issues.Add("$key 所指路径不存在或不稳定")
                    if ($null -ne $runtime -and $value -is [string] -and
                        ($value -match '[\\/]runtimes[\\/]cua_node[\\/]' -or [string]::IsNullOrWhiteSpace($value))) {
                        $prop.Value = $runtimeMap[$key]
                        $changed++
                    }
                }
            }
            $rp = $p.PSObject.Properties['resourcesPath']
            if ($null -eq $rp) {
                $issues.Add('缺少 resourcesPath 字段')
                if ($null -ne $runtime) {
                    $p | Add-Member -MemberType NoteProperty -Name 'resourcesPath' -Value $Context.ResourcesPath
                    $changed++
                }
            } elseif ($rp.Value -ne $Context.ResourcesPath) {
                $issues.Add('resourcesPath 不是当前 Codex 版本')
                if ($null -ne $runtime) {
                    $rp.Value = $Context.ResourcesPath
                    $changed++
                }
            }
        }
        $total += $changed
        $manifestPlans += [pscustomobject]@{
            Source = $source
            OriginalHash = Get-LLFileHash -Path $source.Path
            OriginalObject = $obj
            Changes = $changed
            Issues = @($issues.ToArray())
        }
    }
    if ($null -eq $runtime) {
        $warnings.Add('没有发现完整的正式 Node 运行时；Node 路径不会被自动修改。请先修复 Codex 运行时安装。')
    }
    [pscustomobject]@{
        Context = $Context
        Runtime = $runtime
        ManifestPlans = $manifestPlans
        Changes = $total
        Warnings = @($warnings.ToArray())
    }
}

function Write-LLJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 100 -Compress:$false
    $null = ConvertFrom-Json -InputObject $json -ErrorAction Stop
    $enc = New-Object System.Text.UTF8Encoding($false)
    $temp = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [System.IO.File]::WriteAllText($temp, $json, $enc)
        # All files being patched must already exist: File.Replace provides atomic replacement.
        [System.IO.File]::Replace($temp, $Path, $null)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Save-LLMetadata {
    param([string]$Folder, $Data)
    $metadata = Join-Path $Folder 'backup-info.json'
    $json = ConvertTo-Json -InputObject $Data -Depth 20
    [System.IO.File]::WriteAllText($metadata, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-LLRepair {
    param([Parameter(Mandatory)]$Context)
    $plan = Get-LLPlan -Context $Context
    if ($plan.Changes -eq 0) { return [pscustomobject]@{ Changes = 0; BackupFolder = $null; Message = '未发现可自动修复的字段。' } }
    $toPatch = @($plan.ManifestPlans | Where-Object { $_.Changes -gt 0 })
    # Protect against a running updater changing files between scan and patch.
    foreach ($part in $toPatch) {
        if ((Get-LLFileHash -Path $part.Source.Path) -ne $part.OriginalHash) {
            throw "$($part.Source.Name) 在扫描后已被其他程序修改，请重新扫描。"
        }
    }
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
    $folder = Join-Path $Context.BackupRoot $id
    $null = New-Item -ItemType Directory -Path $folder -Force
    $entries = @()
    foreach ($part in $toPatch) {
        $filename = "$($part.Source.Id).json"
        Copy-Item -LiteralPath $part.Source.Path -Destination (Join-Path $folder $filename) -ErrorAction Stop
        $entries += [pscustomobject]@{
            FileId = $part.Source.Id; SourcePath = $part.Source.Path; BackupFile = $filename
            BeforeHash = $part.OriginalHash; AfterHash = $null; Modified = $false
        }
    }
    $meta = [pscustomobject]@{ Tool = 'Codex Extension Fixer'; Schema = 1; CreatedAt = (Get-Date).ToString('o'); Status = 'Pending'; Files = $entries }
    Save-LLMetadata -Folder $folder -Data $meta
    try {
        foreach ($part in $toPatch) {
            $rec = @($meta.Files | Where-Object { $_.FileId -eq $part.Source.Id })[0]
            if ((Get-LLFileHash -Path $part.Source.Path) -ne $part.OriginalHash) {
                throw "$($part.Source.Name) 在修复过程中被其他程序更改，操作已中断。"
            }
            Write-LLJson -Path $part.Source.Path -Object $part.OriginalObject
            $rec.AfterHash = Get-LLFileHash -Path $part.Source.Path
            $rec.Modified = $true
            Save-LLMetadata -Folder $folder -Data $meta
        }
        $meta.Status = 'Complete'
        Save-LLMetadata -Folder $folder -Data $meta
    } catch {
        $cause = $_.Exception.Message
        foreach ($rec in @($meta.Files | Where-Object { $_.Modified })) {
            try {
                if ((Get-LLFileHash -Path $rec.SourcePath) -eq $rec.AfterHash) {
                    $tmp = "$($rec.SourcePath).restore-$([guid]::NewGuid().ToString('N'))"
                    Copy-Item -LiteralPath (Join-Path $folder $rec.BackupFile) -Destination $tmp -ErrorAction Stop
                    [System.IO.File]::Replace($tmp, $rec.SourcePath, $null)
                }
            } catch { Write-Warning "自动回滚失败，请使用备份目录：$folder" }
        }
        $meta.Status = 'Failed'
        Save-LLMetadata -Folder $folder -Data $meta
        throw "修复未完成：$cause。备份保存在 $folder"
    }
    [pscustomobject]@{ Changes = $plan.Changes; BackupFolder = $folder; Message = "已修复 $($plan.Changes) 个字段。" }
}

function Get-LLBackups {
    param([Parameter(Mandatory)]$Context)
    if (-not (Test-Path -LiteralPath $Context.BackupRoot -PathType Container)) { return @() }
    $all = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $Context.BackupRoot -Directory | Sort-Object Name -Descending)) {
        $file = Join-Path $dir.FullName 'backup-info.json'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try {
            $meta = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($meta.Tool -eq 'Codex Extension Fixer' -and $meta.Schema -eq 1 -and $meta.Status -eq 'Complete') {
                $all += [pscustomobject]@{ Folder = $dir.FullName; Info = $meta }
            }
        } catch { continue }
    }
    return $all
}

function Invoke-LLRestore {
    param([Parameter(Mandatory)]$Context, [string]$BackupFolder)
    $backups = @(Get-LLBackups -Context $Context)
    if ($backups.Count -eq 0) { throw '没有找到可恢复的完整备份。' }
    $selected = $null
    if ([string]::IsNullOrWhiteSpace($BackupFolder)) { $selected = $backups[0] }
    else { $selected = @($backups | Where-Object { $_.Folder -eq $BackupFolder } | Select-Object -First 1)[0] }
    if ($null -eq $selected) { throw '指定的备份不存在或不是完整备份。' }
    $allowed = @($Context.Manifests | ForEach-Object { $_.Path })
    foreach ($rec in @($selected.Info.Files)) {
        if ($allowed -notcontains $rec.SourcePath) { throw '备份中的目标路径与当前用户不匹配，已拒绝恢复。' }
        $original = Join-Path $selected.Folder $rec.BackupFile
        if (-not (Test-Path -LiteralPath $original -PathType Leaf)) { throw '备份文件丢失，已取消恢复。' }
        if ((Get-LLFileHash -Path $original) -ne $rec.BeforeHash) { throw '备份校验失败，已取消恢复。' }
        if (-not (Test-Path -LiteralPath $rec.SourcePath -PathType Leaf)) { throw '当前清单文件不存在，已取消恢复。' }
        if ((Get-LLFileHash -Path $rec.SourcePath) -ne $rec.AfterHash) {
            throw '检测到 Codex 更新或其他程序已更改配置；为避免覆盖新配置，已拒绝自动恢复。'
        }
    }
    # Keep a separate safety copy of the patched version before restoring.
    foreach ($rec in @($selected.Info.Files)) {
        $safety = Join-Path $selected.Folder ("pre-restore-$($rec.FileId).json")
        Copy-Item -LiteralPath $rec.SourcePath -Destination $safety -ErrorAction Stop
    }
    foreach ($rec in @($selected.Info.Files)) {
        $tmp = "$($rec.SourcePath).restore-$([guid]::NewGuid().ToString('N'))"
        try {
            Copy-Item -LiteralPath (Join-Path $selected.Folder $rec.BackupFile) -Destination $tmp -ErrorAction Stop
            [System.IO.File]::Replace($tmp, $rec.SourcePath, $null)
        } finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
    $selected.Info.Status = 'Restored'
    Save-LLMetadata -Folder $selected.Folder -Data $selected.Info
    [pscustomobject]@{ Restored = @($selected.Info.Files).Count; BackupFolder = $selected.Folder }
}
