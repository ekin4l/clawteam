#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

ROLE_KEY="${1:-}"
INPUT="${2:-}"
FORCE=""

if [ -z "$ROLE_KEY" ] || [ -z "$INPUT" ]; then
    echo "Usage: $0 <role_key> <input_path> [--force]"
    exit 1
fi

[ "${3:-}" = "--force" ] && FORCE="--force"

INSTANCE="$PROJECT_DIR/instance.yaml"
if [ ! -f "$INSTANCE" ]; then
    echo "ERROR: instance.yaml not found. Run preflight-check.sh first."
    exit 1
fi

AGENTS_DIR=$(python3 -c "import yaml; print(yaml.safe_load(open('$INSTANCE'))['openclaw']['agents_dir'])")
WORKSPACE="$AGENTS_DIR/$ROLE_KEY/workspace"
[ ! -d "$WORKSPACE" ] && WORKSPACE="$AGENTS_DIR/$ROLE_KEY"

if [ "$FORCE" = "--force" ]; then
    python3 -c "
import sys; sys.path.insert(0, 'src')
from pathlib import Path
from clawteam_glm.memory import import_memory
import_memory(Path('$INPUT'), Path('$WORKSPACE'), force=True)
print('Imported memory to $ROLE_KEY (force)')
"
else
    python3 -c "
import sys; sys.path.insert(0, 'src')
from pathlib import Path
from clawteam_glm.memory import import_memory
import_memory(Path('$INPUT'), Path('$WORKSPACE'))
print('Imported memory to $ROLE_KEY')
"
fi
