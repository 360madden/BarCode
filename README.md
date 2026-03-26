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
