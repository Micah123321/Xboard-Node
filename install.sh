#!/usr/bin/env bash
set -euo pipefail

# mi-node native installer.
#
# Supported actions:
#   install   Configure /etc/mi-node/config.yml and start mi-node.service
#   status    Show service, binary, config and health status
#   upgrade   Replace mi-node/xbctl binaries and restart the service when active
#   egress    Manage default upstream egress for an existing instance
#   uninstall Stop service and remove binaries; config is kept unless --purge is set

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

RELEASE_REPO_DEFAULT="Micah123321/mi-node"
RELEASE_REPO="${MI_NODE_RELEASE_REPO:-$RELEASE_REPO_DEFAULT}"
REPO_URL="https://github.com/${RELEASE_REPO}"
RELEASES_BASE_URL="${REPO_URL}/releases"

INSTALL_ROOT="${MI_NODE_INSTALL_ROOT:-/etc/mi-node}"
INSTALL_DIR="${MI_NODE_INSTALL_DIR:-/usr/local/bin}"
CONFIG_FILE="${MI_NODE_CONFIG_FILE:-${INSTALL_ROOT}/config.yml}"
CREDENTIALS_FILE="${MI_NODE_CREDENTIALS_FILE:-${INSTALL_ROOT}/credentials.env}"
INSTALL_META="${MI_NODE_INSTALL_META:-${INSTALL_ROOT}/install-meta.json}"
BACKUP_DIR="${MI_NODE_BACKUP_DIR:-${INSTALL_ROOT}/backups}"
BINARY_PATH="${MI_NODE_BINARY_PATH:-${INSTALL_DIR}/mi-node}"
CLI_PATH="${MI_NODE_XBCTL_PATH:-${INSTALL_DIR}/xbctl}"
INSTALLER_COPY_PATH="${MI_NODE_INSTALLER_COPY_PATH:-${INSTALL_ROOT}/install.sh}"
SERVICE_NAME="mi-node.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

ACTION="install"
MODE="node"
PANEL_URL=""
TOKEN=""
NODE_ID=""
NODE_TYPE=""
MACHINE_ID=""
KERNEL_TYPE="singbox"
HEALTH_PORT="0"
DEBUG_PORT="0"
GOMEMLIMIT=""
GOGC=""
LOG_LEVEL="info"
KERNEL_LOG_LEVEL="warn"
RELEASE_VERSION="${MI_NODE_VERSION:-latest}"
BINARY_URL="${MI_NODE_BINARY_URL:-}"
XBCTL_URL="${MI_NODE_XBCTL_URL:-}"
YES=0
PURGE=0
SKIP_START=0

EGRESS_SOCKS5=""
EGRESS_SOCKS5_HOST=""
EGRESS_SOCKS5_PORT=""
EGRESS_SOCKS5_USER=""
EGRESS_SOCKS5_PASS=""
EGRESS_SHADOWSOCKS_URI=""

CERT_MODE=""
CERT_DOMAIN=""
CERT_EMAIL=""
CERT_HTTP_PORT=""
CERT_DNS_PROVIDER=""
CERT_DNS_ENV_ITEMS=()

ARCH=""
OS_ID=""
TMP_DIR=""
CURRENT_STATE="fresh"
SERVICE_WAS_ACTIVE=0
HAVE_XBCTL=0
REMOVE_ARGS=()
EGRESS_ARGS=()

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${CYAN}[STEP]${NC} ${BOLD}$*${NC}"; }

