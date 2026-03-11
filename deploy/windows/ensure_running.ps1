$ErrorActionPreference = "Stop"

$MutexName = "Global\SolBotEnsureRunningMutex"
$RuntimeMutexName = "Global\SolBotRuntimeMutex"
$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$hasLock = $false

try {
    $hasLock = $mutex.WaitOne(0)
    if (-not $hasLock) {
        Write-Output "Another ensure check is in progress. Skip."
        exit 0
    }

    $runtimeMutex = New-Object System.Threading.Mutex($false, $RuntimeMutexName)
    try {
        $runtimeActive = -not $runtimeMutex.WaitOne(0)
        if (-not $runtimeActive) {
            $runtimeMutex.ReleaseMutex() | Out-Null
            & (Join-Path $PSScriptRoot "start_bot.ps1")
            Write-Output "Bot was not running. Started a new runner."
        }
        else {
            Write-Output "Bot runtime already active."
        }
    }
    finally {
        $runtimeMutex.Dispose()
    }
}
finally {
    if ($hasLock) {
        $mutex.ReleaseMutex() | Out-Null
    }
    $mutex.Dispose()
}
