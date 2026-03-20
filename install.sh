#!/bin/bash
set -e

# xboard-node 多节点部署脚本
# 支持: Ubuntu 20+, Debian 11+, CentOS 8+, Alpine 3.18+
#
# 本机一键部署（默认，不带 --docker）:
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 1
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 2 -k xray
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 3 --gomemlimit 256MiB --gogc 50
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 3 --egress-socks5 127.0.0.1:1080
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 4 --cert-domain node.example.com
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 5 --cert-mode dns --cert-domain node.example.com --cert-dns-provider cloudflare --cert-dns-env CF_API_TOKEN=xxxx
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
RELEASE_REPO_DEFAULT="Micah123321/Xboard-Node"
RELEASE_REPO="${XBOARD_RELEASE_REPO:-$RELEASE_REPO_DEFAULT}"
RELEASE_REPO_LC="$(printf '%s' "$RELEASE_REPO" | tr '[:upper:]' '[:lower:]')"
REPO_URL="https://github.com/${RELEASE_REPO}"
RELEASES_BASE_URL="${REPO_URL}/releases"
DOCKER_IMAGE="ghcr.io/${RELEASE_REPO_LC}:latest"

# 解析后的参数
PANEL_URL=""
PANEL_TOKEN=""
NODE_ID=""
NODE_TYPE=""
KERNEL_TYPE="singbox"
GOMEMLIMIT=""
GOGC=""
EGRESS_SOCKS5=""
EGRESS_SOCKS5_HOST=""
EGRESS_SOCKS5_PORT=""
EGRESS_SOCKS5_USER=""
EGRESS_SOCKS5_PASS=""
CERT_MODE=""
CERT_DOMAIN=""
CERT_EMAIL=""
CERT_HTTP_PORT=""
CERT_DNS_PROVIDER=""
CERT_DNS_ENV_ITEMS=()
DOCKER_MODE=0
SUBCOMMAND=""

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} ${BOLD}$1${NC}"; }

has_cert_inputs() {
    [ -n "$CERT_MODE" ] || [ -n "$CERT_DOMAIN" ] || [ -n "$CERT_EMAIL" ] || \
    [ -n "$CERT_HTTP_PORT" ] || [ -n "$CERT_DNS_PROVIDER" ] || [ ${#CERT_DNS_ENV_ITEMS[@]} -gt 0 ]
}

effective_cert_mode() {
    if [ -n "$CERT_MODE" ]; then
        printf '%s' "$CERT_MODE"
        return
    fi
    if [ -n "$CERT_DNS_PROVIDER" ] || [ ${#CERT_DNS_ENV_ITEMS[@]} -gt 0 ]; then
        printf 'dns'
        return
    fi
    if [ -n "$CERT_DOMAIN" ] || [ -n "$CERT_EMAIL" ] || [ -n "$CERT_HTTP_PORT" ]; then
        printf 'http'
        return
    fi
    printf ''
}

cert_mode_label() {
    case "$1" in
        http) printf 'ACME HTTP-01' ;;
        dns) printf 'ACME DNS-01' ;;
        self) printf '自签证书' ;;
        file) printf '文件证书' ;;
        content) printf '内联证书' ;;
        none) printf '不启用固定证书' ;;
        *) printf '未显式配置' ;;
    esac
}

