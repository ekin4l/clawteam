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

# ── Gateway 进程管理（user 级 systemd 服务）──
GW_SERVICE="openclaw-gateway.service"

find_gateway_pid() {
    pgrep -f 'openclaw.*gateway' 2>/dev/null || true
}

gateway_stop() {
    # 优先使用 systemctl --user
    if systemctl --user list-unit-files "$GW_SERVICE" &>/dev/null; then
        systemctl --user stop "$GW_SERVICE" 2>/dev/null && return
    fi
    # fallback: 直接 kill 进程
    local pid=$(find_gateway_pid)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        local waited=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 1
            waited=$((waited + 1))
            if [ "$waited" -ge 10 ]; then
                kill -9 "$pid" 2>/dev/null || true
                break
            fi
        done
    fi
}

gateway_start() {
    if systemctl --user list-unit-files "$GW_SERVICE" &>/dev/null; then
        systemctl --user start "$GW_SERVICE" 2>/dev/null && return
    fi
    # fallback: openclaw gateway start
    openclaw gateway start 2>/dev/null || true
}

gateway_restart() {
    gateway_stop
    sleep 2
    gateway_start
    sleep 3
}

# ── 检查并修复 OpenClaw 设备权限 ──
check_and_fix_scopes() {
    if ! command -v openclaw &>/dev/null; then
        return
    fi
    STATE_DIR=$(python3 -c "import yaml; print(yaml.safe_load(open('$INSTANCE'))['openclaw']['state_dir'])")
    PAIRED_FILE="$STATE_DIR/devices/paired.json"
    AUTH_FILE="$STATE_DIR/identity/device-auth.json"
    PENDING_FILE="$STATE_DIR/devices/pending.json"

    [ ! -f "$PAIRED_FILE" ] && return

    # 1. 确保文件权限正确（补齐 operator.write 等 scope）
    echo "  检查设备权限文件..."
    python3 -c "
import json, shutil, time
from pathlib import Path

WANTED = ['operator.read', 'operator.write', 'operator.admin', 'operator.approvals', 'operator.pairing']
changed = False

def merge_scopes(scopes):
    if not isinstance(scopes, list):
        scopes = []
    original = list(scopes)
    for s in WANTED:
        if s not in scopes:
            scopes.append(s)
    return scopes, scopes != original

def patch_entry(obj):
    global changed
    if not isinstance(obj, dict):
        return
    new_scopes, modified = merge_scopes(obj.get('scopes', []))
    if modified:
        obj['scopes'] = new_scopes
        changed = True
    tokens = obj.get('tokens', {})
    if isinstance(tokens, dict):
        op = tokens.get('operator', {})
        if isinstance(op, dict):
            new_scopes, modified = merge_scopes(op.get('scopes', []))
            if modified:
                op['scopes'] = new_scopes
                changed = True

for path_str in ['$PAIRED_FILE', '$AUTH_FILE']:
    path = Path(path_str)
    if not path.exists():
        continue
    data = json.loads(path.read_text())
    if isinstance(data, dict):
        if 'tokens' in data:
            patch_entry(data)
        for v in data.values():
            if isinstance(v, dict):
                patch_entry(v)
    if changed:
        backup = str(path) + f'.bak.{int(time.time())}'
        shutil.copy2(str(path), backup)
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
        print(f'  PATCHED: {path}')
    else:
        print(f'  OK: {path}')

if changed:
    # 清空 pending 请求
    pending = Path('$PENDING_FILE')
    if pending.exists():
        pending.write_text('{}')
        print('  CLEARED: pending requests')
"

    # 2. 重启 gateway（确保加载最新文件状态）
    echo "  重启 gateway..."
    gateway_restart

    # 3. 验证
    GW_NEW_PID=$(find_gateway_pid)
    if [ -n "$GW_NEW_PID" ]; then
        echo "  gateway 已重启 (PID $GW_NEW_PID) ✓"
    else
        echo "  WARNING: gateway 未检测到，可能需要手动启动: systemctl --user start $GW_SERVICE"
    fi
}
check_and_fix_scopes

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

# ── 备份现有 workspace + agent 认证（用于 rollback-agents.sh 回滚）──
BACKUP_DIR="$PROJECT_DIR/.backups/setup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
for RK in $AGENTS; do
    # 备份 workspace 文件（仅 workspace/ 子目录，不碰 sessions/ 和 agent/）
    WS="$AGENTS_DIR/$RK/workspace"
    if [ -d "$WS" ]; then
        echo "备份 $RK workspace → $BACKUP_DIR/$RK/workspace"
        mkdir -p "$BACKUP_DIR/$RK"
        cp -r "$WS" "$BACKUP_DIR/$RK/workspace"
    fi
    # 备份 agent 认证文件（auth.json, auth-profiles.json）
    AGENT_DIR="$AGENTS_DIR/$RK/agent"
    if [ -d "$AGENT_DIR" ]; then
        echo "备份 $RK 认证 → $BACKUP_DIR/$RK/agent"
        cp -r "$AGENT_DIR" "$BACKUP_DIR/$RK/agent"
    fi
