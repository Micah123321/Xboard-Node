#!/bin/bash
set -e

# mi-node 多节点部署脚本
# 支持: Ubuntu 20+, Debian 11+, CentOS 8+, Alpine 3.18+
#
# 本机一键部署（默认，不带 --docker）:
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 1
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 2 -k xray
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 3 --gomemlimit 256MiB --gogc 50
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 3 --egress-socks5 127.0.0.1:1080
#   bash install.sh -a https://panel.example.com -t YOUR_TOKEN -n 3 --egress-shadowsocks-uri 'ss://YWVzLTEyOC1nY206eW91ci1wYXNzd29yZA==@127.0.0.1:8388'
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
CONFIG_DIR="/etc/mi-node"
SERVICE_TEMPLATE="mi-node@.service"
DOCKER_COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
RELEASE_REPO_DEFAULT="Micah123321/mi-node"
RELEASE_REPO="${MI_NODE_RELEASE_REPO:-$RELEASE_REPO_DEFAULT}"
RELEASE_REPO_LC="$(printf '%s' "$RELEASE_REPO" | tr '[:upper:]' '[:lower:]')"
REPO_URL="https://github.com/${RELEASE_REPO}"
RELEASES_BASE_URL="${REPO_URL}/releases"
DOCKER_IMAGE="${MI_NODE_DOCKER_IMAGE:-ghcr.io/micah123321/mi-node:latest}"
CERT_WAIT_SECONDS=15
EGRESS_PROBE_WAIT_SECONDS=15

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
EGRESS_SHADOWSOCKS_URI=""
EGRESS_SHADOWSOCKS_HOST=""
EGRESS_SHADOWSOCKS_PORT=""
CERT_MODE=""
CERT_DOMAIN=""
CERT_EMAIL=""
CERT_HTTP_PORT=""
CERT_DNS_PROVIDER=""
CERT_DNS_ENV_ITEMS=()
DOCKER_MODE=0
SUBCOMMAND=""
NODE_LAUNCHED=0
SERVICE_LAUNCH_TIME_LOCAL=""
SERVICE_LAUNCH_TIME_UTC=""

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

is_acme_mode() {
    case "$(effective_cert_mode)" in
        http|dns) return 0 ;;
        *) return 1 ;;
    esac
}

is_http_cert_mode() {
    [ "$(effective_cert_mode)" = "http" ]
}

effective_cert_http_port() {
    if [ -n "$CERT_HTTP_PORT" ]; then
        printf '%s' "$CERT_HTTP_PORT"
        return
    fi
    printf '80'
}

cert_file_path() {
    local node_id="$1"
    printf '%s/%s/certs/%s.crt' "$CONFIG_DIR" "$node_id" "$CERT_DOMAIN"
}

cert_key_path() {
    local node_id="$1"
    printf '%s/%s/certs/%s.key' "$CONFIG_DIR" "$node_id" "$CERT_DOMAIN"
}

can_auto_wait_for_cert() {
    if ! is_acme_mode || [ -z "$CERT_DOMAIN" ]; then
        return 1
    fi

    if [ "$NODE_LAUNCHED" -ne 1 ]; then
        return 1
    fi

    if [ "$DOCKER_MODE" -eq 1 ]; then
        command -v docker >/dev/null 2>&1
        return
    fi

    command -v systemctl >/dev/null 2>&1
}

