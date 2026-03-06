$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = (Join-Path $ProjectDir ".venv\\Scripts\\python.exe").ToLower()

$targets = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.ExecutablePath -and $_.CommandLine -and
    $_.ExecutablePath.ToLower() -eq $PythonExe -and
    $_.CommandLine -match "run_testnet\\.py"
}

foreach ($p in $targets) {
    Stop-Process -Id $p.ProcessId -Force
}

Write-Output ("Stopped {0} bot process(es)." -f @($targets).Count)