cleanup() {
    if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT

usage() {
    cat <<'HELP'
mi-node 原生部署脚本

用法:
  bash install.sh [install] -a <panel_url> -t <token> -n <node_id> [选项]
  bash install.sh install --mode machine -a <panel_url> -t <token> --machine-id <id> [选项]
  bash install.sh status
  bash install.sh upgrade [--version <tag>|--binary-url <url>|--xbctl-url <url>]
  bash install.sh egress list
  bash install.sh egress set --node-id <id> (--socks5-url <url>|--socks5 <host:port>|--shadowsocks-uri <ss://...>) [--no-restart]
  bash install.sh egress clear --node-id <id> [--no-restart]
  bash install.sh uninstall [--purge] [--yes]

常用参数:
  -a, --api, --panel-url <url>      面板地址
  -t, --token <token>               节点 token 或 machine token
  -n, --node-id <id>                节点 ID，node 模式必填
      --machine-id <id>             machine ID，machine 模式必填
      --mode node|machine           部署模式，默认 node
  -T, --node-type <type>            可选节点类型
  -k, --kernel singbox|xray         内核类型，默认 singbox
      --health-port <port>          健康检查端口，0 表示关闭
      --debug-port <port>           本地调试端口，0 表示关闭
      --gomemlimit <value>          Go 运行时软内存上限，例如 256MiB
      --gogc <percent>              GOGC 百分比，例如 50
      --version <tag>               Release tag，默认 latest
      --binary-url <url>            指定 mi-node 二进制下载地址
      --xbctl-url <url>             指定 xbctl 二进制下载地址
      --install-root <path>         安装配置目录，默认 /etc/mi-node
      --skip-start                  写入文件但不启动服务

默认出站:
      --egress-socks5 <host:port>
      --egress-socks5-user <user>
      --egress-socks5-pass <pass>
      --egress-shadowsocks-uri <ss://...>

证书:
      --cert-mode http|dns|self|file|none
      --cert-domain <domain>
      --cert-email <email>
      --cert-http-port <port>
      --cert-dns-provider cloudflare|alidns
      --cert-dns-env KEY=VALUE      可重复传入

示例:
  bash install.sh -a https://panel.example.com -t TOKEN -n 1
  bash install.sh -a https://panel.example.com -t TOKEN -n 1 -k xray --gomemlimit 256MiB --gogc 50
  bash install.sh --mode machine -a https://panel.example.com -t TOKEN --machine-id 100
  bash install.sh -a https://panel.example.com -t TOKEN -n 1 --egress-socks5 127.0.0.1:1080
  bash install.sh -a https://panel.example.com -t TOKEN -n 1 --cert-mode dns --cert-domain node.example.com --cert-dns-provider cloudflare --cert-dns-env CF_API_TOKEN=xxxx

管理:
  bash install.sh status
  bash install.sh upgrade
  bash install.sh egress list
  bash install.sh uninstall
  xbctl status
  xbctl list
  xbctl egress list
  xbctl service logs
HELP
}

need_value() {
    if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        log_error "$1 需要参数值"
        exit 1
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            install|status|upgrade|update|uninstall|list|help)
                ACTION="$1"
                [ "$ACTION" = "update" ] && ACTION="upgrade"
                shift
                ;;
            egress)
                ACTION="egress"
                shift
                EGRESS_ARGS=("$@")
                break
                ;;
            remove)
                ACTION="remove"
                shift
                REMOVE_ARGS=("$@")
                break
                ;;
            -h|--help)
                ACTION="help"
                shift
                ;;
            -a|--api|--panel|--panel-url)
                need_value "$1" "${2:-}"
                PANEL_URL="$2"
                shift 2
                ;;
            -t|--token)
                need_value "$1" "${2:-}"
                TOKEN="$2"
                shift 2
                ;;
            -n|--node-id)
                need_value "$1" "${2:-}"
                NODE_ID="$2"
                shift 2
                ;;
            -T|--node-type)
                need_value "$1" "${2:-}"
                NODE_TYPE="$2"
                shift 2
                ;;
            --machine-id)
                need_value "$1" "${2:-}"
                MACHINE_ID="$2"
                shift 2
                ;;
            --mode)
                need_value "$1" "${2:-}"
                MODE="$2"
                shift 2
                ;;
            -k|--kernel)
                need_value "$1" "${2:-}"
                KERNEL_TYPE="$2"
                shift 2
                ;;
            --health-port)
                need_value "$1" "${2:-}"
                HEALTH_PORT="$2"
                shift 2
                ;;
            --debug-port)
                need_value "$1" "${2:-}"
                DEBUG_PORT="$2"
                shift 2
                ;;
            --gomemlimit)
                need_value "$1" "${2:-}"
                GOMEMLIMIT="$2"
                shift 2
                ;;
            --gogc)
                need_value "$1" "${2:-}"
                GOGC="$2"
                shift 2
                ;;
            --version)
                need_value "$1" "${2:-}"
                RELEASE_VERSION="$2"
                shift 2
                ;;
            --binary-url)
                need_value "$1" "${2:-}"
                BINARY_URL="$2"
                shift 2
                ;;
            --xbctl-url)
                need_value "$1" "${2:-}"
                XBCTL_URL="$2"
                shift 2
                ;;
            --install-root)
                need_value "$1" "${2:-}"
                INSTALL_ROOT="$2"
                CONFIG_FILE="${INSTALL_ROOT}/config.yml"
                CREDENTIALS_FILE="${INSTALL_ROOT}/credentials.env"
                INSTALL_META="${INSTALL_ROOT}/install-meta.json"
                BACKUP_DIR="${INSTALL_ROOT}/backups"
                INSTALLER_COPY_PATH="${INSTALL_ROOT}/install.sh"
                shift 2
                ;;
            --skip-start)
                SKIP_START=1
                shift
                ;;
            --yes|-y)
                YES=1
                shift
                ;;
            --purge)
                PURGE=1
                shift
                ;;
            --egress-socks5)
                need_value "$1" "${2:-}"
                EGRESS_SOCKS5="$2"
                shift 2
                ;;
            --egress-socks5-user)
                need_value "$1" "${2:-}"
                EGRESS_SOCKS5_USER="$2"
                shift 2
                ;;
            --egress-socks5-pass)
                need_value "$1" "${2:-}"
                EGRESS_SOCKS5_PASS="$2"
                shift 2
                ;;
            --egress-shadowsocks-uri)
                need_value "$1" "${2:-}"
                EGRESS_SHADOWSOCKS_URI="$2"
                shift 2
                ;;
            --egress-shadowsocks|--egress-shadowsocks-method|--egress-shadowsocks-password)
                log_error "旧 Shadowsocks 参数已废弃，请使用 --egress-shadowsocks-uri 'ss://...'"
                exit 1
                ;;
            --cert-mode)
                need_value "$1" "${2:-}"
                CERT_MODE="$2"
                shift 2
                ;;
            --cert-domain)
                need_value "$1" "${2:-}"
                CERT_DOMAIN="$2"
                shift 2
                ;;
            --cert-email)
                need_value "$1" "${2:-}"
                CERT_EMAIL="$2"
                shift 2
                ;;
            --cert-http-port)
                need_value "$1" "${2:-}"
                CERT_HTTP_PORT="$2"
                shift 2
                ;;
            --cert-dns-provider)
                need_value "$1" "${2:-}"
                CERT_DNS_PROVIDER="$2"
                shift 2
                ;;
            --cert-dns-env)
                need_value "$1" "${2:-}"
                CERT_DNS_ENV_ITEMS+=("$2")
                shift 2
                ;;
            --docker)
                log_error "当前安装器只管理原生 mi-node.service。Docker 部署请使用 ghcr.io/micah123321/mi-node 镜像。"
                exit 1
                ;;
            *)
                log_error "未知参数: $1"
                usage
                exit 1
                ;;
        esac
    done

    MODE="$(printf '%s' "${MODE}" | tr '[:upper:]' '[:lower:]')"
    KERNEL_TYPE="$(printf '%s' "${KERNEL_TYPE}" | tr '[:upper:]' '[:lower:]')"
    CERT_MODE="$(printf '%s' "${CERT_MODE}" | tr '[:upper:]' '[:lower:]')"
    CERT_DNS_PROVIDER="$(printf '%s' "${CERT_DNS_PROVIDER}" | tr '[:upper:]' '[:lower:]')"
    case "${CERT_DNS_PROVIDER}" in
        cf) CERT_DNS_PROVIDER="cloudflare" ;;
        aliyun) CERT_DNS_PROVIDER="alidns" ;;
    esac
}

