$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = (Join-Path $ProjectDir ".venv\\Scripts\\python.exe").ToLower()

$running = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.ExecutablePath -and $_.CommandLine -and
    $_.ExecutablePath.ToLower() -eq $PythonExe -and
    $_.CommandLine -match "run_testnet\\.py"
}

if (@($running).Count -eq 0) {
    & (Join-Path $PSScriptRoot "start_bot.ps1")
    Write-Output "Bot was not running. Started a new process."
}
else {
    Write-Output ("Bot already running. Count={0}" -f @($running).Count)
}
