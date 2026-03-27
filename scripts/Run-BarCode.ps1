<#
script name: scripts/Run-BarCode.ps1
version: 0.3.3
purpose: Runs DesktopAHK/Main.ahk with a chosen mode and prints the most useful available summary back to PowerShell.
dependencies: AutoHotkey v2, DesktopAHK/Main.ahk
important assumptions: Falls back to latest-run.txt and the referenced report file when the GUI-subsystem AHK process does not emit stdout reliably.
protocol version: BC-Strip/1
framework module role: Operator helper
character count note: Character count not precomputed; measure with tooling if needed.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Mode = 'smoke',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ModeArgs = @()
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainScript = Join-Path $repoRoot 'DesktopAHK\Main.ahk'
$exe = 'C:\Users\mrkoo\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe'
$latestRunPath = 'C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\out\latest-run.txt'

function Format-ProcessArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Get-LatestRunReportPath {
    if (-not (Test-Path -LiteralPath $latestRunPath)) {
        return $null
    }

    $latestRun = Get-Content -LiteralPath $latestRunPath -ErrorAction SilentlyContinue
    foreach ($line in $latestRun) {
        if ($line -like 'Report=*') {
            return $line.Substring(7)
        }
    }

    return $null
}

$arguments = @('/ErrorStdOut=UTF-8', $mainScript, $Mode) + $ModeArgs
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $exe
$startInfo.Arguments = (($arguments | ForEach-Object { Format-ProcessArgument $_ }) -join ' ')
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$null = $process.Start()
$process.WaitForExit()

$stdout = $process.StandardOutput.ReadToEnd().Trim()
$stderr = $process.StandardError.ReadToEnd().Trim()

Write-Output ("ExitCode=" + $process.ExitCode)

if ($stdout) {
    Write-Output '--- STDOUT ---'
    Write-Output $stdout
}

if ($stderr) {
    Write-Output '--- STDERR ---'
    Write-Output $stderr
}

$reportPath = Get-LatestRunReportPath
if ($reportPath) {
    Write-Output '--- LATEST RUN ---'
    Get-Content -LiteralPath $latestRunPath -ErrorAction SilentlyContinue
    if ((-not $stdout) -and (Test-Path -LiteralPath $reportPath)) {
        Write-Output '--- REPORT ---'
        Get-Content -LiteralPath $reportPath -ErrorAction SilentlyContinue
    }
}

exit $process.ExitCode

# end-of-script marker comment