is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

validate_port() {
    local name="$1"
    local value="$2"
    if ! is_uint "${value}"; then
        log_error "${name} 必须是 0-65535 的整数，当前值: ${value}"
        exit 1
    fi
    if [ "${value}" -gt 65535 ]; then
        log_error "${name} 必须是 0-65535 的整数，当前值: ${value}"
        exit 1
    fi
}

parse_socks5_endpoint() {
    local endpoint="$1"
    if [[ "${endpoint}" =~ ^\[([^\]]+)\]:([0-9]+)$ ]]; then
        EGRESS_SOCKS5_HOST="${BASH_REMATCH[1]}"
        EGRESS_SOCKS5_PORT="${BASH_REMATCH[2]}"
        return 0
    fi
    if [[ "${endpoint}" =~ ^([^:]+):([0-9]+)$ ]]; then
        EGRESS_SOCKS5_HOST="${BASH_REMATCH[1]}"
        EGRESS_SOCKS5_PORT="${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

effective_cert_mode() {
    if [ -n "${CERT_MODE}" ]; then
        printf '%s' "${CERT_MODE}"
        return
    fi
    if [ -n "${CERT_DNS_PROVIDER}" ] || [ "${#CERT_DNS_ENV_ITEMS[@]}" -gt 0 ]; then
        printf 'dns'
        return
    fi
    if [ -n "${CERT_DOMAIN}" ] || [ -n "${CERT_EMAIL}" ] || [ -n "${CERT_HTTP_PORT}" ]; then
        printf 'http'
        return
    fi
    printf ''
}

