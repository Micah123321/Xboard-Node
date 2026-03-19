#!/bin/bash
set -e

# xboard-node 多节点部署脚本
# 支持: Ubuntu 20+, Debian 11+, CentOS 8+, Alpine 3.18+
#
# 本机一键部署（默认，不带 --docker）:
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 1
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 2 -k xray
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 3 --gomemlimit 256MiB --gogc 50
#
# Docker 部署:
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 3 --docker
#
# 交互模式:
#   bash install.sh
#
# 管理命令:
#   bash install.sh list
#   bash install.sh remove <node_id>
#   bash install.sh update
#   bash install.sh uninstall

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/xboard-node"
SERVICE_TEMPLATE="xboard-node@.service"
DOCKER_COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
DOCKER_IMAGE="ghcr.io/cedar2025/xboard-node:latest"

# 解析后的参数
PANEL_URL=""
PANEL_TOKEN=""
NODE_ID=""
NODE_TYPE=""
KERNEL_TYPE="singbox"
GOMEMLIMIT=""
GOGC=""
DOCKER_MODE=0
SUBCOMMAND=""

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} ${BOLD}$1${NC}"; }

# ─── 参数解析 ────────────────────────────────────────────────────────

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--api)        PANEL_URL="$2";      shift 2 ;;
            -t|--token)      PANEL_TOKEN="$2";    shift 2 ;;
            -n|--node-id)    NODE_ID="$2";        shift 2 ;;
            -T|--node-type)  NODE_TYPE="$2";      shift 2 ;;
            -k|--kernel)     KERNEL_TYPE="$2";    shift 2 ;;
            --gomemlimit)    GOMEMLIMIT="$2";     shift 2 ;;
            --gogc)          GOGC="$2";           shift 2 ;;
            --docker)        DOCKER_MODE=1;         shift ;;
            add|remove|list|update|uninstall|help|--help|-h)
                if [ -z "$SUBCOMMAND" ]; then
                    SUBCOMMAND="$1"
                fi
                shift
                ;;
            *)
                if [ "$SUBCOMMAND" = "remove" ] && [ -z "$NODE_ID" ]; then
                    NODE_ID="$1"
                fi
                shift
                ;;
        esac
    done

    case "$KERNEL_TYPE" in
        xray|Xray|XRAY) KERNEL_TYPE="xray" ;;
        *) KERNEL_TYPE="singbox" ;;
    esac
}

has_all_params() {
    [ -n "$PANEL_URL" ] && [ -n "$PANEL_TOKEN" ] && [ -n "$NODE_ID" ]
}

validate_params() {
    if [ -z "$PANEL_URL" ]; then
        log_error "必须提供面板地址 (-a/--api)"
        exit 1
    fi
    if [ -z "$PANEL_TOKEN" ]; then
        log_error "必须提供服务端令牌 (-t/--token)"
        exit 1
    fi
    if [ -z "$NODE_ID" ]; then
        log_error "必须提供节点 ID (-n/--node-id)"
        exit 1
    fi
    if ! [[ "$NODE_ID" =~ ^[0-9]+$ ]]; then
        log_error "节点 ID 必须是正整数，当前值: $NODE_ID"
        exit 1
    fi
    if [ -n "$GOGC" ] && ! [[ "$GOGC" =~ ^[0-9]+$ ]]; then
        log_error "GOGC 必须是非负整数，当前值: $GOGC"
        exit 1
    fi
}

# ─── 系统检测 ────────────────────────────────────────────────────────

check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "请使用 root 用户执行，或通过 sudo 运行"
        exit 1
    fi
}

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    else
        OS="unknown"
    fi
}

install_deps() {
    case "$OS" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq wget curl tar >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux|fedora)
            yum install -y -q wget curl tar >/dev/null 2>&1
            ;;
        alpine)
            apk add --no-cache wget curl tar >/dev/null 2>&1
            ;;
    esac
}

# ─── 二进制安装 ──────────────────────────────────────────────────────

is_binary_installed() {
    [ -x "${INSTALL_DIR}/xboard-node" ]
}

