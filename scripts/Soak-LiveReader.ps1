[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$ScriptPath = 'DesktopAHK\Main.ahk',
    [int]$DurationSeconds = 60,
    [int]$ReaderSleepMs = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Get-BarCodeDataRoot {
    $baseDir = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($baseDir)) {
        $baseDir = $env:TEMP
    }

    return Join-Path $baseDir 'BarCode\DesktopAHK'
}

function Read-KeyValueReport {
    param([string]$Path)

    $result = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $result
    }

    foreach ($line in Get-Content -Path $Path) {
        if ($line -match '^(?<key>[^:=]+)\s*[:=]\s*(?<value>.*)$') {
            $result[$Matches.key.Trim()] = $Matches.value.Trim()
        }
    }

    return $result
}

function Invoke-ToolStep {
    param(
        [string]$Label,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$LogPath
    )

    $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $shellExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    $reportedExitCode = $null
    $timedOut = $false

    foreach ($line in $output) {
        if ($line -eq 'TimedOut=true') {
            $timedOut = $true
        }
        if ($line -match '^ExitCode=(?<code>-?\d+)$') {
            $reportedExitCode = [int]$Matches.code
        }
    }

    $logDir = Split-Path $LogPath -Parent
    if ($logDir) {
        [System.IO.Directory]::CreateDirectory($logDir) | Out-Null
    }
    [System.IO.File]::WriteAllLines($LogPath, $output, [System.Text.Encoding]::UTF8)

    return [ordered]@{
        Label = $Label
        ShellExitCode = $shellExitCode
        ReportedExitCode = $reportedExitCode
        TimedOut = $timedOut
        Passed = ($shellExitCode -eq 0 -and -not $timedOut -and $reportedExitCode -eq 0)
        LogPath = $LogPath
        Output = $output
    }
}

function Copy-ArtifactIfPresent {
    param(
        [string]$SourcePath,
        [string]$DestinationDir
    )

    if (Test-Path $SourcePath) {
        [System.IO.Directory]::CreateDirectory($DestinationDir) | Out-Null
        Copy-Item -Path $SourcePath -Destination (Join-Path $DestinationDir (Split-Path $SourcePath -Leaf)) -Force
    }
}

function Get-DoubleAverage {
    param(
        [object[]]$Items,
        [string]$Property
    )

    $values = @(
        $Items |
            Where-Object { $null -ne $_.$Property -and $_.$Property -ne '' } |
            ForEach-Object { [double]$_.$Property }
    )

    if ($values.Count -eq 0) {
        return 0.0
    }

    return [Math]::Round((($values | Measure-Object -Average).Average), 2)
}

function Format-BoolText {
    param([bool]$Value)

    if ($Value) {
        return 'true'
    }

    return 'false'
}

function Get-TextOrDefault {
    param(
        [System.Collections.IDictionary]$Map,
        [string]$Key,
        [string]$Default = ''
    )

    if ($null -ne $Map -and $Map.Contains($Key)) {
        return [string]$Map[$Key]
    }

    return $Default
}

$mainScriptPath = Resolve-RepoPath $ScriptPath
$dataRoot = Get-BarCodeDataRoot
$outDir = Join-Path $dataRoot 'out'
$stateDir = Join-Path $dataRoot 'state'
$artifactRoot = Join-Path $outDir 'soak'
$sessionDir = Join-Path $artifactRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
$scriptRunner = Resolve-RepoPath 'scripts\Run-AhkScript.cmd'
$latestRunPath = Join-Path $outDir 'latest-run.txt'
$watchReportPath = Join-Path $outDir 'phase2-watch.txt'
$tracePath = Join-Path $outDir 'trace.txt'
$latestStateJsonPath = Join-Path $stateDir 'latest-state.json'
$latestStateTextPath = Join-Path $stateDir 'latest-state.txt'
$historyJsonPath = Join-Path $stateDir 'recent-history.json'
$historyJsonlPath = Join-Path $stateDir 'recent-history.jsonl'

[System.IO.Directory]::CreateDirectory($sessionDir) | Out-Null

$timeoutMs = [Math]::Max(30000, ($DurationSeconds + 10) * 1000)
$runnerStep = Invoke-ToolStep `
    -Label 'soak-watch' `
    -FilePath $scriptRunner `
    -Arguments @('-ScriptPath', $mainScriptPath, '-TimeoutMs', "$timeoutMs", 'watch', "$DurationSeconds", "$ReaderSleepMs") `
    -LogPath (Join-Path $sessionDir 'runner-output.txt')

$latestRun = Read-KeyValueReport -Path $latestRunPath
$watchReport = Read-KeyValueReport -Path $watchReportPath

$history = @()
if (Test-Path $historyJsonPath) {
    $historyContent = Get-Content -Path $historyJsonPath -Raw -ErrorAction Stop
    $parsedHistory = ConvertFrom-Json -InputObject $historyContent -ErrorAction Stop
    $history = @($parsedHistory)
}