has_cert_inputs() {
    [ -n "${CERT_MODE}" ] || [ -n "${CERT_DOMAIN}" ] || [ -n "${CERT_EMAIL}" ] || \
        [ -n "${CERT_HTTP_PORT}" ] || [ -n "${CERT_DNS_PROVIDER}" ] || [ "${#CERT_DNS_ENV_ITEMS[@]}" -gt 0 ]
}

validate_install_request() {
    if [ -z "${PANEL_URL}" ]; then
        log_error "必须提供面板地址 (-a/--api/--panel-url)"
        exit 1
    fi
    if [ -z "${TOKEN}" ]; then
        log_error "必须提供 token (-t/--token)"
        exit 1
    fi
    case "${MODE}" in
        node)
            if ! is_uint "${NODE_ID}" || [ "${NODE_ID:-0}" -le 0 ]; then
                log_error "node 模式必须提供正整数 --node-id"
                exit 1
            fi
            ;;
        machine)
            if ! is_uint "${MACHINE_ID}" || [ "${MACHINE_ID:-0}" -le 0 ]; then
                log_error "machine 模式必须提供正整数 --machine-id"
                exit 1
            fi
            ;;
        *)
            log_error "--mode 只能是 node 或 machine，当前值: ${MODE}"
            exit 1
            ;;
    esac
    case "${KERNEL_TYPE}" in
        singbox|xray) ;;
        *)
            log_error "--kernel 只能是 singbox 或 xray，当前值: ${KERNEL_TYPE}"
            exit 1
            ;;
    esac
    validate_port "health-port" "${HEALTH_PORT}"
    validate_port "debug-port" "${DEBUG_PORT}"
    if [ -n "${GOGC}" ] && ! is_uint "${GOGC}"; then
        log_error "--gogc 必须是非负整数，当前值: ${GOGC}"
        exit 1
    fi
    if [ -n "${EGRESS_SOCKS5}" ] && [ -n "${EGRESS_SHADOWSOCKS_URI}" ]; then
        log_error "SOCKS5 和 Shadowsocks 默认出站只能二选一"
        exit 1
    fi
    if [ -n "${EGRESS_SOCKS5}" ]; then
        if ! parse_socks5_endpoint "${EGRESS_SOCKS5}"; then
            log_error "--egress-socks5 格式必须是 host:port 或 [ipv6]:port"
            exit 1
        fi
        validate_port "egress-socks5 port" "${EGRESS_SOCKS5_PORT}"
    fi
    if { [ -n "${EGRESS_SOCKS5_USER}" ] && [ -z "${EGRESS_SOCKS5_PASS}" ]; } || \
        { [ -z "${EGRESS_SOCKS5_USER}" ] && [ -n "${EGRESS_SOCKS5_PASS}" ]; }; then
        log_error "SOCKS5 用户名和密码必须同时提供"
        exit 1
    fi
    if { [ -n "${EGRESS_SOCKS5_USER}" ] || [ -n "${EGRESS_SOCKS5_PASS}" ]; } && [ -z "${EGRESS_SOCKS5}" ]; then
        log_error "配置 SOCKS5 认证时必须同时提供 --egress-socks5"
        exit 1
    fi

    local cert_mode
    cert_mode="$(effective_cert_mode)"
    case "${cert_mode}" in
        ""|http|dns|self|file|none) ;;
        *)
            log_error "--cert-mode 只能是 http、dns、self、file 或 none，当前值: ${cert_mode}"
            exit 1
            ;;
    esac
    if [ -n "${CERT_HTTP_PORT}" ]; then
        validate_port "cert-http-port" "${CERT_HTTP_PORT}"
    fi
    if [ "${cert_mode}" = "http" ] || [ "${cert_mode}" = "dns" ]; then
        if [ -z "${CERT_DOMAIN}" ]; then
            log_error "cert_mode=${cert_mode} 时必须提供 --cert-domain"
            exit 1
        fi
    fi
    if [ "${cert_mode}" = "dns" ]; then
        if [ -z "${CERT_DNS_PROVIDER}" ]; then
            log_error "DNS-01 模式必须提供 --cert-dns-provider"
            exit 1
        fi
        if [ "${#CERT_DNS_ENV_ITEMS[@]}" -eq 0 ]; then
            log_error "DNS-01 模式必须至少提供一个 --cert-dns-env KEY=VALUE"
            exit 1
        fi
    fi
    for item in "${CERT_DNS_ENV_ITEMS[@]}"; do
        if [[ ! "${item}" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
            log_error "--cert-dns-env 格式必须是 KEY=VALUE，当前值: ${item}"
            exit 1
        fi
    done
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "请使用 root 运行此脚本"
        exit 1
    fi
}

ensure_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "原生安装需要 systemd/systemctl"
        exit 1
    fi
    if [ ! -d /run/systemd/system ]; then
        log_error "当前系统看起来未运行 systemd"
        exit 1
    fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l|armv7) ARCH="armv7" ;;
        *)
            log_error "不支持的 CPU 架构: $(uname -m)"
            exit 1
            ;;
    esac
}

