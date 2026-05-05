#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

INSTANCE="$PROJECT_DIR/instance.yaml"
if [ ! -f "$INSTANCE" ]; then
    echo "ERROR: instance.yaml not found. Run scripts/preflight-check.sh first."
    exit 1
fi

TARGET="${2:-}"

if [ "$1" = "--all" ]; then
    echo "=== Setting up all agents ==="
    AGENTS=$(python3 -c "
import yaml, glob
from pathlib import Path
agents = []
for f in sorted(glob.glob('agents/*.yaml')):
    if not Path(f).name.startswith('_'):
        data = yaml.safe_load(open(f))
        agents.append(data['role_key'])
print(' '.join(agents))
")
elif [ -n "$1" ]; then
    AGENTS=("$1")
else
    echo "Usage: $0 <role_key|--all> [--target <existing_agent>]"
    exit 1
fi

AGENTS_DIR=$(python3 -c "
import yaml
data = yaml.safe_load(open('$INSTANCE'))
print(data['openclaw']['agents_dir'])
")

# ── 备份现有 workspace（用于 rollback-agents.sh 回滚）──
BACKUP_DIR="$PROJECT_DIR/.backups/setup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
for RK in $AGENTS; do
    WS="$AGENTS_DIR/$RK/workspace"
    [ ! -d "$WS" ] && WS="$AGENTS_DIR/$RK"
    if [ -d "$WS" ]; then
        echo "备份 $RK → $BACKUP_DIR/$RK/"
        mkdir -p "$BACKUP_DIR/$RK"
        cp -r "$WS" "$BACKUP_DIR/$RK/workspace"
    fi
done
if [ "$1" = "--all" ]; then
    WS_ROOT=$(python3 -c "import yaml; print(yaml.safe_load(open('$INSTANCE'))['openclaw']['workspace_root'])")
    if [ -d "$WS_ROOT" ]; then
        mkdir -p "$BACKUP_DIR/main"
        for f in SOUL.md AGENTS.md IDENTITY.md HEARTBEAT.md TOOLS.md TEAM.md; do
            [ -f "$WS_ROOT/$f" ] && cp "$WS_ROOT/$f" "$BACKUP_DIR/main/" 2>/dev/null || true
        done
    fi
fi
echo "备份已保存: $BACKUP_DIR"

for ROLE_KEY in $AGENTS; do
    echo "--- Setting up agent: $ROLE_KEY ---"

    WORKSPACE="$AGENTS_DIR/$ROLE_KEY/workspace"
    mkdir -p "$WORKSPACE"

    if [ -n "$TARGET" ]; then
        echo "Applying $ROLE_KEY config to existing agent: $TARGET"
    else
        MODEL=$(python3 -c "
import yaml, glob
files = glob.glob('agents/${ROLE_KEY}_*.yaml')
if files:
    data = yaml.safe_load(open(files[0]))
    print(data.get('model', 'zai/glm-4.7'))
else:
    print('zai/glm-4.7')
" 2>/dev/null || echo "zai/glm-4.7")

        if command -v openclaw &>/dev/null; then
            if openclaw agents list 2>/dev/null | grep -q "$ROLE_KEY"; then
                echo "Agent $ROLE_KEY already exists, skipping creation"
            else
                openclaw agents add "$ROLE_KEY" --workspace "$WORKSPACE" --model "$MODEL" --non-interactive 2>/dev/null || \
                    echo "Note: openclaw agents add not available, workspace files will be created manually"
            fi
        fi
    fi

    python3 scripts/render-workspace.py --agent "$ROLE_KEY" --output "$AGENTS_DIR"
    echo "Agent $ROLE_KEY configured."

    # --- Setup scheduled cron tasks for this agent ---
    echo "Setting up scheduled tasks for $ROLE_KEY..."
    python3 -c "
import yaml, glob, subprocess, sys

# Find agent file
files = glob.glob('agents/${ROLE_KEY}_*.yaml')
if not files:
    sys.exit(0)
agent = yaml.safe_load(open(files[0]))

# Load assignments
asgn = yaml.safe_load(open('assignments.yaml'))
work_item_names = asgn.get('defaults', {}).get('${ROLE_KEY}', [])

# For each assigned work item, check for scheduled triggers
for wi_name in work_item_names:
    wi_path = f'work_items/{wi_name}.yaml'
    try:
        wi = yaml.safe_load(open(wi_path))
    except FileNotFoundError:
        continue

    schedule = wi.get('triggers', {}).get('scheduled')
    if not schedule:
        continue

    # Build the cron prompt that tells the agent what to do
    display_name = wi.get('display_name', wi_name)
    manual_trigger = wi.get('triggers', {}).get('manual', '')
    prompt = f'执行定时任务：{display_name}。触发命令：{manual_trigger or wi_name}'

    # Create cron job via openclaw CLI
    try:
        result = subprocess.run(
            ['openclaw', 'cron', 'add',
             '--cron', schedule,
             '--prompt', prompt,
             '--agent', '${ROLE_KEY}'],
            capture_output=True, text=True, timeout=15,
        )
        if result.returncode == 0:
            print(f'  Created cron: {display_name} ({schedule}) for ${ROLE_KEY}')
        else:
            print(f'  Warning: could not create cron for {display_name}: {result.stderr.strip()}')
    except (FileNotFoundError, subprocess.TimeoutExpired):
        print(f'  Warning: openclaw cron not available, skipping {display_name}')
" 2>/dev/null || echo "  Warning: scheduled task setup failed for $ROLE_KEY"

done

echo "=== Done ==="
