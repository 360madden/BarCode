[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath
)

$exe = 'C:\Users\mrkoo\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe'

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

$arguments = @('/Validate', '/ErrorStdOut=UTF-8', $ScriptPath)
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

$finished = $process.WaitForExit(10000)
if (-not $finished) {
    $process.Kill()
    $process.WaitForExit()
    Write-Output 'TimedOut=true'
}

$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()

Write-Output ("ExitCode=" + $process.ExitCode)

if ($stdout.Length -gt 0) {
    Write-Output '--- STDOUT ---'
    Write-Output $stdout
}

if ($stderr.Length -gt 0) {
    Write-Output '--- STDERR ---'
    Write-Output $stderr
}
