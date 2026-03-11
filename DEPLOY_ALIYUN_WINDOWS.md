# Aliyun ECS Windows Deployment Guide (24/7 + Easy Updates)

This guide is for your current server type:
- Windows Server 2022 x64
- Public IP shown in your screenshot

## 1) Prepare software on ECS

Open PowerShell as Administrator and install:

```powershell
winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
winget install --id Python.Python.3.13 -e --accept-package-agreements --accept-source-agreements
```

Re-open PowerShell after install.

## 2) Clone project

```powershell
New-Item -ItemType Directory -Force C:\solbot | Out-Null
Set-Location C:\solbot
git clone <YOUR_REPO_URL> nautilus_binance_sol_testnet
Set-Location C:\solbot\nautilus_binance_sol_testnet
```

## 3) Create venv and install deps

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## 4) Configure `.env`

```powershell
Copy-Item .env.example .env
notepad .env
```

Required:
- `BINANCE_SPOT_TESTNET_API_KEY`
- `BINANCE_SPOT_TESTNET_API_SECRET`
- `BINANCE_FUTURES_TESTNET_API_KEY`
- `BINANCE_FUTURES_TESTNET_API_SECRET`

If Binance gives you an Ed25519 private key, keep it on one line with
literal `\n` escapes. Do not paste a multi-line PEM block directly into
`.env`.

Recommended:
- `BINANCE_TIMESTAMP_OFFSET_MS=-1500`
- `BINANCE_USER_WS_KEEPALIVE_SECS=1800`

Optional:
- `BINANCE_PROXY_URL=http://127.0.0.1:7890`

Before debugging `-2015 Invalid API-key, IP, or permissions`, compare the
local and ECS `.env` fingerprints:

Local:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\windows\print_env_fingerprints.ps1 -EnvPath .\.env
```

On ECS:

```powershell
powershell -ExecutionPolicy Bypass -File C:\solbot\nautilus_binance_sol_testnet\deploy\windows\print_env_fingerprints.ps1 -EnvPath C:\solbot\nautilus_binance_sol_testnet\.env
```

For the same variable, both sides must have the same `len` and the same
`sha256`.

## 5) Manual smoke test

```powershell
.\.venv\Scripts\python.exe run_testnet.py
```

If connection/auth/order flow is normal, stop with `Ctrl+C`.

## 6) Register auto-start + watchdog tasks

Use the built-in scripts in `deploy\windows`:

```powershell
Set-Location C:\solbot\nautilus_binance_sol_testnet
powershell -ExecutionPolicy Bypass -File .\deploy\windows\register_tasks.ps1
```

What it creates:
- `SolBot-Startup`: starts bot on boot
- `SolBot-Watchdog`: every minute checks and restarts bot if stopped

Start now:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\windows\ensure_running.ps1
```

## 7) Check running status

```powershell
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'run_testnet\.py' } | Select-Object ProcessId,CommandLine
Get-ScheduledTask -TaskName "SolBot-Startup","SolBot-Watchdog" | Select-Object TaskName,State
```

Logs:
- Directory: `C:\solbot\nautilus_binance_sol_testnet\logs`

## 8) Update after local `git push`

On ECS:

```powershell
Set-Location C:\solbot\nautilus_binance_sol_testnet
powershell -ExecutionPolicy Bypass -File .\deploy\windows\update.ps1 -Branch main
```

This script will:
- Pull latest code
- Install/update dependencies
- Compile-check `run_testnet.py`
- Restart bot process

## 9) Useful commands

```powershell
# Start if not running
powershell -ExecutionPolicy Bypass -File .\deploy\windows\ensure_running.ps1

# Stop bot process
powershell -ExecutionPolicy Bypass -File .\deploy\windows\stop_bot.ps1

# Force update + restart
powershell -ExecutionPolicy Bypass -File .\deploy\windows\update.ps1 -Branch main

# Remove tasks (if needed)
schtasks /Delete /TN "SolBot-Startup" /F
schtasks /Delete /TN "SolBot-Watchdog" /F
```
