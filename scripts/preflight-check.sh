#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== OpenClaw Instance Preflight Check ==="

if ! command -v openclaw &>/dev/null; then
    echo "ERROR: openclaw CLI not found in PATH"
    exit 1
fi

VERSION=$(openclaw --version 2>&1 | head -1)
echo "OpenClaw version: $VERSION"

python3 -c "
import sys
sys.path.insert(0, '$PROJECT_DIR/src')
from pathlib import Path
from clawteam_glm.detector import detect_instance
try:
    info = detect_instance(output_path=Path('$PROJECT_DIR/instance.yaml'))
    print(f'Detected: OpenClaw {info.version} ({info.variant})')
    print(f'State dir: {info.state_dir}')
    print(f'Workspace: {info.workspace_root}')
    print(f'Agents dir: {info.agents_dir}')
    print(f'Existing agents: {len(info.existing_agents)}')
    print(f'Instance config written to: $PROJECT_DIR/instance.yaml')
except RuntimeError as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"
