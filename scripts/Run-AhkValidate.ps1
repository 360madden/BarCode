param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath
)

$exe = 'C:\Users\mrkoo\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe'
$stdout = Join-Path $env:TEMP 'barcode-ahk-validate-stdout.txt'
$stderr = Join-Path $env:TEMP 'barcode-ahk-validate-stderr.txt'

Remove-Item -Force $stdout, $stderr -ErrorAction SilentlyContinue

$process = Start-Process `
    -FilePath $exe `
    -ArgumentList '/Validate', '/ErrorStdOut=UTF-8', $ScriptPath `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$finished = $process.WaitForExit(10000)
if (-not $finished) {
    Stop-Process -Id $process.Id -Force
    Write-Output 'TimedOut=true'
}

Write-Output ("ExitCode=" + $process.ExitCode)

if (Test-Path $stdout) {
    Write-Output '--- STDOUT ---'
    Get-Content -Raw $stdout
}

if (Test-Path $stderr) {
    Write-Output '--- STDERR ---'
    Get-Content -Raw $stderr
}
