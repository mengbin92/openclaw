#!/usr/bin/env bash
#
# OpenClaw 一键部署脚本
# 支持: Linux (Ubuntu/Debian, CentOS/RHEL, macOS, Windows WSL/Git Bash)
#

set -e

# 检查 sudo 权限（仅在需要时提示）
require_sudo() {
    if ! sudo -v 2>/dev/null; then
        print_error "需要 sudo 权限来安装系统依赖"
        print_info "请确保有 sudo 权限后再运行脚本"
        exit 1
    fi
    # 保持 sudo 权限活跃
    while true; do
        sudo -n true 2>/dev/null || break
        sleep 60
    done &
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
OPENCLAW_DIR="${HOME}/.openclaw"
CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
NPM_REGISTRY="https://registry.npmmirror.com/"

# 默认值
DEFAULT_API_KEY=""
DEFAULT_MODEL="GPUNexus"
DEFAULT_BASE_URL="https://coding.gpunexus.com"
DEFAULT_BASE_URL_ALT="https://api.gpunexus.com/v1"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # 检测具体的Linux发行版
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian|linuxmint|pop)
                    echo "debian"
                    ;;
                centos|rhel|fedora|rocky|alma)
                    echo "rhel"
                    ;;
                arch|manjaro|endeavouros)
                    echo "arch"
                    ;;
                *)
                    echo "linux"
                    ;;
            esac
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 安装 Git
install_git() {
    local os="$1"

    # Linux 系统需要 sudo 权限来安装依赖
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        require_sudo
    fi

    print_info "检查 Git 安装状态..."

    if command_exists git; then
        local git_version
        git_version=$(git --version)
        print_success "Git 已安装: ${git_version}"
        return 0
    fi

    print_info "正在安装 Git..."

    case "$os" in
        macos)
            if command_exists brew; then
                brew install git
            else
                print_error "请安装 Homebrew: https://brew.sh"
                print_info "或者手动安装 Git: https://git-scm.com"
                exit 1
            fi
            ;;
        debian)
            sudo apt-get update
            sudo apt-get install -y git
            ;;
        rhel)
            sudo yum install -y git
            ;;
        arch)
            sudo pacman -S --noconfirm git
            ;;
        windows)
            print_warning "Windows 环境检测到"
            print_info "请确保已安装 Git: https://git-scm.com"
            print_info "或使用 WSL 运行此脚本"
            exit 1
            ;;
        *)
            print_error "不支持的操作系统"
            exit 1
            ;;
    esac

    # 验证安装
    if command_exists git; then
        local git_version
        git_version=$(git --version)
        print_success "Git 安装成功: ${git_version}"
    else
        print_error "Git 安装失败"
        exit 1
    fi
}

# 安装 Node.js
install_nodejs() {
    local os="$1"

    # Linux 系统需要 sudo 权限来安装依赖
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        require_sudo
    fi

    print_info "检查 Node.js 安装状态..."

    if command_exists node; then
        local node_version
        node_version=$(node --version)
        print_success "Node.js 已安装: ${node_version}"
        return 0
    fi

    print_info "正在安装 Node.js..."

    case "$os" in
        macos)
            if command_exists brew; then
                brew install node jq cmake
            else
                print_error "请安装 Homebrew: https://brew.sh"
                print_info "或者手动安装 Node.js: https://nodejs.org"
                exit 1
            fi
            ;;
        debian)
            # 安装编译依赖 (cmake, gcc, g++, make 等)
            print_info "正在安装编译依赖..."
            sudo apt-get update
            sudo apt-get install -y build-essential cmake gcc g++ make jq curl python3 iproute2

            # 安装 Node.js
            if ! install_nvm "debian"; then
                # nvm 失败，使用系统包管理器
                print_info "使用系统包管理器安装 Node.js..."
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                sudo apt-get install -y nodejs
            fi
            ;;
        rhel)
            # 安装编译依赖
            print_info "正在安装编译依赖..."
            sudo yum groupinstall -y "Development Tools"
            sudo yum install -y cmake gcc gcc-c++ make jq curl python3 iproute

            # 安装 Node.js
            if ! install_nvm "rhel"; then
                # nvm 失败，使用系统包管理器
                print_info "使用系统包管理器安装 Node.js..."
                curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
                sudo yum install -y nodejs
            fi
            ;;
        arch)
            sudo pacman -S --noconfirm nodejs npm jq cmake gcc make python
            ;;
        windows)
            print_warning "Windows 环境检测到"
            print_info "请确保已安装 Node.js: https://nodejs.org"
            print_info "或使用 WSL 运行此脚本"
            exit 1
            ;;
        *)
            print_error "不支持的操作系统"
            exit 1
            ;;
    esac
}

