param(
    [string]$ScriptPath = 'DesktopAHK\Main.ahk',
    [int]$LiveIterations = 3,
    [int]$LiveSamples = 10,
    [int]$LiveSleepMs = 100,
    [switch]$SkipLive
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

function New-ArtifactDir {
    param([string]$Name)

    $path = Join-Path $script:sessionDir $Name
    [System.IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
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

function Get-IntOrDefault {
    param(
        [System.Collections.IDictionary]$Map,
        [string]$Key,
        [int]$Default = 0
    )

    $value = Get-TextOrDefault -Map $Map -Key $Key
    if ($value -match '^-?\d+$') {
        return [int]$value
    }

    return $Default
}

function Format-BoolText {
    param([bool]$Value)

    if ($Value) {
        return 'true'
    }

    return 'false'
}

function Format-PassFail {
    param([bool]$Value)

    if ($Value) {
        return 'PASS'
    }

    return 'FAIL'
}

$mainScriptPath = Resolve-RepoPath $ScriptPath
$dataRoot = Get-BarCodeDataRoot
$outDir = Join-Path $dataRoot 'out'
$artifactRoot = Join-Path $outDir 'verify'
$sessionDir = Join-Path $artifactRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
$validateRunner = Resolve-RepoPath 'scripts\Run-AhkValidate.cmd'
$scriptRunner = Resolve-RepoPath 'scripts\Run-AhkScript.cmd'
$latestRunPath = Join-Path $outDir 'latest-run.txt'
$smokeReportPath = Join-Path $outDir 'phase2-reader-smoke.txt'
$liveReportPath = Join-Path $outDir 'phase2-live.txt'
$tracePath = Join-Path $outDir 'trace.txt'
$liveCaptureBmpPath = Join-Path $outDir 'phase2-live-last-capture.bmp'

[System.IO.Directory]::CreateDirectory($sessionDir) | Out-Null

$validateDir = New-ArtifactDir 'validate'
$validateStep = Invoke-ToolStep `
    -Label 'validate' `
    -FilePath $validateRunner `
    -Arguments @('-ScriptPath', $mainScriptPath) `
    -LogPath (Join-Path $validateDir 'runner-output.txt')
Copy-ArtifactIfPresent -SourcePath $latestRunPath -DestinationDir $validateDir
Copy-ArtifactIfPresent -SourcePath $tracePath -DestinationDir $validateDir

$smokeDir = New-ArtifactDir 'smoke'
$smokeStep = Invoke-ToolStep `
    -Label 'smoke' `
    -FilePath $scriptRunner `
    -Arguments @('-ScriptPath', $mainScriptPath, '-TimeoutMs', '30000', 'smoke') `
    -LogPath (Join-Path $smokeDir 'runner-output.txt')
$latestAfterSmoke = Read-KeyValueReport -Path $latestRunPath
$smokeReport = Read-KeyValueReport -Path $smokeReportPath
Copy-ArtifactIfPresent -SourcePath $latestRunPath -DestinationDir $smokeDir
Copy-ArtifactIfPresent -SourcePath $smokeReportPath -DestinationDir $smokeDir
Copy-ArtifactIfPresent -SourcePath $tracePath -DestinationDir $smokeDir

$smokePassed = (
    $smokeStep.Passed -and
    (Get-TextOrDefault -Map $latestAfterSmoke -Key 'Mode') -eq 'smoke' -and
    (Get-TextOrDefault -Map $latestAfterSmoke -Key 'Success') -eq 'true' -and
    (Get-TextOrDefault -Map $smokeReport -Key 'Success') -eq 'true' -and
    (Get-TextOrDefault -Map $smokeReport -Key 'Good accepted') -eq 'true' -and
    (Get-TextOrDefault -Map $smokeReport -Key 'Corrupt accepted') -eq 'false'
)

$liveRuns = @()
if (-not $SkipLive) {
    $iteration = 1
    while ($iteration -le $LiveIterations) {
        $liveDirName = 'live-{0:d3}' -f $iteration
        $liveDir = New-ArtifactDir $liveDirName
        $liveStep = Invoke-ToolStep `
            -Label $liveDirName `
            -FilePath $scriptRunner `
            -Arguments @('-ScriptPath', $mainScriptPath, '-TimeoutMs', '30000', 'live', "$LiveSamples", "$LiveSleepMs") `
            -LogPath (Join-Path $liveDir 'runner-output.txt')
        $latestAfterLive = Read-KeyValueReport -Path $latestRunPath
        $liveReport = Read-KeyValueReport -Path $liveReportPath
        Copy-ArtifactIfPresent -SourcePath $latestRunPath -DestinationDir $liveDir
        Copy-ArtifactIfPresent -SourcePath $liveReportPath -DestinationDir $liveDir
        Copy-ArtifactIfPresent -SourcePath $tracePath -DestinationDir $liveDir
        Copy-ArtifactIfPresent -SourcePath $liveCaptureBmpPath -DestinationDir $liveDir

        $acceptedSamples = Get-IntOrDefault -Map $liveReport -Key 'AcceptedSamples'
        $rejectedSamples = Get-IntOrDefault -Map $liveReport -Key 'RejectedSamples'
        $livePassed = (
            $liveStep.Passed -and
            (Get-TextOrDefault -Map $latestAfterLive -Key 'Mode') -eq 'live' -and
            (Get-TextOrDefault -Map $latestAfterLive -Key 'Success') -eq 'true' -and
            (Get-TextOrDefault -Map $liveReport -Key 'LastAccepted') -eq 'true' -and
            $acceptedSamples -gt 0 -and
            $rejectedSamples -eq 0
        )

        $liveRuns += [ordered]@{
            Iteration = $iteration
            Passed = $livePassed
            RunnerPassed = $liveStep.Passed
            AcceptedSamples = $acceptedSamples
            RejectedSamples = $rejectedSamples
            SearchMode = Get-TextOrDefault -Map $liveReport -Key 'SearchMode'
            LastReason = Get-TextOrDefault -Map $liveReport -Key 'LastReason'
            LastSequence = Get-TextOrDefault -Map $liveReport -Key 'LastSequence'
            ArtifactDir = $liveDir
            LogPath = $liveStep.LogPath
        }

        $iteration += 1
    }
}

$livePassedCount = @($liveRuns | Where-Object { $_.Passed }).Count
$liveFailedCount = @($liveRuns | Where-Object { -not $_.Passed }).Count
$overallPassed = $validateStep.Passed -and $smokePassed -and ($SkipLive -or $liveFailedCount -eq 0)

$summary = [ordered]@{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    SessionDir = $sessionDir
    OverallPassed = $overallPassed
    Validate = [ordered]@{
        Passed = $validateStep.Passed
        ReportedExitCode = $validateStep.ReportedExitCode
        TimedOut = $validateStep.TimedOut
        LogPath = $validateStep.LogPath
    }
    Smoke = [ordered]@{
        Passed = $smokePassed
        ReportedExitCode = $smokeStep.ReportedExitCode
        TimedOut = $smokeStep.TimedOut
        GoodAccepted = Get-TextOrDefault -Map $smokeReport -Key 'Good accepted'
        CorruptAccepted = Get-TextOrDefault -Map $smokeReport -Key 'Corrupt accepted'
        GoodReason = Get-TextOrDefault -Map $smokeReport -Key 'Good reason'
        CorruptReason = Get-TextOrDefault -Map $smokeReport -Key 'Corrupt reason'
        ArtifactDir = $smokeDir
        LogPath = $smokeStep.LogPath
    }
    Live = [ordered]@{
        Skipped = [bool]$SkipLive
        Iterations = $LiveIterations
        SamplesPerIteration = $LiveSamples
        SleepMs = $LiveSleepMs
        PassedRuns = $livePassedCount
        FailedRuns = $liveFailedCount
        Runs = $liveRuns
    }
}

$summaryLines = @()
$summaryLines += 'BarCode verification summary'
$summaryLines += ('Timestamp: ' + $summary.Timestamp)
$summaryLines += ('OverallPassed: ' + (Format-BoolText $summary.OverallPassed))
$summaryLines += ('SessionDir: ' + $summary.SessionDir)
$summaryLines += ''
$summaryLines += ('Validate: ' + (Format-PassFail $summary.Validate.Passed) + ' (ExitCode=' + $summary.Validate.ReportedExitCode + ')')
$summaryLines += ('Smoke: ' + (Format-PassFail $summary.Smoke.Passed) + ' (GoodAccepted=' + $summary.Smoke.GoodAccepted + ', CorruptAccepted=' + $summary.Smoke.CorruptAccepted + ')')

if ($SkipLive) {
    $summaryLines += 'Live: SKIPPED'
} else {
    $summaryLines += ('Live: ' + $livePassedCount + '/' + $LiveIterations + ' passed (Samples=' + $LiveSamples + ', SleepMs=' + $LiveSleepMs + ')')
    foreach ($run in $liveRuns) {
        $summaryLines += ('  Live-' + ('{0:d3}' -f $run.Iteration) + ': ' + (Format-PassFail $run.Passed) + ' Accepted=' + $run.AcceptedSamples + ' Rejected=' + $run.RejectedSamples + ' SearchMode=' + $run.SearchMode + ' LastReason=' + $run.LastReason)
    }
}

$summaryTextPath = Join-Path $sessionDir 'summary.txt'
$summaryJsonPath = Join-Path $sessionDir 'summary.json'
[System.IO.File]::WriteAllLines($summaryTextPath, $summaryLines, [System.Text.Encoding]::UTF8)
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryJsonPath -Encoding UTF8

$summaryLines | ForEach-Object { Write-Output $_ }
Write-Output ('SummaryText: ' + $summaryTextPath)
Write-Output ('SummaryJson: ' + $summaryJsonPath)

if ($overallPassed) {
    exit 0
}

exit 1