detect_os() {
    OS_ID="unknown"
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
    fi
}

ensure_dirs() {
    mkdir -p "${INSTALL_ROOT}" "${BACKUP_DIR}" "${INSTALL_DIR}"
    chmod 755 "${INSTALL_ROOT}" "${INSTALL_DIR}"
}

download_url() {
    local url="$1"
    local dest="$2"
    local tmp
    tmp="$(mktemp)"
    log_info "下载: ${url}"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "${url}" -o "${tmp}"; then
            mv "${tmp}" "${dest}"
            return 0
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        if wget -q "${url}" -O "${tmp}"; then
            mv "${tmp}" "${dest}"
            return 0
        fi
    fi
    rm -f "${tmp}"
    return 1
}

release_url() {
    local asset="$1"
    if [ -z "${RELEASE_VERSION}" ] || [ "${RELEASE_VERSION}" = "latest" ]; then
        printf '%s/latest/download/%s' "${RELEASES_BASE_URL}" "${asset}"
        return
    fi
    printf '%s/download/%s/%s' "${RELEASES_BASE_URL}" "${RELEASE_VERSION}" "${asset}"
}

stage_asset() {
    local name="$1"
    local url="$2"
    local dest="$3"
    shift 3
    local candidate
    for candidate in "$@"; do
        if [ -f "${candidate}" ]; then
            cp "${candidate}" "${dest}"
            chmod +x "${dest}"
            log_info "使用本地 ${name}: ${candidate}"
            return 0
        fi
    done
    if [ -n "${url}" ]; then
        if download_url "${url}" "${dest}"; then
            chmod +x "${dest}"
            return 0
        fi
        return 1
    fi
    if download_url "$(release_url "${name}-linux-${ARCH}")" "${dest}"; then
        chmod +x "${dest}"
        return 0
    fi
    return 1
}

stage_binary() {
    log_step "准备 mi-node 二进制"
    if ! stage_asset "mi-node" "${BINARY_URL}" "${TMP_DIR}/mi-node" \
        "./mi-node-linux-${ARCH}" "./mi-node"; then
        log_error "无法获取 mi-node 二进制。请将 mi-node-linux-${ARCH} 放到当前目录，或使用 --binary-url 指定下载地址。"
        exit 1
    fi
}

stage_xbctl() {
    log_step "准备 xbctl 管理工具"
    if stage_asset "xbctl" "${XBCTL_URL}" "${TMP_DIR}/xbctl" \
        "./xbctl-linux-${ARCH}" "./xbctl"; then
        HAVE_XBCTL=1
        return
    fi
    log_error "无法获取 xbctl 管理工具。请将 xbctl-linux-${ARCH} 放到当前目录，或使用 --xbctl-url 指定下载地址。"
    exit 1
}

