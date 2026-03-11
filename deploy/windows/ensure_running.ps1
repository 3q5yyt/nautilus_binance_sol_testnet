$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = (Join-Path $ProjectDir ".venv\\Scripts\\python.exe").ToLower()
$RunnerScript = (Join-Path $PSScriptRoot "bot_runner.ps1").ToLower()
$MutexName = "Global\SolBotEnsureRunningMutex"
$RuntimeMutexName = "Global\SolBotRuntimeMutex"
$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$hasLock = $false

function Get-PythonTargets {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
        $_.CommandLine -and
        $_.CommandLine.ToLower().Contains($PythonExe) -and
        $_.CommandLine -match '(?i)\brun_testnet\.py\b'
    }
}

function Get-RunnerTargets {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.ToLower().Contains($RunnerScript)
    }
}

function Get-BotSnapshot {
    $pythonTargets = @(Get-PythonTargets | Sort-Object ProcessId)
    $runnerTargets = @(Get-RunnerTargets | Sort-Object ProcessId)

    $pythonIds = @{}
    $runnerIds = @{}

    foreach ($p in $pythonTargets) {
        $pythonIds[$p.ProcessId] = $true
    }
    foreach ($p in $runnerTargets) {
        $runnerIds[$p.ProcessId] = $true
    }

    $rootPythonTargets = @($pythonTargets | Where-Object {
        -not $pythonIds.ContainsKey($_.ParentProcessId) -and
        -not $runnerIds.ContainsKey($_.ParentProcessId)
    } | Sort-Object ProcessId)

    $healthy = (
        $runnerTargets.Count -eq 1 -and
        $rootPythonTargets.Count -eq 0 -and
        $pythonTargets.Count -ge 1 -and
        $pythonTargets.Count -le 2
    )

    return @{
        Python = $pythonTargets
        Runner = $runnerTargets
        RootPython = $rootPythonTargets
        Healthy = $healthy
    }
}

function Stop-BotTargets {
    $snapshot = Get-BotSnapshot
    $rootTargets = @($snapshot.Runner + $snapshot.RootPython | Sort-Object ProcessId -Unique)

    foreach ($p in $rootTargets) {
        taskkill /PID $p.ProcessId /T /F | Out-Null
    }

    Start-Sleep -Seconds 2

    return @{
        Python = $snapshot.Python.Count
        Runner = $snapshot.Runner.Count
    }
}

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

            $stopped = Stop-BotTargets
            & (Join-Path $PSScriptRoot "start_bot.ps1")
            Write-Output ("Bot was not running. Cleaned python={0}, runner={1}, then started a new runner." -f $stopped.Python, $stopped.Runner)
        }
        else {
            $snapshot = Get-BotSnapshot

            if ($snapshot.Healthy) {
                Write-Output ("Bot runtime healthy. Runner={0}, PythonCount={1}" -f $snapshot.Runner[0].ProcessId, $snapshot.Python.Count)
            }
            else {
                $stopped = Stop-BotTargets
                & (Join-Path $PSScriptRoot "start_bot.ps1")
                Write-Output ("Bot runtime was inconsistent. Cleaned python={0}, runner={1}, then started a new runner." -f $stopped.Python, $stopped.Runner)
            }
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