install_binary() {
    if is_binary_installed; then
        log_info "xboard-node 二进制已存在，跳过下载"
        return
    fi

    log_step "安装 xboard-node 二进制..."

    local src=""

    if [ -f "./xboard-node" ]; then
        src="./xboard-node"
    elif [ -f "./xboard-node-linux-${ARCH}" ]; then
        src="./xboard-node-linux-${ARCH}"
    fi

    if [ -n "$src" ]; then
        cp "$src" "${INSTALL_DIR}/xboard-node"
        log_info "已从本地文件安装: $src"
    else
        local url="https://github.com/cedar2025/xboard-node/releases/latest/download/xboard-node-linux-${ARCH}"
        log_info "正在从 GitHub Releases 下载..."
        if wget -q "$url" -O "${INSTALL_DIR}/xboard-node" 2>/dev/null; then
            log_info "下载完成"
        elif curl -fsSL "$url" -o "${INSTALL_DIR}/xboard-node" 2>/dev/null; then
            log_info "下载完成"
        else
            log_error "下载失败。请先将对应架构的二进制放到当前目录后重试。"
            exit 1
        fi
    fi

    chmod +x "${INSTALL_DIR}/xboard-node"
    log_info "xboard-node 已安装到 ${INSTALL_DIR}/xboard-node"
}

# ─── systemd 模板 ───────────────────────────────────────────────────

install_systemd_template() {
    if ! command -v systemctl >/dev/null 2>&1; then
        return
    fi

    if [ -f "/etc/systemd/system/${SERVICE_TEMPLATE}" ]; then
        return
    fi

    log_step "安装 systemd 服务模板..."

    cat > "/etc/systemd/system/${SERVICE_TEMPLATE}" << 'UNIT'
[Unit]
Description=Xboard Node Backend (node %i)
Documentation=https://github.com/cedar2025/xboard-node
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xboard-node -c /etc/xboard-node/%i/config.yml
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    log_info "systemd 模板已安装: ${SERVICE_TEMPLATE}"
}

# ─── 迁移旧版单节点配置 ──────────────────────────────────────────────

migrate_legacy_config() {
    if [ -f "${CONFIG_DIR}/config.yml" ] && [ ! -d "${CONFIG_DIR}/config.yml" ]; then
        local legacy_id
        legacy_id=$(grep -E '^\s*node_id:\s*' "${CONFIG_DIR}/config.yml" 2>/dev/null | head -1 | sed 's/[^0-9]*//g')

        if [ -z "$legacy_id" ]; then
            legacy_id="default"
        fi

        if [ ! -d "${CONFIG_DIR}/${legacy_id}" ]; then
            log_warn "检测到旧版单节点配置，正在迁移到多节点目录布局: node ${legacy_id}"
            mkdir -p "${CONFIG_DIR}/${legacy_id}"
            mv "${CONFIG_DIR}/config.yml" "${CONFIG_DIR}/${legacy_id}/config.yml"

            if command -v systemctl >/dev/null 2>&1; then
                systemctl stop xboard-node 2>/dev/null || true
                systemctl disable xboard-node 2>/dev/null || true
                rm -f /etc/systemd/system/xboard-node.service

                install_systemd_template
                systemctl enable "xboard-node@${legacy_id}" 2>/dev/null || true
                systemctl start "xboard-node@${legacy_id}" 2>/dev/null || true
                log_info "服务已迁移: xboard-node → xboard-node@${legacy_id}"
            fi
        fi
    fi
}

# ─── 交互式输入 ──────────────────────────────────────────────────────

