# Integration tests using isolated temp fixtures; never touch the real Codex installation.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\CodexFixer.Core.ps1')

function Assert-LL([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "TEST FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('CodexExtensionFixerTest-' + [guid]::NewGuid().ToString('N'))
try {
    $runtimeRoot = Join-Path $root 'OpenAI\Codex\runtimes\cua_node'
    $goodBin = Join-Path $runtimeRoot 'a9ba6825a525118c\bin'
    $stageBin = Join-Path $runtimeRoot '.staging-should-never-be-used\bin'
    $resources = Join-Path $root 'WindowsApps\OpenAI.Codex_current\app\resources'
    foreach ($dir in @($goodBin, (Join-Path $goodBin 'node_modules'), $stageBin, (Join-Path $stageBin 'node_modules'), $resources)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    foreach ($bin in @($goodBin, $stageBin)) {
        Set-Content -LiteralPath (Join-Path $bin 'node.exe') -Value 'test' -Encoding Ascii
        Set-Content -LiteralPath (Join-Path $bin 'node_repl.exe') -Value 'test' -Encoding Ascii
    }
    $legacyBin = Join-Path $runtimeRoot '3dd31cfff853001c\bin'
    $firstManifest = Join-Path $root 'appdata\chrome-native-hosts-v2.json'
    $secondManifest = Join-Path $root 'profile\chrome-native-hosts-v2.json'
    $context = [pscustomobject]@{
        CodexVersion = '26.1007.9446.0'
        RuntimeRoot = $runtimeRoot
        ResourcesPath = $resources
        BackupRoot = Join-Path $root 'backups'
        Manifests = @(
            [pscustomobject]@{ Id='appdata'; Name='AppData'; Path=$firstManifest }
            [pscustomobject]@{ Id='profile'; Name='Profile'; Path=$secondManifest }
        )
    }
    $manifestText = [pscustomobject]@{
        entries = @(
            [pscustomobject]@{
                id = 'chrome'; paths = [pscustomobject]@{
                    nodePath = Join-Path $legacyBin 'node.exe'
                    nodeReplPath = Join-Path $legacyBin 'node_repl.exe'
                    nodeModuleDirs = @(Join-Path $legacyBin 'node_modules')
                    resourcesPath = Join-Path $root 'obsolete\app\resources'
                    extensionHostPath = Join-Path $root 'plugin\extension-host.exe'
                    customField = 'DO_NOT_TOUCH'
                }
            },
            [pscustomobject]@{ id = 'unrelated'; paths = [pscustomobject]@{nodePath='leave-as-is'} }
        )
    } | ConvertTo-Json -Depth 20
    foreach ($path in @($firstManifest, $secondManifest)) {
        $null = New-Item -ItemType Directory -Path (Split-Path $path) -Force
        [System.IO.File]::WriteAllText($path, $manifestText)
    }
    $before1 = Get-LLFileHash $firstManifest
    $before2 = Get-LLFileHash $secondManifest
    $plan = Get-LLPlan -Context $context
    Assert-LL ($plan.Runtime.Id -eq 'a9ba6825a525118c') 'uses stable runtime, not staging'
    Assert-LL ($plan.Changes -eq 8) 'detects 4 broken fields in each manifest'
    Assert-LL (((Get-LLFileHash $firstManifest) -eq $before1) -and ((Get-LLFileHash $secondManifest) -eq $before2)) 'scan does not modify files'
    $result = Invoke-LLRepair -Context $context
    Assert-LL ($result.Changes -eq 8) 'repairs both manifests'
    Assert-LL (Test-Path (Join-Path $result.BackupFolder 'backup-info.json')) 'creates backup metadata'
    foreach ($path in @($firstManifest, $secondManifest)) {
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $p = $json.entries[0].paths
        Assert-LL ($p.nodePath -eq (Join-Path $goodBin 'node.exe')) 'repairs nodePath'
        Assert-LL ($p.nodeReplPath -eq (Join-Path $goodBin 'node_repl.exe')) 'repairs nodeReplPath'
        Assert-LL (@($p.nodeModuleDirs)[0] -eq (Join-Path $goodBin 'node_modules')) 'repairs nodeModuleDirs array'
        Assert-LL ($p.resourcesPath -eq $resources) 'repairs resourcesPath'
        Assert-LL ($p.customField -eq 'DO_NOT_TOUCH') 'preserves unrelated fields'
        Assert-LL ($json.entries[1].paths.nodePath -eq 'leave-as-is') 'does not rewrite unrelated entry'
    }
    $again = Invoke-LLRepair -Context $context
    Assert-LL ($again.Changes -eq 0) 'second repair is idempotent'
    Assert-LL (@(Get-LLBackups -Context $context).Count -eq 1) 'does not create extra backup if nothing changed'
    $restored = Invoke-LLRestore -Context $context
    Assert-LL ($restored.Restored -eq 2) 'restores both original manifests'
    Assert-LL (((Get-LLFileHash $firstManifest) -eq $before1) -and ((Get-LLFileHash $secondManifest) -eq $before2)) 'restore recovers original bytes'
    $result2 = Invoke-LLRepair -Context $context
    # Simulate the official updater modifying the manifest after our repair.
    Add-Content -LiteralPath $firstManifest -Value ' ' -Encoding Ascii
    $blocked = $false
    try { $null = Invoke-LLRestore -Context $context } catch { $blocked = $true }
    Assert-LL $blocked 'refuses to overwrite a newer externally modified manifest'
    Write-Host "`nAll tests passed." -ForegroundColor Cyan
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
