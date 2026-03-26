# BarCode

RIFT loads this addon from this folder:
`C:\Users\mrkoo\OneDrive\Documents\RIFT\Interface\AddOns\BarCode`

Desktop AHK runtime artifacts are written to:
`C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK`

Common local checks:

```powershell
.\scripts\Run-AhkValidate.cmd -ScriptPath .\DesktopAHK\Main.ahk
.\scripts\Run-AhkScript.cmd -ScriptPath .\DesktopAHK\Main.ahk smoke
.\scripts\Verify-Reader.cmd -SkipLive
.\scripts\Verify-Reader.cmd -LiveIterations 3 -LiveSamples 10 -LiveSleepMs 100
```

Live data watch:

```powershell
.\scripts\Run-AhkScript.cmd -ScriptPath .\DesktopAHK\Main.ahk watch 10 100
.\scripts\Watch-LiveState.cmd -DurationSeconds 10 -ReaderSleepMs 100
.\scripts\Soak-LiveReader.cmd -DurationSeconds 60 -ReaderSleepMs 100
```

Latest live-state artifacts:

- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-state.json`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\latest-state.txt`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\recent-history.json`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\state\recent-history.jsonl`
- `C:\Users\mrkoo\AppData\Local\BarCode\DesktopAHK\out\phase2-watch.txt`
