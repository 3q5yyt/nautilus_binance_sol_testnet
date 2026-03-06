$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = Join-Path $ProjectDir ".venv\\Scripts\\python.exe"
$PythonExeNorm = $PythonExe.ToLower()
$Entrypoint = Join-Path $ProjectDir "run_testnet.py"
$EnvFile = Join-Path $ProjectDir ".env"
$LogDir = Join-Path $ProjectDir "logs"

if (-not (Test-Path $PythonExe)) {
    throw "Missing Python executable: $PythonExe"
}
if (-not (Test-Path $Entrypoint)) {
    throw "Missing entrypoint: $Entrypoint"
}
if (-not (Test-Path $EnvFile)) {
    throw "Missing .env file: $EnvFile"
}

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$running = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.ExecutablePath -and $_.CommandLine -and
    $_.ExecutablePath.ToLower() -eq $PythonExeNorm -and
    $_.CommandLine -match "run_testnet\\.py"
}
if (@($running).Count -gt 0) {
    Write-Output ("Bot already running. Count={0}. Skip start." -f @($running).Count)
    exit 0
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$stdoutLog = Join-Path $LogDir "bot_$ts.stdout.log"
$stderrLog = Join-Path $LogDir "bot_$ts.stderr.log"

Start-Process `
    -FilePath $PythonExe `
    -ArgumentList "run_testnet.py" `
    -WorkingDirectory $ProjectDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