parse_socks5_endpoint() {
    local endpoint="$1"
    local host=""
    local port=""

    if [[ "$endpoint" =~ ^\[([^\]]+)\]:([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    elif [[ "$endpoint" =~ ^([^:]+):([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    EGRESS_SOCKS5_HOST="$host"
    EGRESS_SOCKS5_PORT="$port"
    return 0
}

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
            --egress-socks5) EGRESS_SOCKS5="$2";  shift 2 ;;
            --egress-socks5-user) EGRESS_SOCKS5_USER="$2"; shift 2 ;;
            --egress-socks5-pass) EGRESS_SOCKS5_PASS="$2"; shift 2 ;;
            --cert-mode)     CERT_MODE="$2";      shift 2 ;;
            --cert-domain)   CERT_DOMAIN="$2";    shift 2 ;;
            --cert-email)    CERT_EMAIL="$2";     shift 2 ;;
            --cert-http-port) CERT_HTTP_PORT="$2"; shift 2 ;;
            --cert-dns-provider) CERT_DNS_PROVIDER="$2"; shift 2 ;;
            --cert-dns-env)  CERT_DNS_ENV_ITEMS+=("$2"); shift 2 ;;
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

    CERT_MODE="$(printf '%s' "$CERT_MODE" | tr '[:upper:]' '[:lower:]')"
    CERT_DNS_PROVIDER="$(printf '%s' "$CERT_DNS_PROVIDER" | tr '[:upper:]' '[:lower:]')"

    case "$CERT_DNS_PROVIDER" in
        cf) CERT_DNS_PROVIDER="cloudflare" ;;
        aliyun) CERT_DNS_PROVIDER="alidns" ;;
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

    if [ -n "$EGRESS_SOCKS5" ]; then
        if ! parse_socks5_endpoint "$EGRESS_SOCKS5"; then
            log_error "SOCKS5 出站格式无效: ${EGRESS_SOCKS5}，必须是 host:port 或 [ipv6]:port"
            exit 1
        fi
    fi

    if { [ -n "$EGRESS_SOCKS5_USER" ] && [ -z "$EGRESS_SOCKS5_PASS" ]; } || \
       { [ -z "$EGRESS_SOCKS5_USER" ] && [ -n "$EGRESS_SOCKS5_PASS" ]; }; then
        log_error "SOCKS5 账号和密码必须同时提供 (--egress-socks5-user / --egress-socks5-pass)"
        exit 1
    fi

    if ([ -n "$EGRESS_SOCKS5_USER" ] || [ -n "$EGRESS_SOCKS5_PASS" ]) && [ -z "$EGRESS_SOCKS5" ]; then
        log_error "配置 SOCKS5 认证时必须同时提供 --egress-socks5 host:port"
        exit 1
    fi

    local cert_mode_resolved
    cert_mode_resolved="$(effective_cert_mode)"

    case "$cert_mode_resolved" in
        ""|none|http|dns|self) ;;
        *)
            log_error "不支持的证书模式: ${CERT_MODE}，可选值: http, dns, self, none"
            exit 1
            ;;
    esac

    if [ -n "$CERT_HTTP_PORT" ] && ! [[ "$CERT_HTTP_PORT" =~ ^[1-9][0-9]*$ ]]; then
        log_error "证书 HTTP 验证端口必须是正整数，当前值: $CERT_HTTP_PORT"
        exit 1
    fi

    if [ "$cert_mode_resolved" = "http" ] || [ "$cert_mode_resolved" = "dns" ]; then
        if [ -z "$CERT_DOMAIN" ]; then
            log_error "ACME 模式必须提供证书域名 (--cert-domain)"
            exit 1
        fi
    fi

    if [ "$cert_mode_resolved" = "dns" ]; then
        if [ -z "$CERT_DNS_PROVIDER" ]; then
            log_error "ACME DNS-01 模式必须提供 DNS Provider (--cert-dns-provider)"
            exit 1
        fi
        if [ ${#CERT_DNS_ENV_ITEMS[@]} -eq 0 ]; then
            log_error "ACME DNS-01 模式必须至少提供一组 DNS 凭据 (--cert-dns-env KEY=VALUE)"
            exit 1
        fi
    fi

    local item key value
    for item in "${CERT_DNS_ENV_ITEMS[@]}"; do
        if [[ "$item" != *=* ]]; then
            log_error "DNS 凭据格式无效: ${item}，必须是 KEY=VALUE"
            exit 1
        fi
        key="${item%%=*}"
        value="${item#*=}"
        if [ -z "$key" ] || [ -z "$value" ]; then
            log_error "DNS 凭据格式无效: ${item}，KEY 和 VALUE 都不能为空"
            exit 1
        fi
    done
}

prompt_cert_settings() {
    local cert_choice=""
    local cert_mode_resolved=""
    local dns_choice=""
    local cf_token=""
    local ali_key_id=""
    local ali_key_secret=""

    if ! has_cert_inputs; then
        echo ""
        echo "  TLS 证书:"
        echo "    1) 自动申请 ACME HTTP-01（推荐，需要 80 端口可访问）"
        echo "    2) 自动申请 ACME DNS-01（适合被 CDN 代理或 80 不可用）"
        echo "    3) 使用自签证书"
        echo "    4) 暂不设置（协议需要证书时自动回退自签）"
        read -rp "  请选择 [1/2/3/4，默认4]: " cert_choice
        case "$cert_choice" in
            1) CERT_MODE="http" ;;
            2) CERT_MODE="dns" ;;
            3) CERT_MODE="self" ;;
            *) CERT_MODE="" ;;
        esac
    fi

    cert_mode_resolved="$(effective_cert_mode)"

    case "$cert_mode_resolved" in
        http)
            if [ -z "$CERT_DOMAIN" ]; then
                read -rp "  ACME 域名 (例如 node.example.com): " CERT_DOMAIN
            fi
            if [ -z "$CERT_EMAIL" ]; then
                read -rp "  ACME 邮箱 (可选，留空跳过): " CERT_EMAIL
            fi
            if [ -z "$CERT_HTTP_PORT" ]; then
                read -rp "  HTTP-01 验证端口 (默认 80): " CERT_HTTP_PORT
            fi
            ;;
        dns)
            if [ -z "$CERT_DOMAIN" ]; then
                read -rp "  ACME 域名 (例如 node.example.com): " CERT_DOMAIN
            fi
            if [ -z "$CERT_EMAIL" ]; then
                read -rp "  ACME 邮箱 (可选，留空跳过): " CERT_EMAIL
            fi
            if [ -z "$CERT_DNS_PROVIDER" ]; then
                echo "  DNS Provider:"
                echo "    1) cloudflare"
                echo "    2) alidns"
                read -rp "  请选择 [1/2]: " dns_choice
                case "$dns_choice" in
                    2) CERT_DNS_PROVIDER="alidns" ;;
                    *) CERT_DNS_PROVIDER="cloudflare" ;;
                esac
            fi
            if [ ${#CERT_DNS_ENV_ITEMS[@]} -eq 0 ]; then
                case "$CERT_DNS_PROVIDER" in
                    cloudflare)
                        read -rp "  Cloudflare API Token: " cf_token
                        if [ -n "$cf_token" ]; then
                            CERT_DNS_ENV_ITEMS=("CF_API_TOKEN=${cf_token}")
                        fi
                        ;;
                    alidns)
                        read -rp "  AliDNS Access Key ID: " ali_key_id
                        read -rp "  AliDNS Access Key Secret: " ali_key_secret
                        if [ -n "$ali_key_id" ] && [ -n "$ali_key_secret" ]; then
                            CERT_DNS_ENV_ITEMS=("ALICLOUD_ACCESS_KEY_ID=${ali_key_id}" "ALICLOUD_ACCESS_KEY_SECRET=${ali_key_secret}")
                        fi
                        ;;
                esac
            fi
            ;;
        self)
            if [ -z "$CERT_DOMAIN" ]; then
                read -rp "  自签证书域名/IP (可选，留空将按节点信息自动推断): " CERT_DOMAIN
            fi
            ;;
    esac
}