capture_launch_time() {
    SERVICE_LAUNCH_TIME_LOCAL="$(date '+%Y-%m-%d %H:%M:%S')"
    SERVICE_LAUNCH_TIME_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

native_node_service_name() {
    local node_id="$1"
    printf 'mi-node@%s' "$node_id"
}

docker_node_container_name() {
    local node_id="$1"
    printf 'mi-node-%s' "$node_id"
}

can_auto_wait_for_shadowsocks_probe() {
    if [ -z "$EGRESS_SHADOWSOCKS_URI" ] || [ "$KERNEL_TYPE" != "singbox" ]; then
        return 1
    fi

    if [ "$NODE_LAUNCHED" -ne 1 ]; then
        return 1
    fi

    if [ "$DOCKER_MODE" -eq 1 ]; then
        command -v docker >/dev/null 2>&1
        return
    fi

    command -v journalctl >/dev/null 2>&1
}

read_node_logs_since_launch() {
    local node_id="$1"

    if [ "$DOCKER_MODE" -eq 1 ]; then
        if [ -n "$SERVICE_LAUNCH_TIME_UTC" ]; then
            docker logs --since "$SERVICE_LAUNCH_TIME_UTC" "$(docker_node_container_name "$node_id")" 2>&1
            return
        fi
        docker logs "$(docker_node_container_name "$node_id")" 2>&1
        return
    fi

    if [ -n "$SERVICE_LAUNCH_TIME_LOCAL" ]; then
        journalctl -u "$(native_node_service_name "$node_id")" --since "$SERVICE_LAUNCH_TIME_LOCAL" -n 200 --no-pager 2>/dev/null
        return
    fi
    journalctl -u "$(native_node_service_name "$node_id")" -n 200 --no-pager 2>/dev/null
}

latest_shadowsocks_probe_result() {
    local node_id="$1"
    local latest_line=""

    latest_line="$(
        read_node_logs_since_launch "$node_id" | \
        grep -E 'shadowsocks egress probe (succeeded|failed)' | \
        tail -n 1 || true
    )"

    case "$latest_line" in
        *"shadowsocks egress probe succeeded"*)
            printf 'success'
            ;;
        *"shadowsocks egress probe failed"*)
            printf 'failed'
            ;;
        *)
            printf 'pending'
            ;;
    esac
}

wait_for_shadowsocks_probe_result() {
    local node_id="$1"
    local timeout="${2:-$EGRESS_PROBE_WAIT_SECONDS}"
    local waited=0
    local probe_result=""

    if ! can_auto_wait_for_shadowsocks_probe; then
        return 2
    fi

    log_info "正在等待 Shadowsocks 默认出站健康检查结果（最多 ${timeout} 秒）..."
    while [ "$waited" -lt "$timeout" ]; do
        probe_result="$(latest_shadowsocks_probe_result "$node_id")"
        case "$probe_result" in
            success)
                log_info "Shadowsocks 默认出站健康检查通过"
                return 0
                ;;
            failed)
                log_error "Shadowsocks 默认出站健康检查失败"
                return 1
                ;;
        esac

        sleep 1
        waited=$((waited + 1))
    done

    log_warn "${timeout} 秒内未拿到 Shadowsocks 默认出站 probe 结果"
    return 2
}

print_shadowsocks_probe_hint() {
    local node_id="$1"

    echo "  默认出站健康检查:"
    if [ "$DOCKER_MODE" -eq 1 ]; then
        echo "    容器状态:  docker ps -a --filter name=$(docker_node_container_name "$node_id")"
        echo "    排查日志:  docker logs --tail 50 $(docker_node_container_name "$node_id")"
    else
        echo "    服务状态:  systemctl status $(native_node_service_name "$node_id")"
        echo "    排查日志:  journalctl -u $(native_node_service_name "$node_id") -n 50 --no-pager"
    fi
    echo "    关键字:    shadowsocks egress probe, open connection to"
}

wait_for_cert_result() {
    local node_id="$1"
    local timeout="${2:-$CERT_WAIT_SECONDS}"
    local cert_file=""
    local key_file=""
    local waited=0

    if ! can_auto_wait_for_cert; then
        return 1
    fi

    cert_file="$(cert_file_path "$node_id")"
    key_file="$(cert_key_path "$node_id")"

    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        return 0
    fi

    log_info "正在等待证书申请结果（最多 ${timeout} 秒）..."
    while [ "$waited" -lt "$timeout" ]; do
        sleep 1
        waited=$((waited + 1))
        if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
            log_info "已检测到证书文件，ACME 申请成功"
            return 0
        fi
    done

    log_warn "${timeout} 秒内未检测到证书文件，将输出当前状态和排查命令"
    return 1
}