$sampleCount = $history.Count
$acceptedCount = @($history | Where-Object { $_.accepted }).Count
$rejectedCount = @($history | Where-Object { -not $_.accepted }).Count
$freshFrameCount = @($history | Where-Object { $_.freshFrame }).Count
$repeatedFrameCount = @($history | Where-Object { $_.accepted -and -not $_.freshFrame }).Count
$lockedCount = @($history | Where-Object { $_.searchMode -eq 'locked' }).Count
$searchingCount = $sampleCount - $lockedCount
$sequenceAdvances = @(
    $history |
        Where-Object { $null -ne $_.sequenceAdvance } |
        ForEach-Object { [int]$_.sequenceAdvance }
)
$maxSequenceAdvance = if ($sequenceAdvances.Count -gt 0) { ($sequenceAdvances | Measure-Object -Maximum).Maximum } else { 0 }
$wrapCount = if ($sampleCount -gt 0) { [int]$history[-1].sequenceWrapCount } else { 0 }
$firstSequence = if ($sampleCount -gt 0) { [int]$history[0].sequence } else { $null }
$lastSequence = if ($sampleCount -gt 0) { [int]$history[-1].sequence } else { $null }
$overallPassed = (
    $runnerStep.Passed -and
    (Get-TextOrDefault -Map $latestRun -Key 'Mode') -eq 'watch' -and
    (Get-TextOrDefault -Map $latestRun -Key 'Success') -eq 'true' -and
    $sampleCount -gt 0 -and
    $rejectedCount -eq 0
)

$summary = [ordered]@{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    OverallPassed = $overallPassed
    SessionDir = $sessionDir
    DurationSeconds = $DurationSeconds
    ReaderSleepMs = $ReaderSleepMs
    Samples = $sampleCount
    AcceptedSamples = $acceptedCount
    RejectedSamples = $rejectedCount
    FreshFrames = $freshFrameCount
    RepeatedFrames = $repeatedFrameCount
    LockedSamples = $lockedCount
    SearchingSamples = $searchingCount
    FirstSequence = $firstSequence
    LastSequence = $lastSequence
    MaxSequenceAdvance = $maxSequenceAdvance
    SequenceWrapCount = $wrapCount
    AverageCaptureMs = Get-DoubleAverage -Items $history -Property 'captureMs'
    AveragePipelineMs = Get-DoubleAverage -Items $history -Property 'pipelineMs'
    AverageConfidence = Get-DoubleAverage -Items $history -Property 'confidence'
    ReportedSearchMode = Get-TextOrDefault -Map $watchReport -Key 'SearchMode'
    RunnerExitCode = $runnerStep.ReportedExitCode
    RunnerTimedOut = $runnerStep.TimedOut
    WatchReportPath = $watchReportPath
    LatestStatePath = $latestStateJsonPath
    HistoryJsonPath = $historyJsonPath
    HistoryJsonlPath = $historyJsonlPath
}

$summaryLines = @()
$summaryLines += 'BarCode live soak summary'
$summaryLines += ('Timestamp: ' + $summary.Timestamp)
$summaryLines += ('OverallPassed: ' + (Format-BoolText $summary.OverallPassed))
$summaryLines += ('SessionDir: ' + $summary.SessionDir)
$summaryLines += ('DurationSeconds: ' + $summary.DurationSeconds)
$summaryLines += ('ReaderSleepMs: ' + $summary.ReaderSleepMs)
$summaryLines += ('Samples: ' + $summary.Samples)
$summaryLines += ('AcceptedSamples: ' + $summary.AcceptedSamples)
$summaryLines += ('RejectedSamples: ' + $summary.RejectedSamples)
$summaryLines += ('FreshFrames: ' + $summary.FreshFrames)
$summaryLines += ('RepeatedFrames: ' + $summary.RepeatedFrames)
$summaryLines += ('LockedSamples: ' + $summary.LockedSamples)
$summaryLines += ('SearchingSamples: ' + $summary.SearchingSamples)
$summaryLines += ('FirstSequence: ' + $summary.FirstSequence)
$summaryLines += ('LastSequence: ' + $summary.LastSequence)
$summaryLines += ('MaxSequenceAdvance: ' + $summary.MaxSequenceAdvance)
$summaryLines += ('SequenceWrapCount: ' + $summary.SequenceWrapCount)
$summaryLines += ('AverageCaptureMs: ' + $summary.AverageCaptureMs)
$summaryLines += ('AveragePipelineMs: ' + $summary.AveragePipelineMs)
$summaryLines += ('AverageConfidence: ' + $summary.AverageConfidence)
$summaryLines += ('ReportedSearchMode: ' + $summary.ReportedSearchMode)

$summaryTextPath = Join-Path $sessionDir 'summary.txt'
$summaryJsonPath = Join-Path $sessionDir 'summary.json'
[System.IO.File]::WriteAllLines($summaryTextPath, $summaryLines, [System.Text.Encoding]::UTF8)
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryJsonPath -Encoding UTF8

Copy-ArtifactIfPresent -SourcePath $latestRunPath -DestinationDir $sessionDir
Copy-ArtifactIfPresent -SourcePath $watchReportPath -DestinationDir $sessionDir
Copy-ArtifactIfPresent -SourcePath $tracePath -DestinationDir $sessionDir
Copy-ArtifactIfPresent -SourcePath $latestStateJsonPath -DestinationDir $sessionDir
Copy-ArtifactIfPresent -SourcePath $latestStateTextPath -DestinationDir $sessionDir
Copy-ArtifactIfPresent -SourcePath $historyJsonPath -DestinationDir $sessionDir
Copy-ArtifactIfPresent -SourcePath $historyJsonlPath -DestinationDir $sessionDir

$summaryLines | ForEach-Object { Write-Output $_ }
Write-Output ('SummaryText: ' + $summaryTextPath)
Write-Output ('SummaryJson: ' + $summaryJsonPath)

if ($overallPassed) {
    exit 0
}

exit 1