render_config() {
    local init_args=(
        config init
        --mode "${MODE}"
        --panel-url "${PANEL_URL}"
        --kernel "${KERNEL_TYPE}"
        --health-port "${HEALTH_PORT}"
        --debug-port "${DEBUG_PORT}"
        --token "${TOKEN}"
        --version "${RELEASE_VERSION}"
        --output "${TMP_DIR}/config.yml"
        --credentials-out "${TMP_DIR}/credentials.env"
        --meta "${TMP_DIR}/install-meta.json"
        --install-root "${INSTALL_ROOT}"
    )
    if [ -f "${CONFIG_FILE}" ]; then
        init_args+=(--config "${CONFIG_FILE}")
    fi
    if [ -f "${CREDENTIALS_FILE}" ]; then
        init_args+=(--credentials-in "${CREDENTIALS_FILE}")
    fi
    if [ "${MODE}" = "machine" ]; then
        init_args+=(--machine-id "${MACHINE_ID}")
    else
        init_args+=(--node-id "${NODE_ID}")
        [ -n "${NODE_TYPE}" ] && init_args+=(--node-type "${NODE_TYPE}")
    fi
    if [ -n "${GOMEMLIMIT}" ]; then
        init_args+=(--gomemlimit "${GOMEMLIMIT}")
    fi
    if [ -n "${GOGC}" ]; then
        init_args+=(--gogc "${GOGC}")
    fi
    if [ -n "${EGRESS_SOCKS5}" ]; then
        init_args+=(--egress-socks5-address "${EGRESS_SOCKS5_HOST}" --egress-socks5-port "${EGRESS_SOCKS5_PORT}")
        [ -n "${EGRESS_SOCKS5_USER}" ] && init_args+=(--egress-socks5-user "${EGRESS_SOCKS5_USER}")
        [ -n "${EGRESS_SOCKS5_PASS}" ] && init_args+=(--egress-socks5-pass "${EGRESS_SOCKS5_PASS}")
    fi
    if [ -n "${EGRESS_SHADOWSOCKS_URI}" ]; then
        init_args+=(--egress-shadowsocks-uri "${EGRESS_SHADOWSOCKS_URI}")
    fi
    local cert_mode
    cert_mode="$(effective_cert_mode)"
    [ -n "${cert_mode}" ] && init_args+=(--cert-mode "${cert_mode}")
    [ -n "${CERT_DOMAIN}" ] && init_args+=(--cert-domain "${CERT_DOMAIN}")
    [ -n "${CERT_EMAIL}" ] && init_args+=(--cert-email "${CERT_EMAIL}")
    [ -n "${CERT_HTTP_PORT}" ] && init_args+=(--cert-http-port "${CERT_HTTP_PORT}")
    [ -n "${CERT_DNS_PROVIDER}" ] && init_args+=(--cert-dns-provider "${CERT_DNS_PROVIDER}")
    local item
    for item in "${CERT_DNS_ENV_ITEMS[@]}"; do
        init_args+=(--cert-dns-env "${item}")
    done

    if ! "${TMP_DIR}/xbctl" "${init_args[@]}" >/dev/null; then
        log_error "xbctl config init failed"
        exit 1
    fi
    chmod 600 "${TMP_DIR}/config.yml"
    chmod 600 "${TMP_DIR}/credentials.env"
    chmod 600 "${TMP_DIR}/install-meta.json"
}

