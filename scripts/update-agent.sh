#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

if [ "${1:-}" = "--all" ]; then
    python3 scripts/render-workspace.py --all
elif [ -n "${1:-}" ]; then
    python3 scripts/render-workspace.py --agent "$1"
else
    echo "Usage: $0 <role_key|--all> [--target <existing_agent>]"
    exit 1
fi