prompt_egress_settings() {
    if [ -z "$EGRESS_SOCKS5" ]; then
        echo ""
        read -rp "  默认 SOCKS5 出站 (host:port，留空则不设置): " EGRESS_SOCKS5
    else
        echo -e "  默认 SOCKS5 出站: ${CYAN}${EGRESS_SOCKS5}${NC}"
    fi

    if [ -n "$EGRESS_SOCKS5" ]; then
        if [ -z "$EGRESS_SOCKS5_USER" ]; then
            read -rp "  SOCKS5 用户名 (可选，留空跳过): " EGRESS_SOCKS5_USER
        else
            echo -e "  SOCKS5 用户名: ${CYAN}${EGRESS_SOCKS5_USER}${NC}"
        fi

        if [ -n "$EGRESS_SOCKS5_USER" ] && [ -z "$EGRESS_SOCKS5_PASS" ]; then
            read -rp "  SOCKS5 密码: " EGRESS_SOCKS5_PASS
        elif [ -n "$EGRESS_SOCKS5_PASS" ]; then
            echo -e "  SOCKS5 密码: ${CYAN}***${NC}"
        fi
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

download_release_asset() {
    local asset_name="$1"
    local dest="$2"
    local tmp
    local url
    local urls=(
        "${RELEASES_BASE_URL}/latest/download/${asset_name}"
        "${RELEASES_BASE_URL}/download/dev/${asset_name}"
    )

    tmp="$(mktemp)"
    for url in "${urls[@]}"; do
        log_info "尝试下载: ${url}"
        if wget -q "$url" -O "$tmp" 2>/dev/null || curl -fsSL "$url" -o "$tmp" 2>/dev/null; then
            mv "$tmp" "$dest"
            return 0
        fi
    done

    rm -f "$tmp"
    return 1
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
        log_info "正在从当前仓库 Releases 下载: ${REPO_URL}"
        if download_release_asset "xboard-node-linux-${ARCH}" "${INSTALL_DIR}/xboard-node"; then
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
Documentation=${REPO_URL}
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

    prompt_egress_settings
    prompt_cert_settings

    echo ""
    validate_params
}

# ─── 节点操作 ────────────────────────────────────────────────────────

write_node_config() {
    local node_id="$1"
    local node_dir="${CONFIG_DIR}/${node_id}"
    local runtime_block=""
    local egress_block=""
    local cert_block=""
    local cert_mode_resolved=""
    local item=""
    local key=""
    local value=""

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

    egress_block="  egress:
    enable_default_rules: true
    prefer_ipv4: true"

    if [ -n "$EGRESS_SOCKS5" ]; then
        egress_block="${egress_block}
    socks5:
      address: \"${EGRESS_SOCKS5_HOST}\"
      port: ${EGRESS_SOCKS5_PORT}"
        if [ -n "$EGRESS_SOCKS5_USER" ]; then
            egress_block="${egress_block}
      username: \"${EGRESS_SOCKS5_USER}\"
      password: \"${EGRESS_SOCKS5_PASS}\""
        fi
    fi

    cert_mode_resolved="$(effective_cert_mode)"
    if has_cert_inputs; then
        cert_block="cert:
  cert_mode: \"${cert_mode_resolved}\""
        if [ -n "$CERT_DOMAIN" ]; then
            cert_block="${cert_block}
  domain: \"${CERT_DOMAIN}\""
        fi
        if [ -n "$CERT_EMAIL" ]; then
            cert_block="${cert_block}
  email: \"${CERT_EMAIL}\""
        fi
        if [ -n "$CERT_HTTP_PORT" ]; then
            cert_block="${cert_block}
  http_port: ${CERT_HTTP_PORT}"
        fi
        if [ -n "$CERT_DNS_PROVIDER" ]; then
            cert_block="${cert_block}
  dns_provider: \"${CERT_DNS_PROVIDER}\""
        fi
        if [ ${#CERT_DNS_ENV_ITEMS[@]} -gt 0 ]; then
            cert_block="${cert_block}
  dns_env:"
            for item in "${CERT_DNS_ENV_ITEMS[@]}"; do
                key="${item%%=*}"
                value="${item#*=}"
                cert_block="${cert_block}
    ${key}: \"${value}\""
            done
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
${egress_block}

${cert_block}

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
    if [ -n "$EGRESS_SOCKS5" ]; then
        echo "  默认出站: SOCKS5"
        echo "    地址:      ${EGRESS_SOCKS5}"
        [ -n "$EGRESS_SOCKS5_USER" ] && echo "    用户名:    ${EGRESS_SOCKS5_USER}"
    else
        echo "  默认出站: 直连（内置防滥用拦截规则默认开启）"
    fi

    echo ""
    if has_cert_inputs; then
        local cert_mode_resolved
        cert_mode_resolved="$(effective_cert_mode)"
        echo "  证书策略: $(cert_mode_label "$cert_mode_resolved")"
        [ -n "$CERT_DOMAIN" ] && echo "    域名:      ${CERT_DOMAIN}"
        [ -n "$CERT_EMAIL" ] && echo "    邮箱:      ${CERT_EMAIL}"
        [ -n "$CERT_DNS_PROVIDER" ] && echo "    Provider:  ${CERT_DNS_PROVIDER}"
    else
        echo "  证书策略: 未显式配置；若协议需要 TLS，将自动回退为自签证书"
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

    local tmp="/tmp/xboard-node-update"

    log_info "正在从当前仓库 Releases 更新: ${REPO_URL}"
    if download_release_asset "xboard-node-linux-${ARCH}" "$tmp"; then
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

    install.sh -a <url> -t <token> -n <node_id> [-T <node_type>] [-k singbox|xray] [--gomemlimit 256MiB] [--gogc 50] [--egress-socks5 127.0.0.1:1080] [--cert-domain node.example.com]

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
        --egress-socks5 默认 SOCKS5 出站 (格式 host:port 或 [ipv6]:port)
        --egress-socks5-user SOCKS5 用户名
        --egress-socks5-pass SOCKS5 密码
        --cert-mode    证书模式          (http、dns、self、none)
        --cert-domain  证书域名          (ACME 必填；仅传域名时默认走 HTTP-01)
        --cert-email   ACME 邮箱         (可选，推荐)
        --cert-http-port HTTP-01 端口    (默认 80)
        --cert-dns-provider DNS Provider (cloudflare 或 alidns)
        --cert-dns-env DNS 凭据          (可重复传入，格式 KEY=VALUE)
        --docker       使用 Docker 部署  (默认不开启)

  示例:

    # 本机部署节点 1（sing-box）
    bash install.sh -a https://panel.example.com -t mytoken123 -n 1

    # 本机部署节点 2（xray）并限制内存
    bash install.sh -a https://panel.example.com -t mytoken123 -n 2 -k xray --gomemlimit 256MiB --gogc 50

    # 本机部署节点 3，所有默认出站经 SOCKS5 转发
    bash install.sh -a https://panel.example.com -t mytoken123 -n 3 --egress-socks5 127.0.0.1:1080

    # 本机部署节点 4，自动申请 ACME HTTP-01 证书
    bash install.sh -a https://panel.example.com -t mytoken123 -n 4 --cert-domain node.example.com

    # 本机部署节点 5，自动申请 ACME DNS-01 证书（Cloudflare）
    bash install.sh -a https://panel.example.com -t mytoken123 -n 5 --cert-mode dns --cert-domain node.example.com --cert-dns-provider cloudflare --cert-dns-env CF_API_TOKEN=xxxx

    # Docker 部署节点 6
    bash install.sh -a https://panel.example.com -t mytoken123 -n 6 --docker

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
      ghcr.io/micah123321/xboard-node:latest

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
