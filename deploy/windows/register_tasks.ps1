$ErrorActionPreference = "Stop"

$EnsureScript = (Resolve-Path (Join-Path $PSScriptRoot "ensure_running.ps1")).Path
$TaskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$EnsureScript`""

schtasks /Create /TN "SolBot-Startup" /SC ONSTART /TR "$TaskCommand" /RU SYSTEM /RL HIGHEST /F | Out-Null
schtasks /Create /TN "SolBot-Watchdog" /SC MINUTE /MO 1 /TR "$TaskCommand" /RU SYSTEM /RL HIGHEST /F | Out-Null

Write-Output "Registered tasks: SolBot-Startup, SolBot-Watchdog"
