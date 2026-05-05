#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

ROLE_KEY="${1:-}"
OUTPUT="${2:-}"

if [ -z "$ROLE_KEY" ]; then
    echo "Usage: $0 <role_key|--all> [output_path]"
    exit 1
fi

if [ "$ROLE_KEY" = "--all" ]; then
    ROLE_KEYS="assistant architect quality ops tester"
else
    ROLE_KEYS="$ROLE_KEY"
fi

INSTANCE="$PROJECT_DIR/instance.yaml"
if [ ! -f "$INSTANCE" ]; then
    echo "ERROR: instance.yaml not found. Run preflight-check.sh first."
    exit 1
fi

AGENTS_DIR=$(python3 -c "import yaml; print(yaml.safe_load(open('$INSTANCE'))['openclaw']['agents_dir'])")

for RK in $ROLE_KEYS; do
    WORKSPACE="$AGENTS_DIR/$RK/workspace"
    [ ! -d "$WORKSPACE" ] && WORKSPACE="$AGENTS_DIR/$RK"
    [ ! -d "$WORKSPACE" ] && { echo "Warning: workspace for $RK not found, skipping"; continue; }

    if [ -n "$OUTPUT" ] && [[ "$OUTPUT" == *.tar.gz ]]; then
        python3 -c "
import sys; sys.path.insert(0, 'src')
from pathlib import Path
from clawteam_glm.memory import export_memory
export_memory(Path('$WORKSPACE'), archive_path=Path('$OUTPUT'))
print('Exported $RK to $OUTPUT')
"
    else
        BACKUP="${OUTPUT:-memories}/$RK"
        python3 -c "
import sys; sys.path.insert(0, 'src')
from pathlib import Path
from clawteam_glm.memory import export_memory
export_memory(Path('$WORKSPACE'), backup_dir=Path('$BACKUP'))
print('Exported $RK to $BACKUP')
"
    fi
done