prompt_missing_params() {
    echo ""
    log_step "=== 节点配置 ==="
    echo ""

    if [ -z "$PANEL_URL" ]; then
        read -rp "  面板地址 (例如 https://panel.example.com): " PANEL_URL
    else
        echo -e "  面板地址: ${CYAN}${PANEL_URL}${NC}"
    fi

    if [ -z "$PANEL_TOKEN" ]; then
        read -rp "  服务端令牌: " PANEL_TOKEN
    else
        echo -e "  服务端令牌: ${CYAN}${PANEL_TOKEN:0:8}***${NC}"
    fi

    if [ -z "$NODE_ID" ]; then
        read -rp "  节点 ID: " NODE_ID
    else
        echo -e "  节点 ID: ${CYAN}${NODE_ID}${NC}"
    fi

    if [ -n "$NODE_TYPE" ]; then
        echo -e "  节点类型: ${CYAN}${NODE_TYPE}${NC}"
    fi

    if [ -n "$KERNEL_TYPE" ] && [ "$KERNEL_TYPE" != "singbox" ]; then
        echo -e "  内核类型: ${CYAN}${KERNEL_TYPE}${NC}"
    else
        echo ""
        echo "  内核类型:"
        echo "    1) singbox (默认，推荐)"
        echo "    2) xray"
        read -rp "  请选择 [1/2]: " KERNEL_CHOICE
        case "$KERNEL_CHOICE" in
            2) KERNEL_TYPE="xray" ;;
            *) KERNEL_TYPE="singbox" ;;
        esac
    fi

    if [ -z "$GOMEMLIMIT" ]; then
        read -rp "  Go 内存软上限 (例如 256MiB，留空跳过): " GOMEMLIMIT
    else
        echo -e "  Go 内存软上限: ${CYAN}${GOMEMLIMIT}${NC}"
    fi

    if [ -z "$GOGC" ]; then
        read -rp "  GOGC 百分比 (例如 50，留空跳过): " GOGC
    else
        echo -e "  GOGC 百分比: ${CYAN}${GOGC}${NC}"
    fi

    echo ""
    validate_params
}

# ─── 节点操作 ────────────────────────────────────────────────────────

write_node_config() {
    local node_id="$1"
    local node_dir="${CONFIG_DIR}/${node_id}"
    local runtime_block=""

    mkdir -p "$node_dir"

    local node_type_line=""
    if [ -n "$NODE_TYPE" ]; then
        node_type_line="  node_type: \"${NODE_TYPE}\""
    fi

    if [ -n "$GOMEMLIMIT" ] || [ -n "$GOGC" ]; then
        runtime_block="runtime:"
        if [ -n "$GOMEMLIMIT" ]; then
            runtime_block="${runtime_block}
  gomemlimit: \"${GOMEMLIMIT}\""
        fi
        if [ -n "$GOGC" ]; then
            runtime_block="${runtime_block}
  gogc: ${GOGC}"
        fi
    fi

    cat > "${node_dir}/config.yml" << EOF
panel:
  url: "${PANEL_URL}"
  token: "${PANEL_TOKEN}"
  node_id: ${node_id}
${node_type_line}

node:
  push_interval: 0
  pull_interval: 0

kernel:
  type: "${KERNEL_TYPE}"
  config_dir: "${node_dir}"
  log_level: "warn"

${runtime_block}

log:
  level: "info"
  output: "stdout"
EOF

    log_info "配置已写入: ${node_dir}/config.yml"
}

add_node_native() {
    local node_id="$1"

    if [ -d "${CONFIG_DIR}/${node_id}" ]; then
        log_error "节点 ${node_id} 已存在: ${CONFIG_DIR}/${node_id}/"
        log_info "如需重新配置，请先删除: $0 remove ${node_id}"
        exit 1
    fi

    write_node_config "$node_id"

    if command -v systemctl >/dev/null 2>&1; then
        install_systemd_template
        systemctl enable "xboard-node@${node_id}"
        systemctl start "xboard-node@${node_id}"
        log_info "服务已启动: xboard-node@${node_id}"
    else
        log_warn "未检测到 systemd，请手动运行:"
        echo "  xboard-node -c ${CONFIG_DIR}/${node_id}/config.yml"
    fi
}

