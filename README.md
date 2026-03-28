# BarCode

BarCode is the narrow-scope, reliability-first RIFT telemetry bridge in this repo.

Current product shape:
- monochrome machine-readable top strip
- player + current target only
- compact HUD-style stats
- reader correctness and reject-safety over bandwidth

RIFT loads this addon from:
`C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode`

Desktop reader/runtime artifacts are written under:
`C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK`

## Preferred Operator Path

Use the PowerShell wrapper, not raw `AutoHotkey64.exe`, for routine checks. The wrapper prints the fresh run summary, guards against stale artifacts, and archives each run.

Smoke test:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode\scripts\Run-BarCode.ps1 -Mode smoke
```

Show the latest compact summary:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode\scripts\Run-BarCode.ps1 -Mode summary
```

Short live watch against the running RIFT client:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode\scripts\Run-BarCode.ps1 -Mode watch 10 100
```

Longer live soak:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode\scripts\Run-BarCode.ps1 -Mode watch 60 100
```

Compact HUD preview:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode\scripts\Run-BarCode.ps1 -Mode hud 300
```

## Offline Screenshot Checks

The wrapper can now resolve the newest screenshot in:
`C:\Users\mrkoo\OneDrive\Documents\RIFT\Screenshots`

If the newest file is not a BMP, it is converted into:
`C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\out\input-cache`

Decode the newest screenshot directly:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode\scripts\Run-BarCode.ps1 -Mode bmp-latest
```

Open the compact HUD against the newest screenshot:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode\scripts\Run-BarCode.ps1 -Mode hudbmp-latest 0 0 300
```

Open the full dashboard against the newest screenshot:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode\scripts\Run-BarCode.ps1 -Mode uibmp-latest 0 0 300
```

Notes:
- `bmp-latest` only guarantees “newest screenshot”, not “newest decodable screenshot”.
- If the newest screenshot does not contain a readable BarCode strip, the wrapper fails cleanly and prints the reader error.

## Useful Output Files

Fresh run/report output:
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\out\latest-run.txt`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\out\phase2-reader-smoke.txt`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\out\phase2-watch.txt`

Latest state/summary output:
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-summary.txt`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-summary.json`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-state.txt`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-state.json`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\recent-history.json`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\recent-history.jsonl`

Archived wrapper runs:
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\out\archive`
