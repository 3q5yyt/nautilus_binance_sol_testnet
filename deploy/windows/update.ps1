param(
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = Join-Path $ProjectDir ".venv\\Scripts\\python.exe"
$GitCandidates = @(
    "C:\Program Files\Git\cmd\git.exe",
    "C:\Program Files\Git\bin\git.exe",
    "C:\ProgramData\chocolatey\bin\git.exe"
)
$GitExe = $GitCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

Set-Location $ProjectDir

if (-not (Test-Path (Join-Path $ProjectDir ".git"))) {
    throw "Not a git repository: $ProjectDir"
}
if (-not $GitExe) {
    throw "git.exe not found in common paths."
}

& $GitExe fetch --all --prune

$CurrentBranch = (& $GitExe rev-parse --abbrev-ref HEAD).Trim()
if ($CurrentBranch -ne $Branch) {
    & $GitExe checkout $Branch
}

& $GitExe pull --ff-only origin $Branch

if (-not (Test-Path $PythonExe)) {
    py -3 -m venv .venv
}

& $PythonExe -m pip install --upgrade pip
& $PythonExe -m pip install -r requirements.txt
& $PythonExe -m py_compile run_testnet.py

& (Join-Path $PSScriptRoot "stop_bot.ps1")
& (Join-Path $PSScriptRoot "ensure_running.ps1")

Write-Output "Update completed on branch '$Branch'."