# 安装 nvm (Node Version Manager)
install_nvm() {
    local os_type="$1"

    if [ -d "${NVM_DIR}" ]; then
        print_success "nvm 已安装"
        return 0
    fi

    # 检查 curl 是否可用
    if ! command_exists curl; then
        print_warning "curl 未安装，尝试安装..."
        case "$os_type" in
            debian) sudo apt-get install -y curl ;;
            rhel) sudo yum install -y curl ;;
            arch) sudo pacman -S --noconfirm curl ;;
        esac
    fi

    print_info "正在安装 nvm..."

    export NVM_DIR="${HOME}/.nvm"

    # 检测是否能访问 raw.githubusercontent.com
    if curl -s --max-time 5 https://raw.githubusercontent.com >/dev/null 2>&1; then
        # 可以访问，使用官方脚本
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    else
        # 无法访问，尝试使用镜像
        print_warning "无法访问 raw.githubusercontent.com，尝试使用 Gitee 镜像..."
        curl -o- https://gitee.com/nvm-sh/nvm/raw/master/install.sh | bash
    fi

    # 检查 nvm 是否安装成功
    if [ ! -d "${NVM_DIR}" ]; then
        print_error "nvm 安装失败，尝试直接安装 Node.js..."
        return 1
    fi

    # 加载 nvm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # 添加到 shell 配置文件
    local shell_config=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        shell_config="${HOME}/.zshrc"
    else
        shell_config="${HOME}/.bashrc"
    fi

    if ! grep -q "NVM_DIR" "$shell_config" 2>/dev/null; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> "$shell_config"
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$shell_config"
    fi

    print_success "nvm 安装完成"
}

# 加载 nvm (如果可用)
load_nvm() {
    if [ -d "${NVM_DIR:-${HOME}/.nvm}" ]; then
        export NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi
}

# 检查并添加 swap 空间 (解决内存不足问题)
setup_swap() {
    local os="$1"

    # 只在 Linux 上处理
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        return 0
    fi

    # 检查是否有 sudo 权限
    if ! sudo -n true 2>/dev/null; then
        print_warning "没有 sudo 权限，无法添加 swap 空间"
        print_info "如果安装过程中内存不足，请手动添加 swap:"
        print_info "  sudo fallocate -l 4G /swapfile"
        print_info "  sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
        return 0
    fi

    # 检查当前内存和 swap
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    local total_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')

    # 如果无法获取内存信息，设置默认值
    if [ -z "$total_mem" ]; then
        total_mem=0
    fi
    if [ -z "$total_swap" ]; then
        total_swap=0
    fi

    print_info "系统内存: ${total_mem}MB, Swap: ${total_swap}MB"

    # 如果内存小于 2GB 且 swap 小于 2GB，添加 swap
    if [ "$total_mem" -lt 2048 ] && [ "$total_swap" -lt 2048 ]; then
        print_warning "内存较小，正在添加 swap 空间..."

        local swap_file="/swapfile_openclaw"
        local swap_size="4G"

        # 检查是否已有 swap 文件
        if [ -f "$swap_file" ]; then
            print_info "Swap 文件已存在"
            return 0
        fi

        # 创建 swap 文件
        sudo fallocate -l $swap_size $swap_file 2>/dev/null || sudo dd if=/dev/zero of=$swap_file bs=1M count=4096
        sudo chmod 600 $swap_file
        sudo mkswap $swap_file
        sudo swapon $swap_file

        print_success "已添加 ${swap_size} swap 空间"
    fi
}

