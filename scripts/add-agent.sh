#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "=== Add New Agent ==="

read -rp "Role key (e.g., dev_fullstack): " ROLE_KEY
read -rp "Display name (e.g., Liam): " DISPLAY_NAME
read -rp "Role title (e.g., 全栈工程师): " ROLE_TITLE
read -rp "Emoji (e.g., 💻): " EMOJI
read -rp "Model (default: zai/glm-4.7): " MODEL
MODEL="${MODEL:-zai/glm-4.7}"

FILENAME="agents/${ROLE_KEY}_${DISPLAY_NAME,,}.yaml"

cat > "$FILENAME" << EOF
role_key: $ROLE_KEY
display_name: "$DISPLAY_NAME"
role_title: "$ROLE_TITLE"
creature: "AI assistant"
emoji: "$EMOJI"
vibe: ""
avatar: "avatars/${ROLE_KEY}.svg"
model: "$MODEL"
communicates_externally: false
personality: |
  你是 $DISPLAY_NAME，一位$ROLE_TITLE。
assigned_work_items: []
heartbeat_tasks: []
capabilities: {}
EOF

echo "Created $FILENAME"
echo "Edit it to add work items, then run: scripts/setup-agents.sh $ROLE_KEY"
