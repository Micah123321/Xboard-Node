#!/usr/bin/env bash
set -euo pipefail

RAW_URL_DEFAULT="https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/install.sh"
RAW_URL="${RAW_URL_DEFAULT}"
TARGET_NODE_ID=""
MIGRATE_ALL=0
DRY_RUN=0
KEEP_OLD_DISABLED=0
BACKUP_ROOT=""

usage() {
    cat <<'EOF'
用法:
  bash migrate-to-mi-node.sh [--node-id 330 | --all] [--raw-url URL] [--backup-root DIR] [--dry-run]

说明:
  - 自动从旧配置中提取 panel.url / token / node_id / kernel.type / cert.* / runtime.*
  - 默认行为:
      仅检测到 1 个节点配置 -> 自动迁移该节点
      检测到多个节点配置     -> 需显式传 --node-id 或 --all
  - 迁移成功后会启动 mi-node.service，并禁用旧 xboard-node 服务

参数:
  --node-id ID        只迁移指定节点
  --all               迁移当前机器检测到的全部节点
  --raw-url URL       覆盖默认 mi-node install.sh raw 地址
  --backup-root DIR   备份目录根路径，默认 /root/mi-node-migrate-<timestamp>
  --dry-run           仅打印识别结果和将执行的命令，不实际执行
  --keep-old-enabled  迁移成功后不禁用旧 xboard-node 服务
  -h, --help          显示帮助
EOF
}

log() {
    printf '[migrate] %s\n' "$*"
}

err() {
    printf '[migrate][error] %s\n' "$*" >&2
}

timestamp() {
    date +%Y%m%d-%H%M%S
}