# 安装 OpenClaw
install_openclaw() {
    print_info "正在安装 OpenClaw..."

    # 设置 npm 镜像源
    npm config set registry "${NPM_REGISTRY}"
    print_info "已设置 npm 镜像源: ${NPM_REGISTRY}"

    # 设置 npm 使用 HTTPS 而不是 SSH 来克隆 git 依赖
    # 解决没有 GitHub SSH 密钥时的安装问题
    print_info "配置 npm 使用 HTTPS 协议克隆 git 依赖..."
    npm config set git-tag-version false
    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" 2>/dev/null || true
    git config --global url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true

    # 设置 Node.js 内存限制 (增加可用内存)
    export NODE_OPTIONS="--max-old-space-size=4096"

    # 全局安装 openclaw
    npm install -g openclaw

    if command_exists openclaw; then
        print_success "OpenClaw 安装成功"
        openclaw --version
    else
        print_error "OpenClaw 安装失败"
        exit 1
    fi
}

# 创建配置文件 (在 openclaw setup 之后运行,只更新 models 部分)
create_config() {
    local api_key="$1"
    local model_choice="$2"
    local custom_base_url="$3"

    print_info "正在更新配置文件..."

    # 确保目录存在
    mkdir -p "${OPENCLAW_DIR}"

    # 根据模型选择生成配置
    local base_url=""
    local api_type=""
    local model_id=""
    local provider_name=""

    case "$model_choice" in
        1)
            # MiniMax-M2.1 (OpenAI兼容)
            provider_name="GPUNexus"
            base_url="${custom_base_url}"
            api_type="openai-completions"
            model_id="MiniMax-M2.1"
            ;;
        2)
            # GPUNexus (Claude Code)
            provider_name="GPUNexus"
            base_url="${custom_base_url}"
            api_type="anthropic-messages"
            model_id="GPUNexus"
            ;;
        *)
            print_error "无效的模型选择"
            exit 1
            ;;
    esac

    # 使用 jq 更新配置文件中的 models 部分
    if command_exists jq; then
        # 读取现有配置，添加 models 部分
        local temp_config
        temp_config=$(cat "${CONFIG_FILE}")

        # 使用 jq 合并配置
        echo "${temp_config}" | jq --arg provider "${provider_name}" \
            --arg baseUrl "${base_url}" \
            --arg apiKey "${api_key}" \
            --arg apiType "${api_type}" \
            --arg modelId "${model_id}" \
            '. + {
                "models": {
                    "providers": {
                        ($provider): {
                            "baseUrl": $baseUrl,
                            "apiKey": $apiKey,
                            "auth": "token",
                            "api": $apiType,
                            "headers": {},
                            "authHeader": true,
                            "models": [
                                {
                                    "id": $modelId,
                                    "name": $modelId,
                                    "api": $apiType,
                                    "reasoning": false,
                                    "input": ["text"],
                                    "cost": {
                                        "input": 1048576,
                                        "output": 1048576,
                                        "cacheRead": 0,
                                        "cacheWrite": 0
                                    },
                                    "contextWindow": 1048576,
                                    "maxTokens": 1048576,
                                    "compat": {
                                        "supportsStore": false,
                                        "maxTokensField": "max_tokens"
                                    }
                                }
                            ]
                        }
                    }
                },
                "agents": {
                    "defaults": {
                        "model": {
                            "primary": ($provider + "/" + $modelId)
                        },
                        "models": {
                            ($provider + "/" + $modelId): {}
                        }
                    }
                }
            }' > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"

        print_success "配置文件已更新: ${CONFIG_FILE}"
    else
        # 如果没有 jq，直接创建完整配置（降级方案）
        print_warning "jq 未安装，将创建完整配置文件"

        # 生成随机 token
        local token=$(openssl rand -hex 20 2>/dev/null || head -c 40 < /dev/urandom | xxd -p)

        cat > "${CONFIG_FILE}" << EOF
{
  "meta": {
    "lastTouchedVersion": "2026.2.1",
    "lastTouchedAt": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  },
  "models": {
    "providers": {
      "${provider_name}": {
        "baseUrl": "${base_url}",
        "apiKey": "${api_key}",
        "auth": "token",
        "api": "${api_type}",
        "headers": {},
        "authHeader": true,
        "models": [
          {
            "id": "${model_id}",
            "name": "${model_id}",
            "api": "${api_type}",
            "reasoning": false,
            "input": ["text"],
            "cost": {
              "input": 1048576,
              "output": 1048576,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 1048576,
            "maxTokens": 1048576,
            "compat": {
              "supportsStore": false,
              "maxTokensField": "max_tokens"
            }
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${provider_name}/${model_id}"
      },
      "models": {
        "${provider_name}/${model_id}": {}
      },
      "workspace": "${OPENCLAW_DIR}/workspace",
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto"
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "${token}"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  }
}
EOF

        print_success "配置文件已创建: ${CONFIG_FILE}"
    fi
}

# 启动服务
start_service() {
    print_info "正在启动 OpenClaw 服务..."
    print_warning "按 Ctrl+C 停止服务"
    echo ""

    # 加载 nvm
    load_nvm

    # 检查配置文件是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "配置文件不存在: ${CONFIG_FILE}"
        exit 1
    fi

    # 验证配置文件 JSON 格式
    if command_exists jq; then
        if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
            print_error "配置文件 JSON 格式错误"
            exit 1
        fi
    fi

    # 从配置文件中获取 token
    local token=""
    if command_exists jq; then
        token=$(jq -r '.gateway.auth.token' "${CONFIG_FILE}" 2>/dev/null)
    fi

    echo ""
    echo "============================================"
    echo ""
    print_info "访问地址: http://127.0.0.1:18789/"
    if [ -n "$token" ]; then
        print_info "Token: ${token}"
    else
        print_info "Token: 查看配置文件中的 gateway.auth.token 字段"
    fi
    echo ""
    echo "============================================"
    echo ""

    # 启动 onboard 进行初始化配置（会重置并重新配置服务）
    print_info "正在运行 openclaw onboard（初始化/重置配置）..."
    print_info "提示: 可以使用方向键进行导航"
    echo ""

    openclaw onboard || true

    echo ""
    print_info "配置完成"
    print_info "如需再次重置配置，请运行: openclaw onboard"
    print_info "如需正常启动服务，请运行: openclaw start"
}

# 显示帮助信息
show_help() {
    cat << EOF
OpenClaw 一键部署脚本

用法: $0 [选项]

选项:
    -k, --api-key <key>     GPUNexus API Key
    -m, --model <model>      选择模型: 1=MiniMax-M2.1, 2=GPUNexus (默认: 2)
    -b, --base-url <url>     API Base URL (可选)
    -h, --help               显示帮助信息

示例:
    $0 -k sk-xxxxxxxxxxxxx -m 1
    $0 --api-key sk-xxxxxxxxxxxxx
    $0 -k sk-xxxxxxxxxxxxx -m 1 -b https://custom.api.com

无参数运行时将进入交互模式 (API Key 会隐藏输入)
EOF
}

# 主函数
main() {
    local api_key=""
    local model_choice="2"
    local custom_base_url=""

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--api-key)
                api_key="$2"
                shift 2
                ;;
            -m|--model)
                model_choice="$2"
                shift 2
                ;;
            -b|--base-url)
                custom_base_url="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 欢迎信息
    echo "============================================"
    echo "         OpenClaw 一键部署脚本"
    echo "============================================"
    echo ""

    # 检测操作系统
    local os
    os=$(detect_os)
    print_info "检测到操作系统: $os"

    # 交互模式 - 获取 API Key (实时掩码显示)
    if [ -z "$api_key" ]; then
        echo ""
        print_info "请输入您的 GPUNexus API Key"
        print_info "获取方式: 访问 https://gpunexus.com 注册并创建 API Key"
        echo -n "API Key: "
        api_key=""
        local ch=""
        while IFS= read -rsn1 ch; do
            case "$ch" in
                $'\x7f')  # Backspace
                    if [ -n "$api_key" ]; then
                        api_key="${api_key%?}"
                        echo -n $'\b \b'
                    fi
                    ;;
                $'\n'|$'\r')  # Enter
                    echo ""
                    break
                    ;;
                "")
                    break
                    ;;
                *)
                    api_key+="$ch"
                    echo -n "*"
                    ;;
            esac
        done
    fi

    if [ -z "$api_key" ]; then
        print_error "API Key 不能为空"
        exit 1
    fi

    # 交互模式 - 选择模型
    if [ -z "$model_choice" ]; then
        echo ""
        print_info "请选择要使用的模型:"
        echo "  1. MiniMax-M2.1 (OpenAI兼容接口)"
        echo "  2. GPUNexus (Claude Code接口)"
        read -p "请选择 [1/2]: " model_choice
    fi

    # 设置默认 base_url 并检查是否需要交互式输入
    local default_base_url=""
    case "$model_choice" in
        1)
            print_info "已选择模型: MiniMax-M2.1"
            default_base_url="${DEFAULT_BASE_URL_ALT}"
            ;;
        2)
            print_info "已选择模型: GPUNexus"
            default_base_url="${DEFAULT_BASE_URL}"
            ;;
        *) print_error "无效选择，使用默认: GPUNexus"; model_choice="2"; default_base_url="${DEFAULT_BASE_URL}" ;;
    esac

    # 交互模式 - 获取 Base URL (仅当未通过命令行参数提供时)
    if [ -z "$custom_base_url" ]; then
        echo ""
        print_info "请输入 API Base URL (直接回车使用默认值: ${default_base_url})"
        read -p "Base URL: " custom_base_url
        if [ -z "$custom_base_url" ]; then
            custom_base_url="$default_base_url"
        fi
    fi
    print_info "已设置 Base URL: ${custom_base_url}"

    echo ""
    echo "============================================"
    echo ""

    # 步骤1: 安装 Git
    echo ">>> 步骤 1/5: 安装 Git"
    install_git "$os"

    # 步骤2: 安装 Node.js
    echo ">>> 步骤 2/5: 安装 Node.js"
    install_nodejs "$os"

    # 加载 nvm 后再次检查
    load_nvm
    if ! command_exists node; then
        print_error "Node.js 安装失败，请手动安装后重试"
        exit 1
    fi

    echo ""
    echo ">>> 步骤 3/5: 安装 OpenClaw"

    # 设置 swap (解决内存不足问题)
    # setup_swap "$os"

    install_openclaw

    echo ""
    echo ">>> 步骤 4/5: 创建配置文件"
    # 先运行 openclaw setup 生成默认配置
    print_info "正在运行 openclaw setup..."
    openclaw setup

    # 再修改配置文件
    create_config "$api_key" "$model_choice" "$custom_base_url"

    echo ""
    echo ">>> 步骤 5/5: 启动服务"
    echo ""
    print_success "部署完成!"
    echo ""
    echo "============================================"
    echo ""
    print_info "配置文件位置: ${CONFIG_FILE}"
    print_info "访问地址: http://127.0.0.1:18789/"
    print_info "Token: 查看配置文件中的 gateway.auth.token 字段"
    echo ""
    print_warning "即将运行 openclaw onboard 进行初始化配置..."
    print_info "提示: onboard 会重置并重新配置服务，按 Ctrl+C 可中断"
    echo ""

    # 运行 onboard 进行初始化
    start_service
}

# 运行主函数
main "$@"
