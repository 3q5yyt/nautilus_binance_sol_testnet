#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${1:-main}"
SERVICE_NAME="${2:-solbot.service}"

cd "$PROJECT_DIR"

if [[ ! -d ".git" ]]; then
  echo "Current directory is not a git repository: $PROJECT_DIR"
  echo "Initialize git and set origin first."
  exit 1
fi

git fetch --all --prune

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  git checkout "$BRANCH"
fi

git pull --ff-only origin "$BRANCH"

if [[ ! -d ".venv" ]]; then
  python3 -m venv .venv
fi

source ".venv/bin/activate"
python -m pip install --upgrade pip
pip install -r requirements.txt
python -m py_compile run_testnet.py

chmod +x deploy/run_service.sh

if systemctl list-unit-files --type=service --no-legend | awk '{print $1}' | grep -qx "$SERVICE_NAME"; then
  sudo systemctl daemon-reload
  sudo systemctl restart "$SERVICE_NAME"
  sudo systemctl --no-pager --full status "$SERVICE_NAME" | sed -n '1,25p'
else
  echo "Service $SERVICE_NAME not found. Skip restart."
fi
