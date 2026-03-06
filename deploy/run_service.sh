#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_DIR"

if [[ ! -f ".env" ]]; then
  echo "Missing .env in $PROJECT_DIR"
  exit 1
fi

if [[ ! -d ".venv" ]]; then
  echo "Missing .venv in $PROJECT_DIR"
  exit 1
fi

source ".venv/bin/activate"
exec python run_testnet.py
