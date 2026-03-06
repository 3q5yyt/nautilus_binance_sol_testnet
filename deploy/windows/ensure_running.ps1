$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = (Join-Path $ProjectDir ".venv\\Scripts\\python.exe").ToLower()
$MutexName = "Global\SolBotEnsureRunningMutex"

$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$hasLock = $false

try {
    $hasLock = $mutex.WaitOne(0)
    if (-not $hasLock) {
        Write-Output "Another ensure check is in progress. Skip."
        exit 0
    }

    $running = Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
        $_.ExecutablePath -and $_.CommandLine -and
        $_.ExecutablePath.ToLower() -eq $PythonExe -and
        $_.CommandLine -match "run_testnet\\.py"
    } | Sort-Object CreationDate

    $count = @($running).Count
    if ($count -eq 0) {
        & (Join-Path $PSScriptRoot "start_bot.ps1")
        Write-Output "Bot was not running. Started a new process."
        exit 0
    }

    if ($count -gt 1) {
        $keep = $running[0]
        $dups = @($running | Select-Object -Skip 1)
        foreach ($p in $dups) {
            Stop-Process -Id $p.ProcessId -Force
        }
        Write-Output ("Found {0} instances. Kept PID={1}, stopped {2} duplicate(s)." -f $count, $keep.ProcessId, @($dups).Count)
        exit 0
    }

    Write-Output ("Bot already running. PID={0}" -f $running[0].ProcessId)
}
finally {
    if ($hasLock) {
        $mutex.ReleaseMutex() | Out-Null
    }
    $mutex.Dispose()
}
