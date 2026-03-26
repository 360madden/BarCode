[CmdletBinding(PositionalBinding = $false)]
param(
    [int]$Port = 8756,
    [int]$DurationSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BarCodeDataRoot {
    $baseDir = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($baseDir)) {
        $baseDir = $env:TEMP
    }

    return Join-Path $baseDir 'BarCode\DesktopAHK'
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    return Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [object]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Response.Headers['Access-Control-Allow-Origin'] = '*'
    $Response.Headers['Cache-Control'] = 'no-store'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Write-TextResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Body
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Response.Headers['Access-Control-Allow-Origin'] = '*'
    $Response.Headers['Cache-Control'] = 'no-store'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Get-SummaryPayload {
    param(
        [string]$LatestStatePath,
        [string]$HistoryPath
    )

    $latest = Read-JsonFile -Path $LatestStatePath
    $history = Read-JsonFile -Path $HistoryPath
    $historyItems = @($history)

    return [ordered]@{
        ok = $null -ne $latest
        timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        latest = $latest
        historyCount = $historyItems.Count
        latestStatePath = $LatestStatePath
        historyPath = $HistoryPath
    }
}

$dataRoot = Get-BarCodeDataRoot
$stateDir = Join-Path $dataRoot 'state'
$latestStatePath = Join-Path $stateDir 'latest-state.json'
$historyPath = Join-Path $stateDir 'recent-history.json'
$historyJsonlPath = Join-Path $stateDir 'recent-history.jsonl'
$prefix = 'http://127.0.0.1:{0}/' -f $Port
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
$startedAt = Get-Date
$deadline = if ($DurationSeconds -gt 0) { $startedAt.AddSeconds($DurationSeconds) } else { [DateTime]::MaxValue }

try {
    $listener.Start()
    Write-Output ('Serving live state on {0}' -f $prefix)
    Write-Output ('Endpoints: /health /state /history /history.ndjson /summary')

    while ((Get-Date) -lt $deadline) {
        $contextTask = $listener.GetContextAsync()
        while (-not $contextTask.Wait(250)) {
            if ((Get-Date) -ge $deadline) {
                break
            }
        }

        if (-not $contextTask.IsCompleted) {
            continue
        }

        $context = $contextTask.Result
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath.ToLowerInvariant()

        if ($request.HttpMethod -eq 'OPTIONS') {
            $response.StatusCode = 204
            $response.Headers['Access-Control-Allow-Origin'] = '*'
            $response.Headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
            $response.Headers['Access-Control-Allow-Headers'] = 'Content-Type'
            $response.OutputStream.Close()
            continue
        }

        switch ($path) {
            '/health' {
                Write-JsonResponse -Response $response -StatusCode 200 -Body ([ordered]@{
                    ok = (Test-Path $latestStatePath)
                    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    latestStatePath = $latestStatePath
                    historyPath = $historyPath
                    historyJsonlPath = $historyJsonlPath
                })
            }
            '/state' {
                if (Test-Path $latestStatePath) {
                    Write-TextResponse -Response $response -StatusCode 200 -ContentType 'application/json; charset=utf-8' -Body (Get-Content -Path $latestStatePath -Raw -ErrorAction Stop)
                } else {
                    Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{ ok = $false; error = 'latest-state.json not found' })
                }
            }
            '/history' {
                if (Test-Path $historyPath) {
                    Write-TextResponse -Response $response -StatusCode 200 -ContentType 'application/json; charset=utf-8' -Body (Get-Content -Path $historyPath -Raw -ErrorAction Stop)
                } else {
                    Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{ ok = $false; error = 'recent-history.json not found' })
                }
            }
            '/history.ndjson' {
                if (Test-Path $historyJsonlPath) {
                    Write-TextResponse -Response $response -StatusCode 200 -ContentType 'application/x-ndjson; charset=utf-8' -Body (Get-Content -Path $historyJsonlPath -Raw -ErrorAction Stop)
                } else {
                    Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{ ok = $false; error = 'recent-history.jsonl not found' })
                }
            }
            '/summary' {
                Write-JsonResponse -Response $response -StatusCode 200 -Body (Get-SummaryPayload -LatestStatePath $latestStatePath -HistoryPath $historyPath)
            }
            default {
                Write-JsonResponse -Response $response -StatusCode 404 -Body ([ordered]@{
                    ok = $false
                    error = 'Unknown route'
                    route = $path
                })
            }
        }
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
