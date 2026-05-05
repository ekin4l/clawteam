#!/usr/bin/env bash
# clawteam 开发环境一键安装脚本
# 用法: bash scripts/setup-env.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "=== ClawTeam 开发环境安装 ==="

# 1. 检查 Python 版本
PYTHON=${PYTHON:-python3}
if ! command -v "$PYTHON" &>/dev/null; then
    echo "ERROR: python3 未安装"
    echo "  Ubuntu/Debian: sudo apt install python3 python3-venv python3-pip"
    echo "  CentOS/RHEL:   sudo yum install python3"
    exit 1
fi

PY_VERSION=$($PYTHON -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$($PYTHON -c "import sys; print(sys.version_info.major)")
PY_MINOR=$($PYTHON -c "import sys; print(sys.version_info.minor)")

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 12 ]; }; then
    echo "ERROR: Python >= 3.12 required, got $PY_VERSION"
    exit 1
fi
echo "Python version: $PY_VERSION ✓"

# 2. 创建虚拟环境
VENV_DIR="$PROJECT_DIR/.venv"

if [ -d "$VENV_DIR" ]; then
    echo "虚拟环境已存在: $VENV_DIR"
else
    echo "创建虚拟环境..."
    $PYTHON -m venv "$VENV_DIR"
    echo "虚拟环境创建完成 ✓"
fi

# 3. 激活虚拟环境
source "$VENV_DIR/bin/activate"
echo "虚拟环境已激活 ✓"

# 4. 升级 pip
echo "升级 pip..."
pip install --upgrade pip --quiet

# 5. 安装项目依赖
echo "安装依赖 (pyyaml, jinja2, pytest, pytest-cov)..."
pip install -e ".[dev]" --quiet
echo "依赖安装完成 ✓"

# 6. 运行测试验证
echo "运行测试..."
TEST_RESULT=$(python -m pytest tests/ -q 2>&1)
TEST_COUNT=$(echo "$TEST_RESULT" | tail -1 | grep -oP '\d+(?= passed)')

if [ -n "$TEST_COUNT" ] && [ "$TEST_COUNT" -ge 50 ]; then
    echo "测试通过: ${TEST_COUNT} passed ✓"
else
    echo "WARNING: 测试未全部通过，请检查"
    echo "$TEST_RESULT"
fi

# 7. 检查 OpenClaw CLI
if command -v openclaw &>/dev/null; then
    OC_VERSION=$(openclaw --version 2>&1 | head -1)
    echo "OpenClaw CLI: $OC_VERSION ✓"
else
    echo "NOTE: OpenClaw CLI 未安装。可选安装: npm install -g openclaw"
fi

echo ""
echo "=== 安装完成 ==="
echo ""
echo "使用方法:"
echo "  激活环境:    source .venv/bin/activate"
echo "  运行测试:    pytest tests/ -v"
echo "  检测实例:    bash scripts/preflight-check.sh"
echo "  初始化Agent: bash scripts/setup-agents.sh --all"
echo "  退出环境:    deactivate"
