# Binance Spot + USDT Futures Testnet Auto Trader (SOLUSDT)

This project provides a minimal NautilusTrader live node with:

- One spot strategy on `SOLUSDT.BINANCE_SPOT` (long-only).
- One USDT futures strategy on `SOLUSDT-PERP.BINANCE_FUTURES` (long/short).
- Shared risk model:
  - Per-trade risk: `0.5%`
  - Stop-loss: `1.2%`
  - Take-profit: `2.4%`
  - Daily realized loss limit: `3%`
- Futures initial leverage target: `50x` for `SOLUSDT` (exchange may cap it).

## 1) Environment

Use Python 3.12+.

```powershell
cd nautilus_binance_sol_testnet
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## 2) Configure credentials

```powershell
Copy-Item .env.example .env
```

Fill `.env` with Binance testnet API keys:

- `BINANCE_SPOT_TESTNET_API_KEY`
- `BINANCE_SPOT_TESTNET_API_SECRET`
- `BINANCE_FUTURES_TESTNET_API_KEY`
- `BINANCE_FUTURES_TESTNET_API_SECRET`

If Binance gives you an Ed25519 private key, keep it as a single line with
literal `\n` escapes inside `.env`. Do not paste a raw multi-line PEM block.

If you hit Binance `-1021` timestamp errors, set:

- `BINANCE_TIMESTAMP_OFFSET_MS=-1500`

If needed, you can tune user stream keepalive interval:

- `BINANCE_USER_WS_KEEPALIVE_SECS=1800` (default)

If your network path to Binance is unstable, you can set:

- `BINANCE_PROXY_URL=http://127.0.0.1:7890`

Before debugging `-2015 Invalid API-key, IP, or permissions`, print the
credential fingerprints and compare local vs server:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\windows\print_env_fingerprints.ps1 -EnvPath .\.env
```

For the same variable, both sides must have the same `len` and the same
`sha256`.

## 3) Run

```powershell
python run_testnet.py
```

Stop with `Ctrl+C`.

## 4) Cloud deployment

For 24/7 ECS deployment (systemd + one-command update), see:

- `DEPLOY_ALIYUN.md`

For Windows ECS deployment (Task Scheduler watchdog + one-command update), see:

- `DEPLOY_ALIYUN_WINDOWS.md`

## Strategy logic summary

- Signal: EMA(9/21) trend.
- Position sizing:
  - By risk budget: `capital * risk_per_trade / (entry * stop_loss_pct)`.
  - Capped by max notional: `capital * leverage_cap`.
- Exit conditions:
  - Stop-loss / take-profit hit.
  - EMA reversal.
  - Daily realized loss limit reached (halts new entries for the day).

## Important notes

- This is for **TESTNET** only.
- Spot shorting is disabled (no margin logic).
- Futures margin type is set to `ISOLATED`.
- Before switching to live funds, run at least several days in testnet and verify:
  - fills/slippage,
  - stop behavior,
  - leverage and margin updates,
  - reconnection/reconciliation logs.
