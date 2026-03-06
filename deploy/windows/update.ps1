param(
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = Join-Path $ProjectDir ".venv\\Scripts\\python.exe"

Set-Location $ProjectDir

if (-not (Test-Path (Join-Path $ProjectDir ".git"))) {
    throw "Not a git repository: $ProjectDir"
}

git fetch --all --prune

$CurrentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($CurrentBranch -ne $Branch) {
    git checkout $Branch
}

git pull --ff-only origin $Branch

if (-not (Test-Path $PythonExe)) {
    py -3 -m venv .venv
}

& $PythonExe -m pip install --upgrade pip
& $PythonExe -m pip install -r requirements.txt
& $PythonExe -m py_compile run_testnet.py

& (Join-Path $PSScriptRoot "stop_bot.ps1")
& (Join-Path $PSScriptRoot "ensure_running.ps1")

Write-Output "Update completed on branch '$Branch'."
