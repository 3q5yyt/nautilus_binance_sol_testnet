$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = (Join-Path $ProjectDir ".venv\\Scripts\\python.exe").ToLower()
$RunnerScript = (Join-Path $PSScriptRoot "bot_runner.ps1").ToLower()

$pythonTargets = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.ExecutablePath -and $_.CommandLine -and
    $_.ExecutablePath.ToLower() -eq $PythonExe -and
    $_.CommandLine -match "run_testnet\\.py"
}

$runnerTargets = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
    $_.CommandLine -and $_.CommandLine.ToLower().Contains($RunnerScript)
}

foreach ($p in @($pythonTargets) + @($runnerTargets)) {
    Stop-Process -Id $p.ProcessId -Force
}

Write-Output ("Stopped {0} process(es)." -f (@($pythonTargets).Count + @($runnerTargets).Count))
