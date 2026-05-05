#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

ROLE_KEY="${1:-}"
if [ -z "$ROLE_KEY" ]; then
    echo "Usage: $0 <role_key>"
    exit 1
fi

read -rp "Export memory for $ROLE_KEY before removing? [Y/n] " EXPORT
if [[ "$EXPORT" =~ ^[Nn] ]]; then
    echo "Skipping memory export."
else
    bash scripts/export-memory.sh "$ROLE_KEY"
fi

if command -v openclaw &>/dev/null; then
    openclaw agents delete "$ROLE_KEY" 2>/dev/null || echo "Note: agent not found in OpenClaw"
fi

echo "Agent $ROLE_KEY removed from OpenClaw."
echo "YAML definition kept in agents/ directory."
