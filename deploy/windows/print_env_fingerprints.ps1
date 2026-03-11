param(
    [string]$EnvPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path ".env"),
    [string[]]$Keys = @(
        "BINANCE_SPOT_TESTNET_API_KEY",
        "BINANCE_SPOT_TESTNET_API_SECRET",
        "BINANCE_FUTURES_TESTNET_API_KEY",
        "BINANCE_FUTURES_TESTNET_API_SECRET"
    ),
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $EnvPath)) {
    throw "Env file not found: $EnvPath"
}

$map = @{}
Get-Content $EnvPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
        return
    }

    $idx = $line.IndexOf("=")
    if ($idx -lt 1) {
        return
    }

    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1)

    if ($value.Length -ge 2) {
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }

    $map[$name] = $value
}

$results = foreach ($key in $Keys) {
    $value = if ($map.ContainsKey($key)) { [string]$map[$key] } else { "" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    [pscustomobject]@{
        Name = $key
        Present = $map.ContainsKey($key)
        Length = $value.Length
        SHA256 = (-join ($hashBytes | ForEach-Object { $_.ToString("x2") }))
    }
}

if ($AsJson) {
    $results | ConvertTo-Json -Depth 3
    exit 0
}

foreach ($item in $results) {
    Write-Output $item.Name
    Write-Output ("  len={0}" -f $item.Length)
    Write-Output ("  sha256={0}" -f $item.SHA256)
}
