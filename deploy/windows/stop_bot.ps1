$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = (Join-Path $ProjectDir ".venv\\Scripts\\python.exe").ToLower()
$RunnerScript = (Join-Path $PSScriptRoot "bot_runner.ps1").ToLower()

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

function Get-RootTargets {
    $pythonTargets = @(Get-PythonTargets)
    $runnerTargets = @(Get-RunnerTargets)

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
    })

    $rootTargets = @($runnerTargets + $rootPythonTargets | Sort-Object ProcessId -Unique)

    return @{
        Python = $pythonTargets
        Runner = $runnerTargets
        Roots = $rootTargets
    }
}

$snapshot = Get-RootTargets

foreach ($p in $snapshot.Roots) {
    taskkill /PID $p.ProcessId /T /F | Out-Null
}

Start-Sleep -Seconds 2

Write-Output ("Stopped {0} process(es)." -f (@($snapshot.Python).Count + @($snapshot.Runner).Count))