render_service() {
    cat > "${TMP_DIR}/${SERVICE_NAME}" <<EOF
[Unit]
Description=Mi Node Backend
Documentation=${REPO_URL}
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-${CREDENTIALS_FILE}
ExecStart=${BINARY_PATH} -c ${CONFIG_FILE}
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

detect_current_state() {
    CURRENT_STATE="fresh"
    SERVICE_WAS_ACTIVE=0
    if [ -f "${CONFIG_FILE}" ] || [ -f "${SERVICE_PATH}" ] || [ -x "${BINARY_PATH}" ]; then
        CURRENT_STATE="existing"
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
        SERVICE_WAS_ACTIVE=1
    fi
}

require_reconfigure_confirmation() {
    if [ "${CURRENT_STATE}" != "existing" ] || [ "${YES}" -eq 1 ]; then
        return
    fi
    echo ""
    log_warn "检测到已有 mi-node 安装。继续会先备份，再合并/替换当前实例配置并更新 ${SERVICE_PATH}。"
    read -r -p "继续安装/重配置? [y/N]: " answer
    if ! [[ "${answer}" =~ ^[Yy]$ ]]; then
        log_warn "已取消"
        exit 0
    fi
}

backup_existing_state() {
    if [ "${CURRENT_STATE}" != "existing" ]; then
        return
    fi
    local backup_path
    backup_path="${BACKUP_DIR}/$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "${backup_path}"
    [ -f "${CONFIG_FILE}" ] && cp -a "${CONFIG_FILE}" "${backup_path}/config.yml"
    [ -f "${CREDENTIALS_FILE}" ] && cp -a "${CREDENTIALS_FILE}" "${backup_path}/credentials.env"
    [ -f "${INSTALL_META}" ] && cp -a "${INSTALL_META}" "${backup_path}/install-meta.json"
    [ -f "${SERVICE_PATH}" ] && cp -a "${SERVICE_PATH}" "${backup_path}/${SERVICE_NAME}"
    [ -f "/etc/systemd/system/mi-node@.service" ] && cp -a "/etc/systemd/system/mi-node@.service" "${backup_path}/mi-node@.service"
    [ -x "${BINARY_PATH}" ] && cp -a "${BINARY_PATH}" "${backup_path}/mi-node"
    [ -x "${CLI_PATH}" ] && cp -a "${CLI_PATH}" "${backup_path}/xbctl"
    log_info "已有状态已备份到 ${backup_path}"
}

list_legacy_template_units() {
    systemctl list-units 'mi-node@*.service' --all --no-legend --no-pager 2>/dev/null |
        awk '{print $1}' |
        grep -E '^mi-node@.+\.service$' || true
}

stop_legacy_template_services() {
    local unit
    local found=0
    while IFS= read -r unit; do
        [ -z "${unit}" ] && continue
        found=1
        systemctl stop "${unit}" 2>/dev/null || true
        systemctl disable "${unit}" 2>/dev/null || true
    done < <(list_legacy_template_units)

    if [ -f "/etc/systemd/system/mi-node@.service" ]; then
        found=1
        rm -f "/etc/systemd/system/mi-node@.service"
    fi

    if [ "${found}" -eq 1 ]; then
        log_warn "已停用旧版 mi-node@.service 模板服务，避免与 ${SERVICE_NAME} 并行运行"
    fi
}

install_staged_files() {
    stop_legacy_template_services
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
        systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
    fi
    install -m 755 "${TMP_DIR}/mi-node" "${BINARY_PATH}"
    install -m 600 "${TMP_DIR}/config.yml" "${CONFIG_FILE}"
    install -m 600 "${TMP_DIR}/credentials.env" "${CREDENTIALS_FILE}"
    install -m 600 "${TMP_DIR}/install-meta.json" "${INSTALL_META}"
    install -m 644 "${TMP_DIR}/${SERVICE_NAME}" "${SERVICE_PATH}"
    if [ "${HAVE_XBCTL}" -eq 1 ]; then
        install -m 755 "${TMP_DIR}/xbctl" "${CLI_PATH}"
        ln -sf "${CLI_PATH}" /usr/bin/xbctl 2>/dev/null || true
    fi
    if [ -f "$0" ]; then
        install -m 755 "$0" "${INSTALLER_COPY_PATH}" 2>/dev/null || true
    fi
    systemctl daemon-reload
}

wait_for_health() {
    if [ "${HEALTH_PORT}" -le 0 ]; then
        return 0
    fi
    local url="http://127.0.0.1:${HEALTH_PORT}/healthz"
    local i
    for i in $(seq 1 20); do
        if command -v curl >/dev/null 2>&1 && curl -fsS "${url}" >/dev/null 2>&1; then
            log_info "健康检查通过: ${url}"
            return 0
        fi
        if command -v wget >/dev/null 2>&1 && wget -q -O - "${url}" >/dev/null 2>&1; then
            log_info "健康检查通过: ${url}"
            return 0
        fi
        sleep 1
    done
    log_warn "服务已启动，但健康检查暂未通过: ${url}"
    return 1
}

start_service() {
    if [ "${SKIP_START}" -eq 1 ]; then
        log_warn "已按 --skip-start 跳过服务启动"
        return
    fi
    systemctl enable --now "${SERVICE_NAME}"
    wait_for_health || true
}

perform_install() {
    validate_install_request
    check_root
    ensure_systemd
    detect_arch
    detect_os
    detect_current_state
    require_reconfigure_confirmation
    TMP_DIR="$(mktemp -d)"
    ensure_dirs
    stage_binary
    stage_xbctl
    render_config
    render_service
    backup_existing_state
    install_staged_files
    start_service
    log_info "安装完成"
    log_info "服务: ${SERVICE_NAME}"
    log_info "配置: ${CONFIG_FILE}"
    log_info "凭据: ${CREDENTIALS_FILE}"
    log_info "二进制: ${BINARY_PATH}"
    [ "${HAVE_XBCTL}" -eq 1 ] && log_info "管理工具: ${CLI_PATH}"
    log_info "查看日志: journalctl -u ${SERVICE_NAME} -n 100 -f"
    log_info "快速重启: systemctl restart ${SERVICE_NAME}"
}

perform_status() {
    echo "mi-node status"
    echo ""
    echo "  service: ${SERVICE_NAME}"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
            echo "  state:   running"
        else
            echo "  state:   $(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || true)"
        fi
    else
        echo "  state:   systemctl unavailable"
    fi
    echo "  binary:  ${BINARY_PATH} $([ -x "${BINARY_PATH}" ] && echo '(present)' || echo '(missing)')"
    echo "  config:  ${CONFIG_FILE} $([ -f "${CONFIG_FILE}" ] && echo '(present)' || echo '(missing)')"
    echo "  creds:   ${CREDENTIALS_FILE} $([ -f "${CREDENTIALS_FILE}" ] && echo '(present)' || echo '(missing)')"
    echo "  xbctl:   ${CLI_PATH} $([ -x "${CLI_PATH}" ] && echo '(present)' || echo '(missing)')"
    if [ -x "${CLI_PATH}" ]; then
        echo ""
        "${CLI_PATH}" list 2>/dev/null || true
    fi
}

perform_upgrade() {
    check_root
    ensure_systemd
    detect_arch
    detect_current_state
    TMP_DIR="$(mktemp -d)"
    ensure_dirs
    stage_binary
    stage_xbctl
    backup_existing_state
    install -m 755 "${TMP_DIR}/mi-node" "${BINARY_PATH}"
    if [ "${HAVE_XBCTL}" -eq 1 ]; then
        install -m 755 "${TMP_DIR}/xbctl" "${CLI_PATH}"
        ln -sf "${CLI_PATH}" /usr/bin/xbctl 2>/dev/null || true
    fi
    if [ "${SERVICE_WAS_ACTIVE}" -eq 1 ]; then
        systemctl restart "${SERVICE_NAME}"
        log_info "服务已重启: ${SERVICE_NAME}"
    else
        log_info "服务当前未运行，已仅更新二进制"
    fi
}

perform_uninstall() {
    check_root
    if [ "${YES}" -ne 1 ]; then
        echo ""
        log_warn "将停止并移除 ${SERVICE_NAME}、${BINARY_PATH} 和 ${CLI_PATH}。配置默认保留。"
        read -r -p "继续卸载? [y/N]: " answer
        if ! [[ "${answer}" =~ ^[Yy]$ ]]; then
            log_warn "已取消"
            exit 0
        fi
    fi
    if command -v systemctl >/dev/null 2>&1; then
        stop_legacy_template_services
        systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
        systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
        rm -f "${SERVICE_PATH}"
        systemctl daemon-reload 2>/dev/null || true
    fi
    rm -f "${BINARY_PATH}" "${CLI_PATH}" /usr/bin/xbctl
    if [ "${PURGE}" -eq 1 ]; then
        rm -rf "${INSTALL_ROOT}"
        log_info "已删除配置目录: ${INSTALL_ROOT}"
    else
        log_info "配置已保留: ${INSTALL_ROOT}"
    fi
    log_info "卸载完成"
}

perform_list() {
    if [ -x "${CLI_PATH}" ]; then
        "${CLI_PATH}" list
        return
    fi
    log_error "未找到 ${CLI_PATH}，请先安装 xbctl 或使用 install/status 检查部署"
    exit 1
}

perform_remove() {
    if [ -x "${CLI_PATH}" ]; then
        "${CLI_PATH}" bind remove-node "${REMOVE_ARGS[@]}"
        return
    fi
    log_error "未找到 ${CLI_PATH}，无法移除实例绑定"
    exit 1
}

perform_egress() {
    if [ "${#EGRESS_ARGS[@]}" -eq 0 ]; then
        log_error "用法: bash install.sh egress <list|set|clear> [参数]"
        exit 1
    fi
    check_root
    ensure_systemd
    detect_arch
    detect_current_state
    ensure_dirs
    TMP_DIR="$(mktemp -d)"
    stage_xbctl
    install -m 755 "${TMP_DIR}/xbctl" "${CLI_PATH}"
    ln -sf "${CLI_PATH}" /usr/bin/xbctl 2>/dev/null || true

    case "${EGRESS_ARGS[0]}" in
        set|clear)
            backup_existing_state
            ;;
    esac

    "${CLI_PATH}" egress "${EGRESS_ARGS[@]}"
}

main() {
    parse_args "$@"
    case "${ACTION}" in
        help)
            usage
            ;;
        install)
            perform_install
            ;;
        status)
            perform_status
            ;;
        upgrade)
            perform_upgrade
            ;;
        uninstall)
            perform_uninstall
            ;;
        list)
            perform_list
            ;;
        remove)
            perform_remove
            ;;
        egress)
            perform_egress
            ;;
        *)
            log_error "未知命令: ${ACTION}"
            usage
            exit 1
            ;;
    esac
}

main "$@"
