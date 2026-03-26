[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$ScriptPath = 'DesktopAHK\Main.ahk',
    [int]$DurationSeconds = 30,
    [int]$ReaderSleepMs = 100,
    [int]$PollMs = 200,
    [int]$StaleAfterMs = 1500,
    [switch]$NoLaunchReader,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$ahkExe = 'C:\Users\mrkoo\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe'
$dataRoot = Join-Path $env:LOCALAPPDATA 'BarCode\DesktopAHK'
$statePath = Join-Path $dataRoot 'state\latest-state.json'
$stateTextPath = Join-Path $dataRoot 'state\latest-state.txt'
$latestRunPath = Join-Path $dataRoot 'out\latest-run.txt'

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

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

function Build-StateSignature {
    param($State)

    return ('{0}|{1}|{2}|{3}|{4}' -f $State.timestampUtc, $State.sampleIndex, $State.sequence, $State.accepted, $State.reason)
}

function Format-StateLine {
    param($State)

    $health = '{0}/{1}' -f $State.healthCurrent, $State.healthMax
    $resource = '{0} {1}/{2}' -f $State.resourceKindName, $State.resourceCurrent, $State.resourceMax
    $calling = if ($State.callingName) { $State.callingName } else { $State.callingCode }
    $role = if ($State.roleName) { $State.roleName } else { $State.roleCode }
    $advance = if ($null -ne $State.sequenceAdvance) { $State.sequenceAdvance } else { '' }
    return ('{0} seq={1} adv={2} fresh={3} ok={4} hp={5} res={6} cast={7} lvl={8} call={9} role={10} search={11} capture={12} conf={13}' -f `
        $State.timestampUtc, `
        $State.sequence, `
        $advance, `
        $State.freshFrame, `
        $State.accepted, `
        $health, `
        $resource.Trim(), `
        $State.castProgressQ15, `
        $State.level, `
        $calling, `
        $role, `
        $State.searchMode, `
        $State.captureSource, `
        $State.confidence)
}

$readerProcess = $null
$stdoutPath = Join-Path $env:TEMP 'barcode-watch-live-stdout.txt'
$stderrPath = Join-Path $env:TEMP 'barcode-watch-live-stderr.txt'
Remove-Item -Force $stdoutPath, $stderrPath -ErrorAction SilentlyContinue

if (-not $NoLaunchReader) {
    Remove-Item -Force $statePath, $stateTextPath -ErrorAction SilentlyContinue
    $scriptFullPath = Resolve-RepoPath $ScriptPath
    $arguments = @('/ErrorStdOut=UTF-8', $scriptFullPath, 'watch', [string]$DurationSeconds, [string]$ReaderSleepMs)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ahkExe
    $startInfo.Arguments = (($arguments | ForEach-Object { Format-ProcessArgument $_ }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $readerProcess = [System.Diagnostics.Process]::new()
    $readerProcess.StartInfo = $startInfo
    $null = $readerProcess.Start()
    Write-Output ('Launched reader watch for {0}s using {1}' -f $DurationSeconds, $scriptFullPath)
}

$startTime = Get-Date
$deadline = if ($DurationSeconds -gt 0) { $startTime.AddSeconds($DurationSeconds + 3) } else { [DateTime]::MaxValue }
$lastSignature = ''
$sawAnyState = $false
$lastStateSeenAt = $null
$staleReported = $false
Write-Output ('Watching {0}' -f $statePath)

while ((Get-Date) -lt $deadline) {
    if (Test-Path $statePath) {
        try {
            $state = Get-Content -Path $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace([string]$state.timestampUtc)) {
                Start-Sleep -Milliseconds $PollMs
                continue
            }
            $signature = Build-StateSignature $state
            if ($signature -ne $lastSignature) {
                $lastSignature = $signature
                $sawAnyState = $true
                $lastStateSeenAt = Get-Date
                $staleReported = $false
                if ($Json) {
                    $state | ConvertTo-Json -Compress
                } else {
                    Format-StateLine $state
                }
            }
        } catch {
        }
    }

    if (-not $Json -and $sawAnyState -and -not $staleReported -and $StaleAfterMs -gt 0 -and $lastStateSeenAt) {
        $ageMs = [int]((Get-Date) - $lastStateSeenAt).TotalMilliseconds
        if ($ageMs -ge $StaleAfterMs) {
            Write-Output ('STALE ageMs={0} lastSeq={1}' -f $ageMs, $state.sequence)
            $staleReported = $true
        }
    }

    if ($readerProcess -and $readerProcess.HasExited -and $sawAnyState) {
        break
    }

    Start-Sleep -Milliseconds $PollMs
}

if ($readerProcess) {
    $readerProcess.WaitForExit()
    $stdout = $readerProcess.StandardOutput.ReadToEnd()
    $stderr = $readerProcess.StandardError.ReadToEnd()
    if ($stdout.Length -gt 0) {
        [System.IO.File]::WriteAllText($stdoutPath, $stdout, [System.Text.Encoding]::UTF8)
    }
    if ($stderr.Length -gt 0) {
        [System.IO.File]::WriteAllText($stderrPath, $stderr, [System.Text.Encoding]::UTF8)
    }

    Write-Output ('ReaderExitCode={0}' -f $readerProcess.ExitCode)
    if ($readerProcess.ExitCode -ne 0 -and (Test-Path $latestRunPath)) {
        Write-Output '--- Latest Run ---'
        Get-Content -Path $latestRunPath
    }
    if ($stdout.Length -gt 0) {
        Write-Output ('ReaderStdout: {0}' -f $stdoutPath)
    }
    if ($stderr.Length -gt 0) {
        Write-Output ('ReaderStderr: {0}' -f $stderrPath)
    }

    exit $readerProcess.ExitCode
}

if (-not $sawAnyState) {
    Write-Output 'No live state updates were observed.'
    exit 1
}

exit 0