add_node_docker() {
    local node_id="$1"

    if [ -d "${CONFIG_DIR}/${node_id}" ]; then
        log_error "节点 ${node_id} 已存在: ${CONFIG_DIR}/${node_id}/"
        log_info "如需重新配置，请先删除: $0 remove ${node_id}"
        exit 1
    fi

    write_node_config "$node_id"
    regenerate_docker_compose
    log_info "Docker Compose 已更新: ${DOCKER_COMPOSE_FILE}"

    if command -v docker >/dev/null 2>&1; then
        if docker compose version >/dev/null 2>&1; then
            COMPOSE_CMD="docker compose"
        elif command -v docker-compose >/dev/null 2>&1; then
            COMPOSE_CMD="docker-compose"
        else
            log_warn "未找到 docker compose，请手动启动:"
            echo "  cd ${CONFIG_DIR} && docker compose up -d"
            return
        fi
        cd "${CONFIG_DIR}"
        ${COMPOSE_CMD} up -d "node-${node_id}"
        log_info "容器已启动: xboard-node-${node_id}"
    else
        log_warn "未检测到 Docker，请先安装后再执行:"
        echo "  cd ${CONFIG_DIR} && docker compose up -d"
    fi
}

regenerate_docker_compose() {
    local nodes=()
    for dir in "${CONFIG_DIR}"/*/; do
        [ -f "${dir}config.yml" ] || continue
        local nid
        nid=$(basename "$dir")
        nodes+=("$nid")
    done

    if [ ${#nodes[@]} -eq 0 ]; then
        rm -f "${DOCKER_COMPOSE_FILE}"
        return
    fi

    cat > "${DOCKER_COMPOSE_FILE}" << 'HEADER'
# Auto-generated by install.sh — do not edit manually.
# Regenerated each time a node is added or removed.

services:
HEADER

    for nid in "${nodes[@]}"; do
        cat >> "${DOCKER_COMPOSE_FILE}" << EOF
  node-${nid}:
    image: ${DOCKER_IMAGE}
    container_name: xboard-node-${nid}
    restart: always
    network_mode: host
    volumes:
      - ./${nid}/config.yml:/etc/xboard-node/config.yml:ro
      - ./${nid}:/etc/xboard-node/data
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

EOF
    done
}

# ─── 部署入口 ────────────────────────────────────────────────────────

deploy_node() {
    if has_all_params; then
        validate_params
        log_info "开始部署节点 ${NODE_ID} (${KERNEL_TYPE}) → ${PANEL_URL}"
    else
        prompt_missing_params
    fi

    if [ "$DOCKER_MODE" -eq 1 ]; then
        add_node_docker "$NODE_ID"
    else
        add_node_native "$NODE_ID"
    fi

    echo ""
    echo -e "${GREEN}=== 节点 ${NODE_ID} 部署完成 ===${NC}"
    echo ""

    if [ "$DOCKER_MODE" -eq 1 ]; then
        echo "  管理命令:"
        echo "    日志:    docker logs -f xboard-node-${NODE_ID}"
        echo "    停止:    cd ${CONFIG_DIR} && docker compose stop node-${NODE_ID}"
        echo "    重启:    cd ${CONFIG_DIR} && docker compose restart node-${NODE_ID}"
    else
        echo "  管理命令:"
        echo "    状态:    systemctl status xboard-node@${NODE_ID}"
        echo "    日志:    journalctl -u xboard-node@${NODE_ID} -f"
        echo "    停止:    systemctl stop xboard-node@${NODE_ID}"
        echo "    重启:    systemctl restart xboard-node@${NODE_ID}"
    fi

    if [ -n "$GOMEMLIMIT" ] || [ -n "$GOGC" ]; then
        echo ""
        echo "  运行时内存调优:"
        [ -n "$GOMEMLIMIT" ] && echo "    GOMEMLIMIT: ${GOMEMLIMIT}"
        [ -n "$GOGC" ] && echo "    GOGC:       ${GOGC}"
    fi

    echo ""
    echo "  配置文件: ${CONFIG_DIR}/${NODE_ID}/config.yml"
    echo ""
}

# ─── 删除节点 ────────────────────────────────────────────────────────

remove_node() {
    local node_id="$1"

    if [ -z "$node_id" ]; then
        log_error "用法: $0 remove <node_id>"
        exit 1
    fi

    if [ ! -d "${CONFIG_DIR}/${node_id}" ]; then
        log_error "未找到节点 ${node_id}"
        exit 1
    fi

    log_step "正在删除节点 ${node_id}..."

    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop "xboard-node@${node_id}" 2>/dev/null || true
        systemctl disable "xboard-node@${node_id}" 2>/dev/null || true
        log_info "systemd 服务已停止并禁用"
    fi

    if command -v docker >/dev/null 2>&1; then
        docker rm -f "xboard-node-${node_id}" 2>/dev/null || true
    fi

    rm -rf "${CONFIG_DIR}/${node_id}"
    log_info "已删除配置目录: ${CONFIG_DIR}/${node_id}/"

    regenerate_docker_compose
    log_info "节点 ${node_id} 已删除"
}

# ─── 列出节点 ────────────────────────────────────────────────────────

list_nodes() {
    echo ""
    echo -e "${BOLD}  已部署节点${NC}"
    echo -e "  ────────────────────────────────────────────"

    local found=0
    for dir in "${CONFIG_DIR}"/*/; do
        [ -f "${dir}config.yml" ] || continue
        found=1

        local nid
        nid=$(basename "$dir")

        local panel_url kernel_type
        panel_url=$(grep -E '^\s*url:' "${dir}config.yml" 2>/dev/null | head -1 | sed 's/.*url:\s*"\?\([^"]*\)"\?.*/\1/')
        kernel_type=$(grep -E '^\s*type:' "${dir}config.yml" 2>/dev/null | head -1 | sed 's/.*type:\s*"\?\([^"]*\)"\?.*/\1/')

        local status="${RED}stopped${NC}"
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active "xboard-node@${nid}" >/dev/null 2>&1; then
                status="${GREEN}running (systemd)${NC}"
            fi
        fi
        if command -v docker >/dev/null 2>&1; then
            if docker inspect -f '{{.State.Running}}' "xboard-node-${nid}" 2>/dev/null | grep -q true; then
                status="${GREEN}running (docker)${NC}"
            fi
        fi

        printf "  ${BOLD}Node %-6s${NC}  kernel=%-8s  panel=%s\n" "$nid" "${kernel_type:-singbox}" "${panel_url:-unknown}"
        echo -e "              status=${status}"
        echo ""
    done

    if [ "$found" -eq 0 ]; then
        echo "  目前还没有已部署节点。"
        echo ""
        echo "  可以先部署第一个节点:"
        echo "    $0 -a https://panel.example.com -t TOKEN -n 1"
        echo "    $0 -a https://panel.example.com -t TOKEN -n 1 --gomemlimit 256MiB --gogc 50"
        echo "    $0 -a https://panel.example.com -t TOKEN -n 1 --docker"
    fi
    echo ""
}

