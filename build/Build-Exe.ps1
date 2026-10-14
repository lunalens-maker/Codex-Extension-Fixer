#Requires -Version 5.1
<#
.SYNOPSIS
    Build a portable Windows EXE from the GUI and the core script.
.DESCRIPTION
    Combines both source files into one PS2EXE input so the final executable
    has no runtime dependency on project .ps1 files. Requires ps2exe 1.0.18.
#>
[CmdletBinding()]
param(
    [string]$Version = '0.2.0.0',
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$coreFile = Join-Path $repoRoot 'src\CodexFixer.Core.ps1'
$guiFile  = Join-Path $repoRoot 'Codex-Fixer.ps1'

Import-Module -Name ps2exe -RequiredVersion '1.0.18' -ErrorAction Stop
foreach ($path in @($coreFile, $guiFile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing source file: $path" }
}

$core = Get-Content -LiteralPath $coreFile -Raw -Encoding UTF8
$gui = Get-Content -LiteralPath $guiFile -Raw -Encoding UTF8

# The original GUI dot-sources the core from its folder. A single-file EXE
# has no such folder, so inline the core functions before the GUI code.
$dotSourceLine = '. (Join-Path $PSScriptRoot ''src\CodexFixer.Core.ps1'')'
$dotSourcePattern = '(?m)^[ \t]*' + [regex]::Escape($dotSourceLine) + '[ \t]*\r?\n'
$matches = [regex]::Matches($gui, $dotSourcePattern)
if ($matches.Count -ne 1) {
    throw "Expected exactly one GUI core import, found $($matches.Count). Aborting."
}
$gui = [regex]::Replace($gui, $dotSourcePattern, '')
$combined = $core.TrimStart([char]0xFEFF) + "`r`n" + $gui.TrimStart([char]0xFEFF)

$OutputDir = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir))
$null = New-Item -ItemType Directory -Path $OutputDir -Force
$inputFile = Join-Path $OutputDir 'Codex-Extension-Fixer.build-input.ps1'
$outputFile = Join-Path $OutputDir 'Codex-Extension-Fixer.exe'
# UTF-8 BOM is required here: Windows PowerShell 5.1's ParseFile defaults
# to the system ANSI codepage when the merged .ps1 file has no BOM.
$utf8 = New-Object System.Text.UTF8Encoding($true)

try {
    [System.IO.File]::WriteAllText($inputFile, $combined, $utf8)
    $parseTokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($inputFile, [ref]$parseTokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "Combined script syntax error: $($parseErrors[0].Message)"
    }

    Invoke-ps2exe -inputFile $inputFile -outputFile $outputFile `
        -noConsole -STA -x64 -DPIAware `
        -title 'Codex Extension Fixer' `
        -description 'Repair obsolete Codex Chrome extension runtime paths' `
        -product 'Codex Extension Fixer' `
        -version $Version

    if (-not (Test-Path -LiteralPath $outputFile -PathType Leaf)) {
        throw 'PS2EXE did not generate an executable.'
    }
    $bytes = [System.IO.File]::ReadAllBytes($outputFile)
    if ($bytes.Length -lt 4096 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw 'Build output is not a Windows PE executable.'
    }
    Write-Host "Built: $outputFile"
    Get-FileHash -LiteralPath $outputFile -Algorithm SHA256 | Format-List
}
finally {
    if (Test-Path -LiteralPath $inputFile) {
        Remove-Item -LiteralPath $inputFile -Force
    }
}
