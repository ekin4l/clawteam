#!/usr/bin/env bash
# Work Item 管理脚本
# 用法: bash scripts/manage-workitems.sh <command> [args]
# 命令:
#   list [--verbose]           列出所有 work items（--verbose 显示详情）
#   show <name>                查看某个 work item 详情
#   add <name>                 从模板创建新 work item
#   edit <name>                编辑 work item（打开 $EDITOR）
#   remove <name>              删除 work item
#   assign <name> <role_key>   将 work item 分配给 agent
#   unassign <name> <role_key> 取消分配
#   sync-cron [--agent <key>]  同步定时任务到 OpenClaw（根据 scheduled triggers）
#   clean-cron [--agent <key>] 清除该 agent 的所有 clawteam cron 任务
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

WI_DIR="$PROJECT_DIR/work_items"
ASSIGNMENTS="$PROJECT_DIR/assignments.yaml"
TEMPLATE="$WI_DIR/_template.yaml"

# ── 辅助函数 ──
wi_path() { echo "$WI_DIR/$1.yaml"; }

wi_exists() { [ -f "$(wi_path "$1")" ]; }

list_all_wi() {
    for f in "$WI_DIR"/*.yaml; do
        [ -f "$f" ] || continue
        basename "$f" .yaml | grep -v '^_'
    done
}

load_wi_field() {
    python3 -c "
import yaml
data = yaml.safe_load(open('$(wi_path $1)'))
print(data.get('$2', ''))
" 2>/dev/null || echo ""
}

# ── 命令实现 ──
cmd_list() {
    local verbose="${1:-}"
    echo "=== Work Items ==="
    for name in $(list_all_wi); do
        if [ "$verbose" = "--verbose" ] || [ "$verbose" = "-v" ]; then
            display=$(load_wi_field "$name" "display_name")
            category=$(load_wi_field "$name" "category")
            schedule=$(python3 -c "
import yaml
data = yaml.safe_load(open('$(wi_path $name)'))
print(data.get('triggers', {}).get('scheduled', '-'))
" 2>/dev/null || echo "-")
            agents=$(python3 -c "
import yaml
asgn = yaml.safe_load(open('$ASSIGNMENTS'))
assigned = []
for rk, items in asgn.get('defaults', {}).items():
    if '$name' in items:
        assigned.append(rk)
print(', '.join(assigned) or '-')
" 2>/dev/null || echo "-")
            printf "  %-25s %-12s %-10s %-15s %s\n" "$name" "$display" "$category" "$schedule" "$agents"
        else
            display=$(load_wi_field "$name" "display_name")
            echo "  $name — $display"
        fi
    done
    if [ "$verbose" = "--verbose" ] || [ "$verbose" = "-v" ]; then
        echo ""
        printf "  %-25s %-12s %-10s %-15s %s\n" "NAME" "DISPLAY" "CATEGORY" "SCHEDULE" "AGENTS"
    fi
}

cmd_show() {
    local name="$1"
    if ! wi_exists "$name"; then
        echo "ERROR: work item '$name' 不存在"
        exit 1
    fi
    echo "=== $name ==="
    cat "$(wi_path "$name")"
}

cmd_add() {
    local name="$1"
    if wi_exists "$name"; then
        echo "ERROR: work item '$name' 已存在"
        exit 1
    fi
    cp "$TEMPLATE" "$(wi_path "$name")"
    # 预填 name 字段
    python3 -c "
import yaml
path = '$(wi_path $name)'
data = yaml.safe_load(open(path))
data['name'] = '$name'
with open(path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
"
    echo "已创建: $(wi_path "$name")"
    echo "请编辑该文件填写详细信息。"
    if [ -n "${EDITOR:-}" ]; then
        echo "运行: $EDITOR $(wi_path "$name")"
    fi
}

cmd_edit() {
    local name="$1"
    if ! wi_exists "$name"; then
        echo "ERROR: work item '$name' 不存在"
        exit 1
    fi
    local editor="${EDITOR:-vi}"
    echo "打开编辑: $(wi_path "$name")"
    $editor "$(wi_path "$name")"
}

cmd_remove() {
    local name="$1"
    if ! wi_exists "$name"; then
        echo "ERROR: work item '$name' 不存在"
        exit 1
    fi
    # 检查是否有 agent 在用
    local assigned
    assigned=$(python3 -c "
import yaml
asgn = yaml.safe_load(open('$ASSIGNMENTS'))
for rk, items in asgn.get('defaults', {}).items():
    if '$name' in items:
        print(rk)
" 2>/dev/null || true)

    if [ -n "$assigned" ]; then
        echo "WARNING: 以下 agent 仍在使用 '$name': $assigned"
        echo "请先执行: bash $0 unassign $name <role_key>"
        read -rp "确认删除？[y/N] " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
            echo "已取消"
            exit 0
        fi
    fi

    rm "$(wi_path "$name")"
    echo "已删除: $name"
}

cmd_assign() {
    local name="$1"
    local role_key="$2"
    if ! wi_exists "$name"; then
        echo "ERROR: work item '$name' 不存在"
        exit 1
    fi
    python3 -c "
import yaml
path = '$ASSIGNMENTS'
data = yaml.safe_load(open(path))
defaults = data.setdefault('defaults', {})
items = defaults.setdefault('$role_key', [])
if '$name' not in items:
    items.append('$name')
    with open(path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
    print('已将 $name 分配给 $role_key')
else:
    print('$name 已分配给 $role_key，跳过')
"
}

cmd_unassign() {
    local name="$1"
    local role_key="$2"
    python3 -c "
import yaml
path = '$ASSIGNMENTS'
data = yaml.safe_load(open(path))
defaults = data.get('defaults', {})
items = defaults.get('$role_key', [])
if '$name' in items:
    items.remove('$name')
    with open(path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
    print('已将 $name 从 $role_key 取消分配')
else:
    print('$name 未分配给 $role_key')
"
}

cmd_sync_cron() {
    local agent_filter="${1:-}"
    local agents

    if [ -n "$agent_filter" ]; then
        agents="$agent_filter"
    else
        # 同步所有有定时任务的 agent
        agents=$(python3 -c "
import yaml, glob
from pathlib import Path

asgn = yaml.safe_load(open('$ASSIGNMENTS'))
agent_keys = set()
for rk, items in asgn.get('defaults', {}).items():
    for wi_name in items:
        wi_path = f'$WI_DIR/{wi_name}.yaml'
        try:
            wi = yaml.safe_load(open(wi_path))
            if wi.get('triggers', {}).get('scheduled'):
                agent_keys.add(rk)
        except FileNotFoundError:
            pass
print(' '.join(sorted(agent_keys)))
" 2>/dev/null || echo "")
    fi

    if [ -z "$agents" ]; then
        echo "没有需要同步定时任务的 agent"
        return
    fi

    echo "=== 同步定时任务 ==="

    for ROLE_KEY in $agents; do
        echo "--- $ROLE_KEY ---"
        python3 -c "
import yaml, glob, subprocess, sys

# Load assignments
asgn = yaml.safe_load(open('$ASSIGNMENTS'))
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
                existing_cron_names.add(line.strip())
except (FileNotFoundError, subprocess.TimeoutExpired):
    pass

# For each assigned work item, check for scheduled triggers
for wi_name in work_item_names:
    wi_path = 'work_items/${wi_name}.yaml'
    try:
        wi = yaml.safe_load(open(wi_path))
    except FileNotFoundError:
        print(f'  Warning: ${wi_name}.yaml not found, skipping')
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
" 2>/dev/null || echo "  Warning: sync failed for $ROLE_KEY"
    done

    echo "=== 同步完成 ==="
}

cmd_clean_cron() {
    local agent_filter="${1:-}"
    local agents

    if [ -n "$agent_filter" ]; then
        agents="$agent_filter"
    else
        echo "ERROR: 请指定 --agent <role_key> 或 'all'"
        echo "用法: $0 clean-cron --agent <role_key>"
        exit 1
    fi

    echo "=== 清理定时任务 ==="

    for ROLE_KEY in $agents; do
        echo "--- $ROLE_KEY ---"
        if ! command -v openclaw &>/dev/null; then
            echo "  openclaw not available, skipping"
            continue
        fi
        openclaw cron list 2>/dev/null | grep "clawteam-${ROLE_KEY}" | awk '{print $1}' | while read -r cron_id; do
            echo "  删除 cron: $cron_id"
            openclaw cron delete "$cron_id" 2>/dev/null || true
        done
        echo "  $ROLE_KEY cron 已清理"
    done

    echo "=== 清理完成 ==="
}

# ── 主入口 ──
usage() {
    echo "用法: $0 <command> [args]"
    echo ""
    echo "命令:"
    echo "  list [--verbose|-v]           列出所有 work items"
    echo "  show <name>                   查看 work item 详情"
    echo "  add <name>                    创建新 work item"
    echo "  edit <name>                   编辑 work item"
    echo "  remove <name>                 删除 work item"
    echo "  assign <name> <role_key>      分配给 agent"
    echo "  unassign <name> <role_key>    取消分配"
    echo "  sync-cron [--agent <key>]     同步定时任务到 OpenClaw"
    echo "  clean-cron --agent <key>      清除 agent 的 cron 任务"
    echo ""
    echo "示例:"
    echo "  $0 list -v"
    echo "  $0 add code_review"
    echo "  $0 assign daily_report assistant"
    echo "  $0 sync-cron --agent assistant"
    echo "  $0 sync-cron                 # 同步所有"
}

CMD="${1:-}"
shift || true

case "$CMD" in
    list|ls)
        cmd_list "${1:-}"
        ;;
    show)
        [ -z "${1:-}" ] && { echo "用法: $0 show <name>"; exit 1; }
        cmd_show "$1"
        ;;
    add)
        [ -z "${1:-}" ] && { echo "用法: $0 add <name>"; exit 1; }
        cmd_add "$1"
        ;;
    edit)
        [ -z "${1:-}" ] && { echo "用法: $0 edit <name>"; exit 1; }
        cmd_edit "$1"
        ;;
    remove|rm)
        [ -z "${1:-}" ] && { echo "用法: $0 remove <name>"; exit 1; }
        cmd_remove "$1"
        ;;
    assign)
        [ -z "${2:-}" ] && { echo "用法: $0 assign <name> <role_key>"; exit 1; }
        cmd_assign "$1" "$2"
        ;;
    unassign)
        [ -z "${2:-}" ] && { echo "用法: $0 unassign <name> <role_key>"; exit 1; }
        cmd_unassign "$1" "$2"
        ;;
    sync-cron)
        AGENT=""
        if [ "${1:-}" = "--agent" ] && [ -n "${2:-}" ]; then
            AGENT="$2"
        fi
        cmd_sync_cron "$AGENT"
        ;;
    clean-cron)
        AGENT=""
        if [ "${1:-}" = "--agent" ] && [ -n "${2:-}" ]; then
            AGENT="$2"
        fi
        cmd_clean_cron "$AGENT"
        ;;
    *)
        usage
        exit 1
        ;;
esac
