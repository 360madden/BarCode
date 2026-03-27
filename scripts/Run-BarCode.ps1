<#
script name: scripts/Run-BarCode.ps1
version: 0.3.18
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
$latestSummaryPath = 'C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-summary.txt'
$latestSummaryJsonPath = 'C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-summary.json'
$latestStateTextPath = 'C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-state.txt'
$latestStateJsonPath = 'C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-state.json'
$latestHistoryJsonPath = 'C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\recent-history.json'
$latestHistoryJsonlPath = 'C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\recent-history.jsonl'
$archiveRoot = 'C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\out\archive'
$archiveKeepCount = 50

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

function Get-LatestRunLines {
    if (-not (Test-Path -LiteralPath $latestRunPath)) {
        return @()
    }

    return @(Get-Content -LiteralPath $latestRunPath -ErrorAction SilentlyContinue)
}

function Get-LatestRunReportPathFromLines {
    param([string[]]$Lines)

    foreach ($line in $Lines) {
        if ($line -like 'Report=*') {
            return $line.Substring(7)
        }
    }

    return $null
}

function Wait-ForFreshFile {
    param(
        [string]$LiteralPath,
        [datetime]$NotOlderThan,
        [int]$TimeoutMs = 1500
    )

    if ([string]::IsNullOrWhiteSpace($LiteralPath)) {
        return $false
    }

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $minimumWriteTime = $NotOlderThan.AddMilliseconds(-250)

    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $LiteralPath) {
            $item = Get-Item -LiteralPath $LiteralPath -ErrorAction SilentlyContinue
            if ($null -ne $item -and $item.LastWriteTime -ge $minimumWriteTime) {
                return $true
            }
        }

        Start-Sleep -Milliseconds 50
    }

    return Test-FreshFile -LiteralPath $LiteralPath -NotOlderThan $NotOlderThan
}

function Test-FreshFile {
    param(
        [string]$LiteralPath,
        [datetime]$NotOlderThan
    )

    if ([string]::IsNullOrWhiteSpace($LiteralPath)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return $false
    }

    $item = Get-Item -LiteralPath $LiteralPath -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $false
    }

    return $item.LastWriteTime -ge $NotOlderThan.AddMilliseconds(-250)
}

function Wait-ForLatestRunCompletion {
    param(
        [datetime]$NotOlderThan,
        [int]$TimeoutMs = 2000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $minimumWriteTime = $NotOlderThan.AddMilliseconds(-250)

    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $latestRunPath) {
            $item = Get-Item -LiteralPath $latestRunPath -ErrorAction SilentlyContinue
            $lines = Get-LatestRunLines
            $firstLine = ''
            if ($lines.Count -gt 0) {
                $firstLine = $lines[0]
            }
            $isComplete = $firstLine -like 'BarCode DesktopAHK run complete*' -or $firstLine -like 'BarCode DesktopAHK run failed*'
            if ($null -ne $item -and $item.LastWriteTime -ge $minimumWriteTime -and $isComplete) {
                return $lines
            }
        }

        Start-Sleep -Milliseconds 50
    }

    return Get-LatestRunLines
}

function Copy-ArtifactIfPresent {
    param(
        [string]$SourcePath,
        [string]$DestinationDirectory,
        [datetime]$NotOlderThan
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return
    }

    if (-not (Test-FreshFile -LiteralPath $SourcePath -NotOlderThan $NotOlderThan)) {
        return
    }

    $leaf = Split-Path -Leaf $SourcePath
    Copy-Item -LiteralPath $SourcePath -Destination (Join-Path $DestinationDirectory $leaf) -Force
}

function New-RunArchive {
    param(
        [datetime]$StartedAt,
        [string]$ModeName,
        [string]$ReportPath
    )

    if ($ModeName -in @('help', '--help', '-h', 'summary')) {
        return $null
    }

    $stamp = $StartedAt.ToString('yyyyMMdd-HHmmss-fff')
    $archiveDir = Join-Path $archiveRoot ($stamp + '-' + $ModeName)
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null

    Copy-ArtifactIfPresent -SourcePath $latestRunPath -DestinationDirectory $archiveDir -NotOlderThan $StartedAt
    Copy-ArtifactIfPresent -SourcePath $ReportPath -DestinationDirectory $archiveDir -NotOlderThan $StartedAt
    Copy-ArtifactIfPresent -SourcePath $latestSummaryPath -DestinationDirectory $archiveDir -NotOlderThan $StartedAt
    Copy-ArtifactIfPresent -SourcePath $latestSummaryJsonPath -DestinationDirectory $archiveDir -NotOlderThan $StartedAt
    Copy-ArtifactIfPresent -SourcePath $latestStateTextPath -DestinationDirectory $archiveDir -NotOlderThan $StartedAt
    Copy-ArtifactIfPresent -SourcePath $latestStateJsonPath -DestinationDirectory $archiveDir -NotOlderThan $StartedAt
    Copy-ArtifactIfPresent -SourcePath $latestHistoryJsonPath -DestinationDirectory $archiveDir -NotOlderThan $StartedAt
    Copy-ArtifactIfPresent -SourcePath $latestHistoryJsonlPath -DestinationDirectory $archiveDir -NotOlderThan $StartedAt

    return $archiveDir
}

function Trim-RunArchives {
    param(
        [string]$ArchiveDirectoryRoot,
        [int]$KeepCount
    )

    if ($KeepCount -le 0) {
        return
    }

    if (-not (Test-Path -LiteralPath $ArchiveDirectoryRoot)) {
        return
    }

    $directories = @(Get-ChildItem -LiteralPath $ArchiveDirectoryRoot -Directory | Sort-Object LastWriteTime -Descending)
    if ($directories.Count -le $KeepCount) {
        return
    }

    foreach ($dir in $directories[$KeepCount..($directories.Count - 1)]) {
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force
    }
}

$runStartTime = Get-Date
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

$latestRun = Wait-ForLatestRunCompletion -NotOlderThan $runStartTime
$reportPath = Get-LatestRunReportPathFromLines -Lines $latestRun
$hasFreshReport = $false
if ($reportPath) {
    $hasFreshReport = Wait-ForFreshFile -LiteralPath $reportPath -NotOlderThan $runStartTime -TimeoutMs 1500
}
$hasFreshSummary = $false
if ($Mode -ne 'summary') {
    $hasFreshSummary = Wait-ForFreshFile -LiteralPath $latestSummaryPath -NotOlderThan $runStartTime -TimeoutMs 1500
}

if ($reportPath) {
    Write-Output '--- LATEST RUN ---'
    $latestRun
    if ((-not $stdout) -and $hasFreshReport) {
        Write-Output '--- REPORT ---'
        Get-Content -LiteralPath $reportPath -ErrorAction SilentlyContinue
    }
}

if (($Mode -ne 'summary') -and $hasFreshSummary) {
    Write-Output '--- SUMMARY ---'
    Get-Content -LiteralPath $latestSummaryPath -ErrorAction SilentlyContinue
}

$archiveDir = New-RunArchive -StartedAt $runStartTime -ModeName $Mode -ReportPath $reportPath
if ($archiveDir) {
    Trim-RunArchives -ArchiveDirectoryRoot $archiveRoot -KeepCount $archiveKeepCount
    Write-Output ('ArchiveDir=' + $archiveDir)
}

exit $process.ExitCode

# end-of-script marker comment
