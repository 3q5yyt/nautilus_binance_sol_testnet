$ErrorActionPreference = "Stop"

$RunnerScript = (Resolve-Path (Join-Path $PSScriptRoot "bot_runner.ps1")).Path
$PowerShellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

if (-not (Test-Path $RunnerScript)) {
    throw "Missing runner script: $RunnerScript"
}
if (-not (Test-Path $PowerShellExe)) {
    throw "Missing PowerShell executable: $PowerShellExe"
}

Start-Process `
    -FilePath $PowerShellExe `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $RunnerScript) `
    -WindowStyle Hidden

Write-Output "Bot runner launch requested."