done
if [ "$1" = "--all" ]; then
    WS_ROOT=$(python3 -c "import yaml; print(yaml.safe_load(open('$INSTANCE'))['openclaw']['workspace_root'])")
    if [ -d "$WS_ROOT" ]; then
        mkdir -p "$BACKUP_DIR/main"
        # 备份所有 .md 文件（包括 BOOTSTRAP.md 等）
        for f in "$WS_ROOT"/*.md; do
            [ -f "$f" ] && cp "$f" "$BACKUP_DIR/main/" 2>/dev/null || true
        done
        echo "备份 main agent workspace → $BACKUP_DIR/main"
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

    if [ -n "$TARGET" ]; then
        # --target: 将配置渲染到目标 agent 的 workspace
        TARGET_WS=$(python3 -c "
import yaml
data = yaml.safe_load(open('$INSTANCE'))
agents = data.get('agents', {}).get('existing', [])
target_agent = [a for a in agents if a['role_key'] == '$TARGET']
if target_agent:
    print(target_agent[0]['workspace'])
else:
    # fallback: 尝试 workspace_root (main agent)
    print(data['openclaw']['workspace_root'])
")
        python3 scripts/render-workspace.py --agent "$ROLE_KEY" --workspace "$TARGET_WS"
        echo "Agent $ROLE_KEY 配置已应用到 $TARGET (workspace: $TARGET_WS)"
    else
        python3 scripts/render-workspace.py --agent "$ROLE_KEY" --output "$AGENTS_DIR"
        echo "Agent $ROLE_KEY configured."
    fi

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

# Get existing cron jobs to avoid duplicates
existing_cron_names = set()
try:
    cron_list = subprocess.run(
        ['openclaw', 'cron', 'list'], capture_output=True, text=True, timeout=10,
    )
    if cron_list.returncode == 0:
        for line in cron_list.stdout.splitlines():
            if 'clawteam-' in line:
                # extract cron name from the line
                existing_cron_names.add(line.strip())
except (FileNotFoundError, subprocess.TimeoutExpired):
    pass

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

    display_name = wi.get('display_name', wi_name)
    manual_trigger = wi.get('triggers', {}).get('manual', '')
    prompt = f'执行定时任务：{display_name}。触发命令：{manual_trigger or wi_name}'
    cron_name = f'clawteam-${ROLE_KEY}-{wi_name}'

    # Skip if already exists
    if any(cron_name in c for c in existing_cron_names):
        print(f'  Cron already exists: {display_name}, skipping')
        continue

    try:
        result = subprocess.run(
            ['openclaw', 'cron', 'add',
             '--name', cron_name,
             '--cron', schedule,
             '--message', prompt,
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

    # --- 绑定消息通道（仅对外沟通的 agent）---
    COMMUNICATES=$(python3 -c "
import yaml, glob
files = glob.glob('agents/${ROLE_KEY}_*.yaml')
if files:
    data = yaml.safe_load(open(files[0]))
    print(str(data.get('communicates_externally', False)).lower())
else:
    print('false')
" 2>/dev/null || echo "false")

    if [ "$COMMUNICATES" = "true" ] && [ -z "$TARGET" ]; then
        echo "检测到 $ROLE_KEY 需要对外沟通，查找可用通道..."
        if command -v openclaw &>/dev/null; then
            # 查找已启用的通道（feishu/slack/discord 等）
            CHANNELS=$(openclaw channels list 2>/dev/null | grep -iE 'configured.*enabled|enabled.*configured' | head -5 || true)
            if [ -n "$CHANNELS" ]; then
                echo "发现通道:"
                echo "$CHANNELS" | sed 's/^/  /'
                # 提取通道名（Feishu default → feishu）
                CH_NAME=$(echo "$CHANNELS" | head -1 | grep -oiE 'feishu|slack|discord|telegram|wecom|dingtalk' || true)
                if [ -n "$CH_NAME" ]; then
                    echo "绑定通道 '$CH_NAME' 到 agent $ROLE_KEY..."
                    BIND_RESULT=$(openclaw agents bind --agent "$ROLE_KEY" --bind "$CH_NAME" 2>&1 || true)
                    echo "$BIND_RESULT"
                    # 验证绑定
                    sleep 1
                    BIND_CHECK=$(openclaw agents list --all --bindings 2>&1 | grep -A5 "$ROLE_KEY" || true)
                    if echo "$BIND_CHECK" | grep -qi "routing"; then
                        echo "通道绑定成功 ✓"
                    else
                        echo "Warning: 无法确认绑定结果，请手动检查: openclaw agents list --all --bindings"
                    fi
                else
                    echo "Warning: 未识别的通道类型，请手动绑定: openclaw agents bind --agent $ROLE_KEY --bind <channel>"
                fi
            else
                echo "Warning: 未发现已配置的通道。请先配置飞书等通道后再运行此脚本。"
            fi
        else
            echo "Warning: openclaw CLI 不可用，跳过通道绑定"
        fi
    fi

done

echo "=== Done ==="
