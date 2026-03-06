# Aliyun ECS Deployment Guide (24/7 + Easy Updates)

This guide targets Ubuntu 22.04/24.04 and assumes server user `ubuntu`.

## 1) Put this project in a Git remote (required for easy updates)

Run on your local machine:

```bash
cd nautilus_binance_sol_testnet
git init
git add .
git commit -m "init: nautilus binance testnet bot"
git branch -M main
git remote add origin <YOUR_REPO_URL>
git push -u origin main
```

Notes:
- `.env` is ignored by `.gitignore`.
- Later, after local changes, just `git push` and update on server with one command.

## 2) Login to ECS and install dependencies

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip
```

## 3) Clone project to server

```bash
sudo mkdir -p /opt/solbot
sudo chown -R $USER:$USER /opt/solbot
cd /opt/solbot
git clone <YOUR_REPO_URL> nautilus_binance_sol_testnet
cd nautilus_binance_sol_testnet
```

## 4) Create venv and install Python packages

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## 5) Create and fill `.env`

```bash
cp .env.example .env
nano .env
```

Required:
- `BINANCE_SPOT_TESTNET_API_KEY`
- `BINANCE_SPOT_TESTNET_API_SECRET`
- `BINANCE_FUTURES_TESTNET_API_KEY`
- `BINANCE_FUTURES_TESTNET_API_SECRET`

Recommended:
- `BINANCE_TIMESTAMP_OFFSET_MS=-1500`
- `BINANCE_USER_WS_KEEPALIVE_SECS=1800`

Optional for unstable network path:
- `BINANCE_PROXY_URL=http://127.0.0.1:7890`

## 6) Manual smoke test

```bash
source .venv/bin/activate
python run_testnet.py
```

After connection is confirmed, stop with `Ctrl+C`.

## 7) Install as systemd service

Make scripts executable:

```bash
chmod +x deploy/run_service.sh
chmod +x deploy/update.sh
```

Install service file:

```bash
sudo cp deploy/solbot.service /etc/systemd/system/solbot.service
```

If your username/path differs, edit service file:

```bash
sudo nano /etc/systemd/system/solbot.service
```

Check these fields:
- `User=ubuntu`
- `WorkingDirectory=/opt/solbot/nautilus_binance_sol_testnet`
- `ExecStart=/opt/solbot/nautilus_binance_sol_testnet/deploy/run_service.sh`

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable solbot.service
sudo systemctl start solbot.service
sudo systemctl status solbot.service --no-pager -l
```

Live logs:

```bash
journalctl -u solbot.service -f
```

## 8) Update flow (recommended)

After you push changes from local machine:

```bash
cd /opt/solbot/nautilus_binance_sol_testnet
./deploy/update.sh main solbot.service
```

This script will:
- Pull latest code
- Install/update dependencies
- Run `py_compile` check
- Restart `solbot.service`

## 9) Useful operations

```bash
sudo systemctl restart solbot.service
sudo systemctl stop solbot.service
sudo systemctl start solbot.service
sudo systemctl status solbot.service --no-pager -l
journalctl -u solbot.service -n 200 --no-pager
```