# ─── 更新 / 卸载 ─────────────────────────────────────────────────────

update_binary() {
    log_step "更新 xboard-node 二进制..."

    detect_arch

    local url="https://github.com/cedar2025/xboard-node/releases/latest/download/xboard-node-linux-${ARCH}"
    local tmp="/tmp/xboard-node-update"

    if wget -q "$url" -O "$tmp" 2>/dev/null || curl -fsSL "$url" -o "$tmp" 2>/dev/null; then
        chmod +x "$tmp"
        mv "$tmp" "${INSTALL_DIR}/xboard-node"
        log_info "二进制更新完成"
    else
        log_error "更新下载失败"
        rm -f "$tmp"
        exit 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        for dir in "${CONFIG_DIR}"/*/; do
            [ -f "${dir}config.yml" ] || continue
            local nid
            nid=$(basename "$dir")
            if systemctl is-active "xboard-node@${nid}" >/dev/null 2>&1; then
                systemctl restart "xboard-node@${nid}"
                log_info "已重启: xboard-node@${nid}"
            fi
        done
    fi

    if [ -f "${DOCKER_COMPOSE_FILE}" ] && command -v docker >/dev/null 2>&1; then
        log_info "如需更新 Docker 节点，请执行:"
        echo "  cd ${CONFIG_DIR} && docker compose pull && docker compose up -d"
    fi
}

do_uninstall() {
    log_step "卸载 xboard-node..."

    if command -v systemctl >/dev/null 2>&1; then
        for dir in "${CONFIG_DIR}"/*/; do
            [ -f "${dir}config.yml" ] || continue
            local nid
            nid=$(basename "$dir")
            systemctl stop "xboard-node@${nid}" 2>/dev/null || true
            systemctl disable "xboard-node@${nid}" 2>/dev/null || true
        done
        systemctl stop xboard-node 2>/dev/null || true
        systemctl disable xboard-node 2>/dev/null || true
        rm -f /etc/systemd/system/xboard-node.service
        rm -f "/etc/systemd/system/${SERVICE_TEMPLATE}"
        systemctl daemon-reload
    fi

    if command -v docker >/dev/null 2>&1; then
        for dir in "${CONFIG_DIR}"/*/; do
            [ -f "${dir}config.yml" ] || continue
            local nid
            nid=$(basename "$dir")
            docker rm -f "xboard-node-${nid}" 2>/dev/null || true
        done
    fi

    rm -f "${INSTALL_DIR}/xboard-node"
    log_info "二进制已删除"

    echo ""
    read -rp "  是否删除所有配置? (${CONFIG_DIR}) [y/N]: " DELETE_ALL
    if [[ "$DELETE_ALL" =~ ^[Yy]$ ]]; then
        rm -rf "${CONFIG_DIR}"
        log_info "所有配置已删除"
    else
        log_info "配置保留在 ${CONFIG_DIR}/"
    fi

    log_info "xboard-node 已卸载"
}

# ─── 帮助信息 ────────────────────────────────────────────────────────

print_help() {
    cat << 'HELP'

  xboard-node 部署脚本

  本机部署（默认，推荐，适合减少 Docker 内存占用）:

    install.sh -a <url> -t <token> -n <node_id> [-T <node_type>] [-k singbox|xray] [--gomemlimit 256MiB] [--gogc 50]

  Docker 部署:

    install.sh -a <url> -t <token> -n <node_id> [--docker]

  参数说明:
    -a, --api          面板地址          (例如 https://panel.example.com)
    -t, --token        服务端令牌        (面板节点设置中的 Token)
    -n, --node-id      节点 ID           (正整数)
    -T, --node-type    节点类型          (可选，可由面板自动识别)
    -k, --kernel       内核类型          (singbox 或 xray，默认: singbox)
        --gomemlimit   Go 内存软上限     (例如 256MiB、512MiB)
        --gogc         Go GC 百分比      (例如 50、100)
        --docker       使用 Docker 部署  (默认不开启)

  示例:

    # 本机部署节点 1（sing-box）
    bash install.sh -a https://panel.example.com -t mytoken123 -n 1

    # 本机部署节点 2（xray）并限制内存
    bash install.sh -a https://panel.example.com -t mytoken123 -n 2 -k xray --gomemlimit 256MiB --gogc 50

    # Docker 部署节点 3
    bash install.sh -a https://panel.example.com -t mytoken123 -n 3 --docker

    # 交互模式
    bash install.sh

  管理命令:

    bash install.sh list               列出所有已部署节点
    bash install.sh remove <node_id>   删除指定节点
    bash install.sh update             更新二进制并重启原生节点
    bash install.sh uninstall          卸载全部内容

  Docker 环境变量模式（无需配置文件）:

    docker run -d --restart=always --network=host \
      -e apiHost=https://panel.example.com \
      -e apiKey=YOUR_TOKEN \
      -e nodeID=1 \
      ghcr.io/cedar2025/xboard-node:latest

HELP
}

# ─── 主程序 ──────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    case "$SUBCOMMAND" in
        remove)
            check_root
            remove_node "$NODE_ID"
            ;;
        list)
            list_nodes
            ;;
        update)
            check_root
            update_binary
            ;;
        uninstall)
            check_root
            do_uninstall
            ;;
        help|--help|-h)
            print_help
            ;;
        add|"")
            check_root
            detect_arch
            detect_os
            install_deps
            mkdir -p "$CONFIG_DIR"
            migrate_legacy_config

            if [ "$DOCKER_MODE" -eq 0 ]; then
                install_binary
                install_systemd_template
            fi

            deploy_node
            ;;
        *)
            log_error "未知命令: $SUBCOMMAND"
            print_help
            exit 1
            ;;
    esac
}

main "$@"