detect_local_tcp_listener() {
    local port="$1"

    if [ -z "$port" ]; then
        printf 'unknown'
        return
    fi

    if command -v ss >/dev/null 2>&1; then
        if ss -ltnH "( sport = :${port} )" 2>/dev/null | grep -q .; then
            printf 'listening'
            return
        fi
        printf 'not_listening'
        return
    fi

    if command -v netstat >/dev/null 2>&1; then
        if netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[[:space:]])[^[:space:]]*:${port}$"; then
            printf 'listening'
            return
        fi
        printf 'not_listening'
        return
    fi

    printf 'unknown'
}

print_http01_listener_hint() {
    local port=""
    local listener_status=""

    if ! is_http_cert_mode || [ -z "$CERT_DOMAIN" ]; then
        return 0
    fi

    port="$(effective_cert_http_port)"
    listener_status="$(detect_local_tcp_listener "$port")"

    case "$listener_status" in
        listening)
            echo "    本地监听:  已检测到 :${port}"
            ;;
        not_listening)
            echo "    本地监听:  暂未检测到 :${port}"
            ;;
        *)
            echo "    本地监听:  当前环境无法自动检测"
            ;;
    esac

    if [ "$port" = "80" ]; then
        echo "    端口要求:  ACME HTTP-01 仍通过公网 80 校验，请确保 ${CERT_DOMAIN}:80 可被公网访问"
    else
        echo "    端口要求:  ACME HTTP-01 仍通过公网 80 校验，请确保公网 80 已转发到本机 ${port}"
    fi
}

print_cert_status_hint() {
    local node_id="$1"
    local cert_file=""
    local key_file=""

    if ! is_acme_mode || [ -z "$CERT_DOMAIN" ]; then
        return 0
    fi

    cert_file="$(cert_file_path "$node_id")"
    key_file="$(cert_key_path "$node_id")"

    echo "  证书申请状态:"
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        echo "    结果:      已成功写入证书文件"
        echo "    cert:      ${cert_file}"
        echo "    key:       ${key_file}"
        if is_http_cert_mode; then
            print_http01_listener_hint
        fi
        return 0
    fi

    echo "    结果:      暂未检测到证书文件"
    if [ "$DOCKER_MODE" -eq 1 ]; then
        echo "    说明:      容器启动后会自动申请，首次签发可能需要几十秒"
        echo "    排查日志:  docker logs -f mi-node-${node_id}"
    else
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active "mi-node@${node_id}" >/dev/null 2>&1; then
            echo "    说明:      服务已启动，可能仍在申请或同步证书"
        else
            echo "    说明:      服务未正常进入 active，证书申请大概率失败"
            echo "    服务状态:  systemctl status mi-node@${node_id}"
        fi
        echo "    排查日志:  journalctl -u mi-node@${node_id} -n 50 --no-pager"
    fi
    if is_http_cert_mode; then
        print_http01_listener_hint
        echo "    手动检查:  ss -ltn | grep ':$(effective_cert_http_port) '"
        echo "    外网检查:  确保 ${CERT_DOMAIN}:80 可达；若使用 --cert-http-port，则确认 80 已转发到该端口"
        echo "    常见原因:  域名未解析到本机、80 端口不可达、80 未转发到本地监听端口"
        return 0
    fi
    echo "    常见原因:  域名未解析到本机、80 端口不可达、DNS Provider 凭据错误"
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

parse_shadowsocks_endpoint() {
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

    EGRESS_SHADOWSOCKS_HOST="$host"
    EGRESS_SHADOWSOCKS_PORT="$port"
    return 0
}

is_supported_shadowsocks_method() {
    local method="$1"
    local kernel="$2"

    case "$method" in
        aes-128-gcm|aes-256-gcm|chacha20-ietf-poly1305|2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305)
            return 0
            ;;
        aes-192-gcm)
            [ "$kernel" = "singbox" ]
            return
            ;;
        *)
            return 1
            ;;
    esac
}

