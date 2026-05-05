#!/usr/bin/env bash
# clawteam 开发环境一键安装脚本
# 用法: bash scripts/setup-env.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "=== ClawTeam 开发环境安装 ==="

# ──────────────────────────────
# 检测操作系统
# ──────────────────────────────
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID}"
    elif command -v lsb_release &>/dev/null; then
        lsb_release -is | tr '[:upper:]' '[:lower:]'
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ "$(uname -s)" = "Darwin" ]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
echo "操作系统: $OS"

# ──────────────────────────────
# 检查并安装系统级依赖
# ──────────────────────────────
check_python_venv() {
    # 尝试创建临时 venv 来检测 venv 是否可用
    local tmp_venv
    tmp_venv=$(mktemp -d)
    if python3 -m venv "$tmp_venv" 2>/dev/null; then
        rm -rf "$tmp_venv"
        return 0
    fi
    rm -rf "$tmp_venv"
    return 1
}

install_system_deps() {
    local os="$1"
    case "$os" in
        ubuntu|debian|pop|linuxmint|elementary)
            echo "检测到 Debian/Ubuntu 系统，安装 python3-venv..."
            sudo apt update -qq
            sudo apt install -y python3 python3-venv python3-pip
            ;;
        centos|rhel|fedora|amzn|rocky|alma)
            echo "检测到 RHEL/CentOS/Fedora 系统，安装 python3..."
            if command -v dnf &>/dev/null; then
                sudo dnf install -y python3 python3-pip
            else
                sudo yum install -y python3 python3-pip
            fi
            ;;
        alpine)
            echo "检测到 Alpine 系统，安装 python3..."
            sudo apk add python3 py3-pip
            ;;
        macos)
            echo "检测到 macOS，使用 Homebrew..."
            if ! command -v brew &>/dev/null; then
                echo "WARNING: Homebrew 未安装，请先安装: https://brew.sh"
                echo "  或者从 python.org 安装 Python 3.12+"
                return 1
            fi
            brew install python@3.12 2>/dev/null || true
            ;;
        *)
            echo "WARNING: 未知系统 '$os'，请手动安装 python3 (>=3.12) 和 python3-venv"
            return 1
            ;;
    esac
}

# 检查 Python3
PYTHON=${PYTHON:-python3}
if ! command -v "$PYTHON" &>/dev/null; then
    echo "Python3 未安装，尝试自动安装系统依赖..."
    install_system_deps "$OS"
fi

if ! command -v "$PYTHON" &>/dev/null; then
    echo "ERROR: python3 仍未安装，请手动安装 Python >= 3.12"
    exit 1
fi

# 检查 Python 版本
PY_VERSION=$($PYTHON -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$($PYTHON -c "import sys; print(sys.version_info.major)")
PY_MINOR=$($PYTHON -c "import sys; print(sys.version_info.minor)")

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 12 ]; }; then
    echo "ERROR: Python >= 3.12 required, got $PY_VERSION"
    echo "  Ubuntu/Debian: sudo apt install python3.12 python3.12-venv"
    echo "  CentOS/RHEL:   sudo yum install python3.12"
    echo "  macOS:         brew install python@3.12"
    exit 1
fi
echo "Python version: $PY_VERSION ✓"

# 检查 venv 可用性
if ! check_python_venv; then
    echo "python3-venv 不可用，尝试自动安装..."
    case "$OS" in
        ubuntu|debian|pop|linuxmint|elementary)
            sudo apt update -qq
            sudo apt install -y "python3.${PY_MINOR}-venv" python3-venv 2>/dev/null || \
                sudo apt install -y python3-venv
            ;;
        centos|rhel|rocky|alma|amzn)
            # RHEL 系通常 venv 随 python3 一起安装
            echo "尝试安装 python3-venv..."
            sudo yum install -y python3-venv 2>/dev/null || true
            ;;
        alpine)
            # Alpine 无需单独的 venv 包
            ;;
        macos)
            # macOS 自带 venv
            ;;
        *)
            echo "WARNING: 无法自动安装 python3-venv，请手动安装"
            ;;
    esac

    # 再次检查
    if ! check_python_venv; then
        echo "ERROR: python3-venv 仍不可用"
        echo "请手动执行:"
        case "$OS" in
            ubuntu|debian|pop|linuxmint|elementary)
                echo "  sudo apt install python3.${PY_MINOR}-venv"
                ;;
            centos|rhel|rocky|alma|amzn)
                echo "  sudo yum install python3-venv"
                ;;
        esac
        exit 1
    fi
fi
echo "python3-venv 可用 ✓"

# ──────────────────────────────
# 检查 Git（可选）
# ──────────────────────────────
if command -v git &>/dev/null; then
    echo "Git: $(git --version | cut -d' ' -f2) ✓"
else
    echo "NOTE: Git 未安装"
fi

# ──────────────────────────────
# 检查 Node.js / OpenClaw（可选）
# ──────────────────────────────
if command -v node &>/dev/null; then
    echo "Node.js: $(node --version) ✓"
else
    echo "NOTE: Node.js 未安装。OpenClaw CLI 需要 Node.js: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash - && sudo apt install -y nodejs"
fi

# ──────────────────────────────
# 创建虚拟环境
# ──────────────────────────────
VENV_DIR="$PROJECT_DIR/.venv"

if [ -d "$VENV_DIR" ]; then
    echo "虚拟环境已存在: $VENV_DIR"
else
    echo "创建虚拟环境..."
    $PYTHON -m venv "$VENV_DIR"
    echo "虚拟环境创建完成 ✓"
fi

# ──────────────────────────────
# 激活虚拟环境并安装依赖
# ──────────────────────────────
source "$VENV_DIR/bin/activate"
echo "虚拟环境已激活 ✓"

echo "升级 pip..."
pip install --upgrade pip --quiet

echo "安装依赖 (pyyaml, jinja2, pytest, pytest-cov)..."
pip install -e ".[dev]" --quiet
echo "依赖安装完成 ✓"

# ──────────────────────────────
# 运行测试验证
# ──────────────────────────────
echo "运行测试..."
TEST_RESULT=$(python -m pytest tests/ -q 2>&1)
TEST_COUNT=$(echo "$TEST_RESULT" | tail -1 | grep -oP '\d+(?= passed)' || echo "0")

if [ "$TEST_COUNT" -ge 50 ]; then
    echo "测试通过: ${TEST_COUNT} passed ✓"
else
    echo "WARNING: 测试未全部通过 (${TEST_COUNT} passed)，请检查"
fi

# ──────────────────────────────
# 检查 OpenClaw CLI
# ──────────────────────────────
if command -v openclaw &>/dev/null; then
    OC_VERSION=$(openclaw --version 2>&1 | head -1)
    echo "OpenClaw CLI: $OC_VERSION ✓"
else
    echo "NOTE: OpenClaw CLI 未安装。可选: npm install -g openclaw"
fi

# ──────────────────────────────
# 完成
# ──────────────────────────────
echo ""
echo "=== 安装完成 ==="
echo ""
echo "使用方法:"
echo "  激活环境:    source .venv/bin/activate"
echo "  运行测试:    pytest tests/ -v"
echo "  检测实例:    bash scripts/preflight-check.sh"
echo "  初始化Agent: bash scripts/setup-agents.sh --all"
echo "  退出环境:    deactivate"
