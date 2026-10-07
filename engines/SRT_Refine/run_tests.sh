#!/bin/bash
# run_tests.sh — SRT_Refine unit tests
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PYTHON="${ROOT}/venv/bin/python"

if [[ ! -x "$PYTHON" ]]; then
    echo "❌ venv chưa có — chạy: python3 -m venv venv && venv/bin/pip install -r requirements.txt"
    exit 1
fi

cd "$ROOT"
"$PYTHON" -m unittest discover -s tests -v
echo "✅ SRT_Refine tests OK"