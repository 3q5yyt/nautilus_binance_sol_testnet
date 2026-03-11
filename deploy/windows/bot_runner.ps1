$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = Join-Path $ProjectDir ".venv\\Scripts\\python.exe"
$Entrypoint = Join-Path $ProjectDir "run_testnet.py"
$EnvFile = Join-Path $ProjectDir ".env"
$LogDir = Join-Path $ProjectDir "logs"
$MutexName = "Global\SolBotRuntimeMutex"

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

$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$hasLock = $false

try {
    $hasLock = $mutex.WaitOne(0)
    if (-not $hasLock) {
        Write-Output "Bot runtime already active. Skip launch."
        exit 0
    }

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $stdoutLog = Join-Path $LogDir "bot_$ts.stdout.log"
    $stderrLog = Join-Path $LogDir "bot_$ts.stderr.log"

    $proc = Start-Process `
        -FilePath $PythonExe `
        -ArgumentList "run_testnet.py" `
        -WorkingDirectory $ProjectDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru

    Wait-Process -Id $proc.Id
}
finally {
    if ($hasLock) {
        $mutex.ReleaseMutex() | Out-Null
    }
    $mutex.Dispose()
}