print_supported_shadowsocks_methods() {
    if [ "$KERNEL_TYPE" = "xray" ]; then
        echo "aes-128-gcm, aes-256-gcm, chacha20-ietf-poly1305, 2022-blake3-aes-128-gcm, 2022-blake3-aes-256-gcm, 2022-blake3-chacha20-poly1305"
    else
        echo "aes-128-gcm, aes-192-gcm, aes-256-gcm, chacha20-ietf-poly1305, 2022-blake3-aes-128-gcm, 2022-blake3-aes-256-gcm, 2022-blake3-chacha20-poly1305"
    fi
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
            --egress-shadowsocks-uri) EGRESS_SHADOWSOCKS_URI="$2"; shift 2 ;;
            --egress-shadowsocks|--egress-shadowsocks-method|--egress-shadowsocks-password)
                log_error "旧的 Shadowsocks 出站参数已不再支持，请改用 --egress-shadowsocks-uri 'ss://...'"
                exit 1
                ;;
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

    if [ -n "$EGRESS_SHADOWSOCKS_URI" ]; then
        case "$EGRESS_SHADOWSOCKS_URI" in
            ss://*) ;;
            *)
                log_error "Shadowsocks 出站必须使用 ss:// URI，例如 --egress-shadowsocks-uri 'ss://...'"
                exit 1
                ;;
        esac
    fi

    if [ -n "$EGRESS_SOCKS5" ] && [ -n "$EGRESS_SHADOWSOCKS_URI" ]; then
        log_error "SOCKS5 和 Shadowsocks 默认出站只能二选一"
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
                read -rp "  HTTP-01 本地监听端口 (默认 80；公网仍需 80 可达): " CERT_HTTP_PORT
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
    echo ""

    if [ -z "$EGRESS_SOCKS5" ] && [ -z "$EGRESS_SHADOWSOCKS_URI" ]; then
        echo "  默认出站:"
        echo "    1) 不设置 / direct"
        echo "    2) SOCKS5"
        echo "    3) Shadowsocks / SS2022"
        read -rp "  请选择 [1/2/3]: " EGRESS_CHOICE
        case "$EGRESS_CHOICE" in
            2)
                read -rp "  默认 SOCKS5 出站 (host:port): " EGRESS_SOCKS5
                ;;
            3)
                read -rp "  默认 Shadowsocks 出站 (ss:// URI): " EGRESS_SHADOWSOCKS_URI
                ;;
            *)
                ;;
        esac
    fi

    if [ -n "$EGRESS_SOCKS5" ]; then
        echo -e "  默认 SOCKS5 出站: ${CYAN}${EGRESS_SOCKS5}${NC}"
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
    elif [ -n "$EGRESS_SHADOWSOCKS_URI" ]; then
        echo -e "  默认 Shadowsocks 出站 URI: ${CYAN}${EGRESS_SHADOWSOCKS_URI}${NC}"
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
    [ -x "${INSTALL_DIR}/mi-node" ]
}

