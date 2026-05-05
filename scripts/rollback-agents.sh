#!/usr/bin/env bash
# 回滚 OpenClaw agent 配置到 setup 前的状态
# 用法: bash scripts/rollback-agents.sh [--all | role_key]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

INSTANCE="$PROJECT_DIR/instance.yaml"
if [ ! -f "$INSTANCE" ]; then
    echo "ERROR: instance.yaml 不存在，无法确定 agent 路径"
    exit 1
fi

# 从 instance.yaml 读取路径
AGENTS_DIR=$(python3 -c "
import yaml
data = yaml.safe_load(open('$INSTANCE'))
print(data['openclaw']['agents_dir'])
")

WORKSPACE_ROOT=$(python3 -c "
import yaml
data = yaml.safe_load(open('$INSTANCE'))
print(data['openclaw']['workspace_root'])
")

BACKUP_DIR="$PROJECT_DIR/.backups"
LATEST_BACKUP=$(ls -dt "$BACKUP_DIR"/setup-* 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "ERROR: 未找到备份。setup-agents.sh 运行前会自动备份。"
    exit 1
fi

echo "=== 回滚 OpenClaw Agent 配置 ==="
echo "备份目录: $LATEST_BACKUP"

if [ "${1:-}" = "--all" ]; then
    TARGETS="assistant architect quality ops tester"
elif [ -n "${1:-}" ]; then
    TARGETS="$1"
else
    echo "用法: $0 [--all | role_key]"
    echo ""
    echo "可回滚的 agent:"
    if [ -d "$LATEST_BACKUP" ]; then
        ls "$LATEST_BACKUP/" 2>/dev/null | sed 's/^/  /'
    fi
    exit 1
fi

# 确认
read -rp "确认回滚 $TARGETS ？[y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "已取消"
    exit 0
fi

for ROLE_KEY in $TARGETS; do
    echo "--- 回滚 agent: $ROLE_KEY ---"

    # 1. 删除通过 openclaw agents add 创建的 agent
    if command -v openclaw &>/dev/null; then
        if openclaw agents list 2>/dev/null | grep -q "$ROLE_KEY"; then
            echo "删除 OpenClaw agent: $ROLE_KEY"
            openclaw agents delete "$ROLE_KEY" --non-interactive 2>/dev/null || \
                echo "WARNING: 删除失败，可能需要手动删除"
        else
            echo "OpenClaw agent $ROLE_KEY 不存在，跳过"
        fi
    fi

    # 2. 恢复工作区文件
    AGENT_WORKSPACE="$AGENTS_DIR/$ROLE_KEY/workspace"
    if [ ! -d "$AGENT_WORKSPACE" ]; then
        AGENT_WORKSPACE="$AGENTS_DIR/$ROLE_KEY"
    fi

    BACKUP_WORKSPACE="$LATEST_BACKUP/$ROLE_KEY/workspace"
    if [ -d "$BACKUP_WORKSPACE" ]; then
        echo "恢复工作区: $AGENT_WORKSPACE"
        rm -rf "$AGENT_WORKSPACE"
        cp -r "$BACKUP_WORKSPACE" "$AGENT_WORKSPACE"
    else
        echo "删除工作区: $AGENT_WORKSPACE"
        rm -rf "$AGENT_WORKSPACE"
    fi

    # 3. 删除该 agent 的 cron 任务
    if command -v openclaw &>/dev/null; then
        echo "清理 $ROLE_KEY 的 cron 任务..."
        openclaw cron list 2>/dev/null | grep "$ROLE_KEY" | awk '{print $1}' | while read -r cron_id; do
            echo "删除 cron: $cron_id"
            openclaw cron delete "$cron_id" 2>/dev/null || true
        done
    fi

    echo "Agent $ROLE_KEY 已回滚 ✓"
done

# 如果是 --all 且 main agent 有备份，恢复 main
if [ "${1:-}" = "--all" ] && [ -d "$LATEST_BACKUP/main" ]; then
    echo "--- 恢复 main agent ---"
    if [ -d "$LATEST_BACKUP/main/workspace" ]; then
        echo "恢复 main 工作区: $WORKSPACE_ROOT"
        # 只恢复我们自己修改过的文件，不覆盖 agent 自己的 memory
        for f in SOUL.md AGENTS.md IDENTITY.md HEARTBEAT.md TOOLS.md TEAM.md; do
            if [ -f "$LATEST_BACKUP/main/workspace/$f" ]; then
                cp "$LATEST_BACKUP/main/workspace/$f" "$WORKSPACE_ROOT/$f" 2>/dev/null || true
            fi
        done
        echo "main agent 已恢复 ✓"
    fi
fi

echo ""
echo "=== 回滚完成 ==="
echo "如需查看备份内容: ls -la $LATEST_BACKUP/"