shell_quote() {
    printf '%q' "$1"
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

unquote() {
    local s
    s="$(trim "$1")"
    if [[ "$s" == \"*\" && "$s" == *\" ]]; then
        s="${s:1:${#s}-2}"
    elif [[ "$s" == \'*\' && "$s" == *\' ]]; then
        s="${s:1:${#s}-2}"
    fi
    printf '%s' "$s"
}

yaml_get_top_level() {
    local file="$1"
    local key="$2"
    awk -v key="$key" '
        $0 ~ "^" key ":[[:space:]]*" {
            sub("^[[:space:]]*" key ":[[:space:]]*", "", $0)
            print $0
            exit
        }
    ' "$file"
}

yaml_get_section_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    awk -v section="$section" -v key="$key" '
        function indent_len(line,    n, c) {
            n = 0
            for (c = 1; c <= length(line); c++) {
                if (substr(line, c, 1) == " ") {
                    n++
                } else {
                    break
                }
            }
            return n
        }
        BEGIN {
            in_section = 0
            section_indent = -1
        }
        {
            line = $0
            if (line ~ "^" section ":[[:space:]]*$") {
                in_section = 1
                section_indent = indent_len(line)
                next
            }
            if (in_section) {
                if (line ~ /^[[:space:]]*$/) {
                    next
                }
                current_indent = indent_len(line)
                if (current_indent <= section_indent) {
                    exit
                }
                if (line ~ "^[[:space:]]*" key ":[[:space:]]*") {
                    sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
                    print line
                    exit
                }
            }
        }
    ' "$file"
}

yaml_get_cert_dns_env() {
    local file="$1"
    awk '
        function indent_len(line,    n, c) {
            n = 0
            for (c = 1; c <= length(line); c++) {
                if (substr(line, c, 1) == " ") {
                    n++
                } else {
                    break
                }
            }
            return n
        }
        BEGIN {
            in_cert = 0
            cert_indent = -1
            in_dns_env = 0
            dns_indent = -1
        }
        {
            line = $0
            if (line ~ "^cert:[[:space:]]*$") {
                in_cert = 1
                cert_indent = indent_len(line)
                in_dns_env = 0
                next
            }
            if (in_cert) {
                if (line ~ /^[[:space:]]*$/) {
                    next
                }
                current_indent = indent_len(line)
                if (current_indent <= cert_indent) {
                    exit
                }
                if (line ~ "^[[:space:]]*dns_env:[[:space:]]*$") {
                    in_dns_env = 1
                    dns_indent = indent_len(line)
                    next
                }
                if (in_dns_env) {
                    if (current_indent <= dns_indent) {
                        exit
                    }
                    if (line ~ "^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*") {
                        key = line
                        sub("^[[:space:]]*", "", key)
                        sub(":.*$", "", key)
                        val = line
                        sub("^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*", "", val)
                        gsub(/^["'\''"]|["'\''"]$/, "", val)
                        print key "=" val
                    }
                }
            }
        }
    ' "$file"
}

yaml_get_kernel_egress_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    awk -v section="$section" -v key="$key" '
        function indent_len(line,    n, c) {
            n = 0
            for (c = 1; c <= length(line); c++) {
                if (substr(line, c, 1) == " ") {
                    n++
                } else {
                    break
                }
            }
            return n
        }
        BEGIN {
            in_kernel = 0
            kernel_indent = -1
            in_egress = 0
            egress_indent = -1
            in_section = 0
            section_indent = -1
        }
        {
            line = $0
            if (line ~ "^kernel:[[:space:]]*$") {
                in_kernel = 1
                kernel_indent = indent_len(line)
                in_egress = 0
                in_section = 0
                next
            }
            if (in_kernel) {
                if (line ~ /^[[:space:]]*$/) {
                    next
                }
                current_indent = indent_len(line)
                if (current_indent <= kernel_indent) {
                    exit
                }
                if (line ~ "^[[:space:]]*egress:[[:space:]]*$") {
                    in_egress = 1
                    egress_indent = current_indent
                    in_section = 0
                    next
                }
                if (in_egress) {
                    if (current_indent <= egress_indent) {
                        in_egress = 0
                        in_section = 0
                    }
                    if (in_egress && line ~ "^[[:space:]]*" section ":[[:space:]]*$") {
                        in_section = 1
                        section_indent = current_indent
                        next
                    }
                    if (in_section) {
                        if (current_indent <= section_indent) {
                            in_section = 0
                        } else if (line ~ "^[[:space:]]*" key ":[[:space:]]*") {
                            sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
                            print line
                            exit
                        }
                    }
                }
            }
        }
    ' "$file"
}

yaml_get_kernel_egress_scalar() {
    local file="$1"
    local section="$2"
    awk -v section="$section" '
        function indent_len(line,    n, c) {
            n = 0
            for (c = 1; c <= length(line); c++) {
                if (substr(line, c, 1) == " ") {
                    n++
                } else {
                    break
                }
            }
            return n
        }
        BEGIN {
            in_kernel = 0
            kernel_indent = -1
            in_egress = 0
            egress_indent = -1
        }
        {
            line = $0
            if (line ~ "^kernel:[[:space:]]*$") {
                in_kernel = 1
                kernel_indent = indent_len(line)
                in_egress = 0
                next
            }
            if (in_kernel) {
                if (line ~ /^[[:space:]]*$/) {
                    next
                }
                current_indent = indent_len(line)
                if (current_indent <= kernel_indent) {
                    exit
                }
                if (line ~ "^[[:space:]]*egress:[[:space:]]*$") {
                    in_egress = 1
                    egress_indent = current_indent
                    next
                }
                if (in_egress) {
                    if (current_indent <= egress_indent) {
                        exit
                    }
                    if (line ~ "^[[:space:]]*" section ":[[:space:]]*[^[:space:]].*") {
                        sub("^[[:space:]]*" section ":[[:space:]]*", "", line)
                        print line
                        exit
                    }
                }
            }
        }
    ' "$file"
}

normalize_scalar() {
    unquote "$1"
}

url_decode() {
    local value="${1//+/ }"
    printf '%b' "${value//%/\\x}"
}

parse_socks5_uri() {
    local uri="$1"
    local rest auth hostport host port user pass
    [[ "$uri" == socks5://* || "$uri" == socks://* ]] || return 1
    rest="${uri#*://}"
    rest="${rest%%/*}"
    rest="${rest%%\?*}"

    if [[ "$rest" == *"@"* ]]; then
        auth="${rest%@*}"
        hostport="${rest##*@}"
        if [[ "$auth" == *:* ]]; then
            user="${auth%%:*}"
            pass="${auth#*:}"
        else
            user="$auth"
            pass=""
        fi
        user="$(url_decode "$user")"
        pass="$(url_decode "$pass")"
    else
        hostport="$rest"
        user=""
        pass=""
    fi

    if [[ "$hostport" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    elif [[ "$hostport" =~ ^([^:]+):([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    SOCKS5_HOST="$host"
    SOCKS5_PORT="$port"
    SOCKS5_USER="$user"
    SOCKS5_PASS="$pass"
}

find_candidate_configs() {
    shopt -s nullglob
    local paths=(
        /etc/mi-node/*/config.yml
        /etc/mi-node/config.yml
        /etc/Xboard-Node/*/config.yml
        /etc/Xboard-Node/config.yml
        /etc/xboard-node/*/config.yml
        /etc/xboard-node/config.yml
    )
    local p
    for p in "${paths[@]}"; do
        [[ -f "$p" ]] || continue
        [[ -n "$(node_id_from_config "$p")" ]] || continue
        printf '%s\n' "$p"
    done | awk '!seen[$0]++'
}

node_id_from_config() {
    local file="$1"
    local id
    id="$(yaml_get_section_value "$file" panel node_id)"
    id="$(normalize_scalar "$id")"
    printf '%s' "$id"
}

create_backup_root() {
    if [[ -n "$BACKUP_ROOT" ]]; then
        mkdir -p "$BACKUP_ROOT"
        printf '%s' "$BACKUP_ROOT"
        return
    fi
    BACKUP_ROOT="/root/mi-node-migrate-$(timestamp)"
    mkdir -p "$BACKUP_ROOT"
    printf '%s' "$BACKUP_ROOT"
}

backup_node() {
    local node_id="$1"
    local cfg="$2"
    local backup_root="$3"
    local node_dir="${backup_root}/node-${node_id}"

    mkdir -p "$node_dir"
    cp -a "$cfg" "${node_dir}/config.yml"
    systemctl cat "xboard-node@${node_id}" > "${node_dir}/xboard-node@${node_id}.service.txt" 2>/dev/null || true
    systemctl cat xboard-node > "${node_dir}/xboard-node.service.txt" 2>/dev/null || true
    systemctl cat "mi-node@${node_id}" > "${node_dir}/mi-node@${node_id}.service.txt" 2>/dev/null || true

    if [[ -d "/etc/xboard-node/${node_id}" ]]; then
        cp -a "/etc/xboard-node/${node_id}" "${node_dir}/etc-xboard-node-node" 2>/dev/null || true
    fi
    if [[ -d "/etc/Xboard-Node/${node_id}" ]]; then
        cp -a "/etc/Xboard-Node/${node_id}" "${node_dir}/etc-Xboard-Node-node" 2>/dev/null || true
    fi
    if [[ -d "/etc/mi-node/${node_id}" ]]; then
        cp -a "/etc/mi-node/${node_id}" "${node_dir}/etc-mi-node-node" 2>/dev/null || true
    fi
}

stop_old_services() {
    local node_id="$1"
    systemctl stop "xboard-node@${node_id}" 2>/dev/null || true
    systemctl stop xboard-node 2>/dev/null || true
    systemctl stop "mi-node@${node_id}" 2>/dev/null || true
}

disable_old_services() {
    local node_id="$1"
    [[ "$KEEP_OLD_DISABLED" -eq 1 ]] && return 0
    systemctl disable "xboard-node@${node_id}" 2>/dev/null || true
    systemctl disable xboard-node 2>/dev/null || true
}

migrate_one() {
    local cfg="$1"
    local node_id
    local panel_url
    local panel_token
    local kernel_type
    local cert_mode
    local cert_domain
    local cert_dns_provider
    local cert_email
    local cert_http_port
    local gomemlimit
    local gogc
    local egress_socks5_scalar
    local SOCKS5_HOST
    local SOCKS5_PORT
    local SOCKS5_USER
    local SOCKS5_PASS
    local socks5_endpoint
    local egress_shadowsocks_uri
    local backup_root
    local -a dns_envs=()
    local -a args=()
    local item

    node_id="$(node_id_from_config "$cfg")"
    if [[ -z "$node_id" ]]; then
        err "配置缺少 panel.node_id: $cfg"
        return 1
    fi

    panel_url="$(normalize_scalar "$(yaml_get_section_value "$cfg" panel url)")"
    panel_token="$(normalize_scalar "$(yaml_get_section_value "$cfg" panel token)")"
    kernel_type="$(normalize_scalar "$(yaml_get_section_value "$cfg" kernel type)")"
    cert_mode="$(normalize_scalar "$(yaml_get_section_value "$cfg" cert cert_mode)")"
    cert_domain="$(normalize_scalar "$(yaml_get_section_value "$cfg" cert domain)")"
    cert_dns_provider="$(normalize_scalar "$(yaml_get_section_value "$cfg" cert dns_provider)")"
    cert_email="$(normalize_scalar "$(yaml_get_section_value "$cfg" cert email)")"
    cert_http_port="$(normalize_scalar "$(yaml_get_section_value "$cfg" cert http_port)")"
    gomemlimit="$(normalize_scalar "$(yaml_get_section_value "$cfg" runtime gomemlimit)")"
    gogc="$(normalize_scalar "$(yaml_get_section_value "$cfg" runtime gogc)")"
    egress_socks5_scalar="$(normalize_scalar "$(yaml_get_kernel_egress_scalar "$cfg" socks5)")"
    SOCKS5_HOST="$(normalize_scalar "$(yaml_get_kernel_egress_value "$cfg" socks5 address)")"
    SOCKS5_PORT="$(normalize_scalar "$(yaml_get_kernel_egress_value "$cfg" socks5 port)")"
    SOCKS5_USER="$(normalize_scalar "$(yaml_get_kernel_egress_value "$cfg" socks5 username)")"
    SOCKS5_PASS="$(normalize_scalar "$(yaml_get_kernel_egress_value "$cfg" socks5 password)")"
    egress_shadowsocks_uri="$(normalize_scalar "$(yaml_get_kernel_egress_value "$cfg" shadowsocks uri)")"

    if [[ -n "$egress_socks5_scalar" ]]; then
        if ! parse_socks5_uri "$egress_socks5_scalar"; then
            err "无法解析 kernel.egress.socks5: $cfg"
            return 1
        fi
    fi

    mapfile -t dns_envs < <(yaml_get_cert_dns_env "$cfg")

    if [[ -z "$panel_url" || -z "$panel_token" ]]; then
        err "配置缺少 panel.url 或 panel.token: $cfg"
        return 1
    fi

    log "准备迁移 node_id=${node_id}"
    log "配置文件: ${cfg}"
    log "面板地址: ${panel_url}"
    log "内核类型: ${kernel_type:-singbox}"
    log "证书模式: ${cert_mode:-none}"
    if [[ -n "$cert_domain" ]]; then
        log "证书域名: ${cert_domain}"
    fi
    if [[ -n "$SOCKS5_HOST" || -n "$egress_shadowsocks_uri" ]]; then
        if [[ -n "$SOCKS5_HOST" ]]; then
            if [[ -n "$SOCKS5_USER" || -n "$SOCKS5_PASS" ]]; then
                log "默认出站: SOCKS5 ${SOCKS5_HOST}:${SOCKS5_PORT} (带认证)"
            else
                log "默认出站: SOCKS5 ${SOCKS5_HOST}:${SOCKS5_PORT}"
            fi
        else
            log "默认出站: Shadowsocks URI"
        fi
    fi

    args=(--yes -a "$panel_url" -t "$panel_token" -n "$node_id")

    if [[ -n "$kernel_type" ]]; then
        args+=(-k "$kernel_type")
    fi
    if [[ -n "$gomemlimit" ]]; then
        args+=(--gomemlimit "$gomemlimit")
    fi
    if [[ -n "$gogc" && "$gogc" != "0" ]]; then
        args+=(--gogc "$gogc")
    fi
    if [[ -n "$cert_mode" && "$cert_mode" != "none" ]]; then
        args+=(--cert-mode "$cert_mode")
    fi
    if [[ -n "$cert_domain" ]]; then
        args+=(--cert-domain "$cert_domain")
    fi
    if [[ -n "$cert_email" ]]; then
        args+=(--cert-email "$cert_email")
    fi
    if [[ -n "$cert_http_port" ]]; then
        args+=(--cert-http-port "$cert_http_port")
    fi
    if [[ -n "$cert_dns_provider" ]]; then
        args+=(--cert-dns-provider "$cert_dns_provider")
    fi
    for item in "${dns_envs[@]}"; do
        args+=(--cert-dns-env "$item")
    done
    if [[ -n "$SOCKS5_HOST" || -n "$SOCKS5_PORT" || -n "$SOCKS5_USER" || -n "$SOCKS5_PASS" ]]; then
        if [[ -z "$SOCKS5_HOST" || -z "$SOCKS5_PORT" ]]; then
            err "SOCKS5 出站配置缺少 address/port: $cfg"
            return 1
        fi
        if [[ "$SOCKS5_HOST" == *:* ]]; then
            socks5_endpoint="[${SOCKS5_HOST}]:${SOCKS5_PORT}"
        else
            socks5_endpoint="${SOCKS5_HOST}:${SOCKS5_PORT}"
        fi
        args+=(--egress-socks5 "$socks5_endpoint")
        if [[ -n "$SOCKS5_USER" || -n "$SOCKS5_PASS" ]]; then
            if [[ -z "$SOCKS5_USER" || -z "$SOCKS5_PASS" ]]; then
                err "SOCKS5 出站认证必须同时包含 username/password: $cfg"
                return 1
            fi
            args+=(--egress-socks5-user "$SOCKS5_USER" --egress-socks5-pass "$SOCKS5_PASS")
        fi
    fi
    if [[ -n "$egress_shadowsocks_uri" ]]; then
        if [[ -n "$SOCKS5_HOST" || -n "$SOCKS5_PORT" ]]; then
            err "SOCKS5 和 Shadowsocks 默认出站只能二选一: $cfg"
            return 1
        fi
        args+=(--egress-shadowsocks-uri "$egress_shadowsocks_uri")
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[migrate][dry-run] bash <(curl -fsSL %s)' "$(shell_quote "$RAW_URL")"
        for item in "${args[@]}"; do
            printf ' %s' "$(shell_quote "$item")"
        done
        printf '\n'
        return 0
    fi

    backup_root="$(create_backup_root)"
    backup_node "$node_id" "$cfg" "$backup_root"
    stop_old_services "$node_id"

    bash <(curl -fsSL "$RAW_URL") "${args[@]}"

    if systemctl is-active mi-node.service >/dev/null 2>&1; then
        disable_old_services "$node_id"
        log "迁移完成: node_id=${node_id} 已由 mi-node.service 管理"
        log "状态检查: systemctl status mi-node --no-pager"
        log "日志查看: journalctl -u mi-node -n 80 --no-pager"
        return 0
    fi

    if systemctl is-active "mi-node@${node_id}" >/dev/null 2>&1; then
        disable_old_services "$node_id"
        log "迁移完成: mi-node@${node_id}"
        log "状态检查: systemctl status mi-node@${node_id} --no-pager"
        log "日志查看: journalctl -u mi-node@${node_id} -n 80 --no-pager"
        return 0
    fi

    err "mi-node.service 未处于 active 状态，请查看日志: journalctl -u mi-node -n 120 --no-pager"
    return 1
}

main() {
    local -a all_cfgs=()
    local -a selected_cfgs=()
    local cfg
    local matched=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --node-id)
                TARGET_NODE_ID="${2:-}"
                shift 2
                ;;
            --all)
                MIGRATE_ALL=1
                shift
                ;;
            --raw-url)
                RAW_URL="${2:-}"
                shift 2
                ;;
            --backup-root)
                BACKUP_ROOT="${2:-}"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --keep-old-enabled)
                KEEP_OLD_DISABLED=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                err "未知参数: $1"
                usage
                exit 1
                ;;
        esac
    done

    mapfile -t all_cfgs < <(find_candidate_configs)
    if [[ "${#all_cfgs[@]}" -eq 0 ]]; then
        err "未找到可迁移的配置文件"
        exit 1
    fi

    if [[ "$MIGRATE_ALL" -eq 1 ]]; then
        selected_cfgs=("${all_cfgs[@]}")
    elif [[ -n "$TARGET_NODE_ID" ]]; then
        for cfg in "${all_cfgs[@]}"; do
            if [[ "$(node_id_from_config "$cfg")" == "$TARGET_NODE_ID" ]]; then
                selected_cfgs+=("$cfg")
                matched=1
            fi
        done
        if [[ "$matched" -eq 0 ]]; then
            err "未找到 node_id=${TARGET_NODE_ID} 的配置"
            exit 1
        fi
    elif [[ "${#all_cfgs[@]}" -eq 1 ]]; then
        selected_cfgs=("${all_cfgs[@]}")
    else
        err "检测到多个节点配置，请显式传 --node-id 或 --all"
        printf '[migrate] 候选配置:\n'
        for cfg in "${all_cfgs[@]}"; do
            printf '  - node_id=%s  %s\n' "$(node_id_from_config "$cfg")" "$cfg"
        done
        exit 1
    fi

    for cfg in "${selected_cfgs[@]}"; do
        migrate_one "$cfg"
    done
}

main "$@"