install_binary() {
    if is_binary_installed; then
        log_info "mi-node 二进制已存在，跳过下载"
        return
    fi

    log_step "安装 mi-node 二进制..."

    local src=""

    if [ -f "./mi-node" ]; then
        src="./mi-node"
    elif [ -f "./mi-node-linux-${ARCH}" ]; then
        src="./mi-node-linux-${ARCH}"
    fi

    if [ -n "$src" ]; then
        cp "$src" "${INSTALL_DIR}/mi-node"
        log_info "已从本地文件安装: $src"
    else
        log_info "正在从当前仓库 Releases 下载: ${REPO_URL}"
        if download_release_asset "mi-node-linux-${ARCH}" "${INSTALL_DIR}/mi-node"; then
            log_info "下载完成"
        else
            log_error "下载失败。请先将对应架构的二进制放到当前目录后重试。"
            exit 1
        fi
    fi

    chmod +x "${INSTALL_DIR}/mi-node"
    log_info "mi-node 已安装到 ${INSTALL_DIR}/mi-node"
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

    cat > "/etc/systemd/system/${SERVICE_TEMPLATE}" <<UNIT
[Unit]
Description=Mi Node Backend (node %i)
Documentation=${REPO_URL}
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mi-node -c /etc/mi-node/%i/config.yml
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
                systemctl stop mi-node 2>/dev/null || true
                systemctl disable mi-node 2>/dev/null || true
                rm -f /etc/systemd/system/mi-node.service

                install_systemd_template
                systemctl enable "mi-node@${legacy_id}" 2>/dev/null || true
                systemctl start "mi-node@${legacy_id}" 2>/dev/null || true
                log_info "服务已迁移: mi-node → mi-node@${legacy_id}"
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
    elif [ -n "$EGRESS_SHADOWSOCKS_URI" ]; then
        egress_block="${egress_block}
    shadowsocks:
      uri: \"${EGRESS_SHADOWSOCKS_URI}\""
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
        capture_launch_time
        systemctl enable "mi-node@${node_id}"
        systemctl start "mi-node@${node_id}"
        NODE_LAUNCHED=1
        log_info "服务已启动: mi-node@${node_id}"
    else
        log_warn "未检测到 systemd，请手动运行:"
        echo "  mi-node -c ${CONFIG_DIR}/${node_id}/config.yml"
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
        capture_launch_time
        ${COMPOSE_CMD} up -d "node-${node_id}"
        NODE_LAUNCHED=1
        log_info "容器已启动: mi-node-${node_id}"
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
    container_name: mi-node-${nid}
    restart: always
    network_mode: host
    volumes:
      - ./${nid}/config.yml:/etc/mi-node/config.yml:ro
      - ./${nid}:/etc/mi-node/data
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
    local egress_probe_status="skipped"

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

    if has_cert_inputs && is_acme_mode; then
        wait_for_cert_result "$NODE_ID" "$CERT_WAIT_SECONDS" || true
    fi

    if [ -n "$EGRESS_SHADOWSOCKS_URI" ]; then
        if [ "$KERNEL_TYPE" = "singbox" ]; then
            if wait_for_shadowsocks_probe_result "$NODE_ID" "$EGRESS_PROBE_WAIT_SECONDS"; then
                egress_probe_status="passed"
            else
                local probe_rc=$?
                if [ "$probe_rc" -eq 1 ]; then
                    echo ""
                    echo -e "${RED}=== 节点 ${NODE_ID} 部署失败 ===${NC}"
                    echo ""
                    echo "  失败原因: Shadowsocks 默认出站健康检查失败"
                    echo "    内核:      ${KERNEL_TYPE}"
                    echo "    URI:       ${EGRESS_SHADOWSOCKS_URI}"
                    echo "    说明:      节点配置和服务已保留，便于继续排查"
                    echo ""
                    print_shadowsocks_probe_hint "$NODE_ID"
                    echo ""
                    echo "  配置文件: ${CONFIG_DIR}/${NODE_ID}/config.yml"
                    echo ""
                    return 1
                fi
                egress_probe_status="timeout"
            fi
        else
            egress_probe_status="unsupported"
        fi
    fi

    echo ""
    echo -e "${GREEN}=== 节点 ${NODE_ID} 部署完成 ===${NC}"
    echo ""

    if [ "$DOCKER_MODE" -eq 1 ]; then
        echo "  管理命令:"
        echo "    日志:    docker logs -f mi-node-${NODE_ID}"
        echo "    停止:    cd ${CONFIG_DIR} && docker compose stop node-${NODE_ID}"
        echo "    重启:    cd ${CONFIG_DIR} && docker compose restart node-${NODE_ID}"
    else
        echo "  管理命令:"
        echo "    状态:    systemctl status mi-node@${NODE_ID}"
        echo "    日志:    journalctl -u mi-node@${NODE_ID} -f"
        echo "    停止:    systemctl stop mi-node@${NODE_ID}"
        echo "    重启:    systemctl restart mi-node@${NODE_ID}"
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
    elif [ -n "$EGRESS_SHADOWSOCKS_URI" ]; then
        echo "  默认出站: Shadowsocks"
        echo "    URI:       ${EGRESS_SHADOWSOCKS_URI}"
        case "$egress_probe_status" in
            passed)
                echo "    健康检查:  已通过（默认出站 probe succeeded）"
                ;;
            timeout)
                echo "    健康检查:  超时未确认，请手动查看 probe 日志"
                print_shadowsocks_probe_hint "$NODE_ID"
                ;;
            unsupported)
                echo "    健康检查:  当前仅 singbox 支持真实 probe，已跳过"
                ;;
            *)
                echo "    健康检查:  未执行"
                ;;
        esac
    else
        echo "  默认出站: 直连（内置防滥用拦截规则默认开启）"
    fi

    echo ""
    if has_cert_inputs; then
        local cert_mode_resolved
        local cert_http_port=""
        cert_mode_resolved="$(effective_cert_mode)"
        echo "  证书策略: $(cert_mode_label "$cert_mode_resolved")"
        [ -n "$CERT_DOMAIN" ] && echo "    域名:      ${CERT_DOMAIN}"
        [ -n "$CERT_EMAIL" ] && echo "    邮箱:      ${CERT_EMAIL}"
        [ -n "$CERT_DNS_PROVIDER" ] && echo "    Provider:  ${CERT_DNS_PROVIDER}"
        if is_http_cert_mode; then
            cert_http_port="$(effective_cert_http_port)"
            echo "    本地监听:  ${cert_http_port}"
            if [ "$cert_http_port" = "80" ]; then
                echo "    公网校验:  ACME HTTP-01 需要 ${CERT_DOMAIN}:80 可被公网访问"
            else
                echo "    公网校验:  ACME HTTP-01 仍走公网 80，请确保 80 已转发到本机 ${cert_http_port}"
            fi
        fi
        is_acme_mode && echo "    首次申请:  服务启动后自动触发"
    else
        echo "  证书策略: 未显式配置；若协议需要 TLS，将自动回退为自签证书"
    fi

    if has_cert_inputs && is_acme_mode; then
        echo ""
        print_cert_status_hint "$NODE_ID"
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
        systemctl stop "mi-node@${node_id}" 2>/dev/null || true
        systemctl disable "mi-node@${node_id}" 2>/dev/null || true
        log_info "systemd 服务已停止并禁用"
    fi

    if command -v docker >/dev/null 2>&1; then
        docker rm -f "mi-node-${node_id}" 2>/dev/null || true
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
            if systemctl is-active "mi-node@${nid}" >/dev/null 2>&1; then
                status="${GREEN}running (systemd)${NC}"
            fi
        fi
        if command -v docker >/dev/null 2>&1; then
            if docker inspect -f '{{.State.Running}}' "mi-node-${nid}" 2>/dev/null | grep -q true; then
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
    log_step "更新 mi-node 二进制..."

    detect_arch

    local tmp="/tmp/mi-node-update"

    log_info "正在从当前仓库 Releases 更新: ${REPO_URL}"
    if download_release_asset "mi-node-linux-${ARCH}" "$tmp"; then
        chmod +x "$tmp"
        mv "$tmp" "${INSTALL_DIR}/mi-node"
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
            if systemctl is-active "mi-node@${nid}" >/dev/null 2>&1; then
                systemctl restart "mi-node@${nid}"
                log_info "已重启: mi-node@${nid}"
            fi
        done
    fi

    if [ -f "${DOCKER_COMPOSE_FILE}" ] && command -v docker >/dev/null 2>&1; then
        log_info "如需更新 Docker 节点，请执行:"
        echo "  cd ${CONFIG_DIR} && docker compose pull && docker compose up -d"
    fi
}

