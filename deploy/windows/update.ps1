param(
    [string]$Branch = "main",
    [string]$RepoZipUrl = "https://codeload.github.com/3q5yyt/nautilus_binance_sol_testnet/zip/refs/heads/main"
)

$ErrorActionPreference = "Stop"

$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
$PythonExe = Join-Path $ProjectDir ".venv\\Scripts\\python.exe"
$TempBase = Join-Path $env:TEMP "solbot_update"
$ZipPath = Join-Path $TempBase "repo.zip"
$ExtractRoot = Join-Path $TempBase "extract"
$HasGitRepo = Test-Path (Join-Path $ProjectDir ".git")
$GitCandidates = @(
    "C:\Program Files\Git\cmd\git.exe",
    "C:\Program Files\Git\bin\git.exe",
    "C:\ProgramData\chocolatey\bin\git.exe"
)
$GitExe = $GitCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

Set-Location $ProjectDir

if ($HasGitRepo -and -not $GitExe) {
    throw "git.exe not found in common paths."
}

if ($HasGitRepo) {
    & $GitExe fetch --all --prune

    $CurrentBranch = (& $GitExe rev-parse --abbrev-ref HEAD).Trim()
    if ($CurrentBranch -ne $Branch) {
        & $GitExe checkout $Branch
    }

    & $GitExe pull --ff-only origin $Branch
}
else {
    if (Test-Path $TempBase) {
        Remove-Item -Recurse -Force $TempBase
    }
    New-Item -ItemType Directory -Force $TempBase | Out-Null

    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $ZipPath -TimeoutSec 180
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractRoot -Force

    $SourceDir = (Get-ChildItem $ExtractRoot -Directory | Select-Object -First 1).FullName
    if (-not $SourceDir) {
        throw "Could not locate extracted source directory."
    }

    & (Join-Path $PSScriptRoot "stop_bot.ps1")

    robocopy $SourceDir $ProjectDir /E /R:1 /W:1 /XD .git .venv logs __pycache__ /XF .env | Out-Null
    $RoboCode = $LASTEXITCODE
    if ($RoboCode -ge 8) {
        throw "robocopy failed with exit code $RoboCode"
    }
}

if (-not (Test-Path $PythonExe)) {
    py -3 -m venv .venv
}

& $PythonExe -m pip install --upgrade pip
& $PythonExe -m pip install -r requirements.txt
& $PythonExe -m py_compile run_testnet.py

& (Join-Path $PSScriptRoot "stop_bot.ps1")
& (Join-Path $PSScriptRoot "ensure_running.ps1")

Write-Output "Update completed on branch '$Branch'."
