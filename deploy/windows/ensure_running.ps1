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

function Stop-BotTargets {
    $pythonTargets = @(Get-PythonTargets)
    $runnerTargets = @(Get-RunnerTargets)
    foreach ($p in @($pythonTargets) + @($runnerTargets)) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    return @{
        Python = $pythonTargets.Count
        Runner = $runnerTargets.Count
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
            $pythonTargets = @(Get-PythonTargets)
            $runnerTargets = @(Get-RunnerTargets)

            if ($pythonTargets.Count -eq 1 -and $runnerTargets.Count -eq 1) {
                Write-Output ("Bot runtime healthy. Runner={0}, Python={1}" -f $runnerTargets[0].ProcessId, $pythonTargets[0].ProcessId)
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