do_uninstall() {
    log_step "卸载 mi-node..."

    if command -v systemctl >/dev/null 2>&1; then
        for dir in "${CONFIG_DIR}"/*/; do
            [ -f "${dir}config.yml" ] || continue
            local nid
            nid=$(basename "$dir")
            systemctl stop "mi-node@${nid}" 2>/dev/null || true
            systemctl disable "mi-node@${nid}" 2>/dev/null || true
        done
        systemctl stop mi-node 2>/dev/null || true
        systemctl disable mi-node 2>/dev/null || true
        rm -f /etc/systemd/system/mi-node.service
        rm -f "/etc/systemd/system/${SERVICE_TEMPLATE}"
        systemctl daemon-reload
    fi

    if command -v docker >/dev/null 2>&1; then
        for dir in "${CONFIG_DIR}"/*/; do
            [ -f "${dir}config.yml" ] || continue
            local nid
            nid=$(basename "$dir")
            docker rm -f "mi-node-${nid}" 2>/dev/null || true
        done
    fi

    rm -f "${INSTALL_DIR}/mi-node"
    log_info "二进制已删除"

    echo ""
    read -rp "  是否删除所有配置? (${CONFIG_DIR}) [y/N]: " DELETE_ALL
    if [[ "$DELETE_ALL" =~ ^[Yy]$ ]]; then
        rm -rf "${CONFIG_DIR}"
        log_info "所有配置已删除"
    else
        log_info "配置保留在 ${CONFIG_DIR}/"
    fi

    log_info "mi-node 已卸载"
}

