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

# ── 检查并修复 OpenClaw 设备权限（方案二：重建 CLI 身份）──
check_and_fix_scopes() {
    if ! command -v openclaw &>/dev/null; then
        return
    fi
    STATE_DIR=$(python3 -c "import yaml; print(yaml.safe_load(open('$INSTANCE'))['openclaw']['state_dir'])")
    IDENTITY_DIR="$STATE_DIR/identity"
    PAIRED_FILE="$STATE_DIR/devices/paired.json"
    AUTH_FILE="$IDENTITY_DIR/device-auth.json"
    DEVICE_FILE="$IDENTITY_DIR/device.json"
    PENDING_FILE="$STATE_DIR/devices/pending.json"

    [ ! -f "$PAIRED_FILE" ] && return

    # 先快速测试：如果 cron list 能用，说明权限正常
    if openclaw cron list &>/dev/null; then
        return
    fi

    echo "⚠ 设备权限不足，执行身份重建..."

    # 1. 停止 gateway
    echo "  停止 gateway..."
    gateway_stop
    sleep 2

    # 2. 备份旧身份文件
    BACKUP_DIR="$STATE_DIR/identity_bak_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    [ -f "$DEVICE_FILE" ] && cp -a "$DEVICE_FILE" "$BACKUP_DIR/"
    [ -f "$AUTH_FILE" ] && cp -a "$AUTH_FILE" "$BACKUP_DIR/"
    echo "  旧身份备份到: $BACKUP_DIR"

    # 3. 删除旧身份，让 CLI 重新生成
    rm -f "$DEVICE_FILE" "$AUTH_FILE"
    echo "  旧身份已移除"

    # 4. 清空 pending 请求
    [ -f "$PENDING_FILE" ] && echo '{}' > "$PENDING_FILE"

    # 5. 启动 gateway
    echo "  启动 gateway..."
    gateway_start

    # 6. 触发新身份生成（openclaw devices list 会自动生成）
    sleep 3
    DEVICES_OUTPUT=$(openclaw devices list 2>&1 || true)
    echo "$DEVICES_OUTPUT" | head -5

    # 7. 尝试 approve 新请求
    NEW_REQUEST=$(echo "$DEVICES_OUTPUT" | grep -oP '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1 || true)
    if [ -n "$NEW_REQUEST" ]; then
        echo "  尝试批准新请求: $NEW_REQUEST"
        openclaw devices approve "$NEW_REQUEST" 2>/dev/null && echo "  批准成功 ✓" || {
            echo "  approve 失败，执行方案一（离线补丁）..."

            # 方案一 fallback：停止 gateway，补齐新身份文件的 scopes，重启
            gateway_stop
            sleep 2

            python3 -c "
import json, shutil, time
from pathlib import Path

WANTED = ['operator.read', 'operator.write', 'operator.admin', 'operator.approvals', 'operator.pairing']

def merge_scopes(scopes):
    if not isinstance(scopes, list):
        scopes = []
    for s in WANTED:
        if s not in scopes:
            scopes.append(s)
    return scopes

def patch_entry(obj):
    if not isinstance(obj, dict):
        return
    obj['scopes'] = merge_scopes(obj.get('scopes'))
    tokens = obj.get('tokens', {})
    if isinstance(tokens, dict):
        op = tokens.get('operator', {})
        if isinstance(op, dict):
            op['scopes'] = merge_scopes(op.get('scopes'))

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
    backup = str(path) + f'.bak.{int(time.time())}'
    shutil.copy2(str(path), backup)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    print(f'  PATCHED: {path}')

pending = Path('$PENDING_FILE')
if pending.exists():
    pending.write_text('{}')
"
            echo "  离线补丁完成"
            gateway_start
        }
    fi

    # 8. 验证
    sleep 2
    GW_NEW_PID=$(find_gateway_pid)
    if [ -n "$GW_NEW_PID" ]; then
        echo "  gateway 运行中 (PID $GW_NEW_PID) ✓"
    else
        echo "  WARNING: gateway 未检测到"
    fi

    # 9. 最终验证 cron 权限
    if openclaw cron list &>/dev/null; then
        echo "  cron 权限验证通过 ✓"
    else
        echo "  WARNING: cron 权限仍不可用，请手动检查: openclaw devices list"
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

    # --- 同步定时任务（委托给 manage-workitems.sh）---
    echo "Syncing scheduled tasks for $ROLE_KEY..."
    bash "$SCRIPT_DIR/manage-workitems.sh" sync-cron --agent "$ROLE_KEY"

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