# ─── 帮助信息 ────────────────────────────────────────────────────────

print_help() {
    cat << 'HELP'

  mi-node 部署脚本

  本机部署（默认，推荐，适合减少 Docker 内存占用）:

    install.sh -a <url> -t <token> -n <node_id> [-T <node_type>] [-k singbox|xray] [--gomemlimit 256MiB] [--gogc 50] [--egress-socks5 127.0.0.1:1080] [--egress-shadowsocks-uri 'ss://...'] [--cert-domain node.example.com]

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
        --egress-shadowsocks-uri 默认 Shadowsocks 出站 URI (格式 ss://...)
        --cert-mode    证书模式          (http、dns、self、none)
        --cert-domain  证书域名          (ACME 必填；仅传域名时默认走 HTTP-01)
        --cert-email   ACME 邮箱         (可选，推荐)
        --cert-http-port HTTP-01 本地监听端口 (默认 80；公网仍需 80 可达)
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

    # 本机部署节点 3，所有默认出站经 Shadowsocks / SS2022 URI 转发
    bash install.sh -a https://panel.example.com -t mytoken123 -n 3 --egress-shadowsocks-uri 'ss://YWVzLTEyOC1nY206eW91ci1wYXNzd29yZA==@127.0.0.1:8388'
    bash install.sh -a https://panel.example.com -t mytoken123 -n 3 --egress-shadowsocks-uri 'ss://MjAyMi1ibGFrZTMtYWVzLTI1Ni1nY206ODhvMGZwK3BBV29XS3ZrRGUydWhxek4zcDE3Uk5mQzdhSE0wVldJTUtuZz06UnlObkhsZ3lLT3ZKVzRCWVY5TnhWMDlMWkhnWGM1Ui9wamxKSjRPR3QyND0=@38.182.122.32:37605?type=tcp#egress'

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
      ghcr.io/micah123321/mi-node:latest

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
