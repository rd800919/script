#!/usr/bin/env bash

# ============================================================
# BYYPRO 网络中转管理系统 v2 Final
# 说明：请仅在你有权管理的服务器与合规网络环境中使用
# 适用：CentOS / Rocky / AlmaLinux / RHEL（优先）
# ============================================================

set -u
umask 022

# ---------------- 颜色 ----------------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------------- 基础配置 ----------------
APP_NAME="中转服务器设置菜单（游戏工作室专用版）"
BASE_DIR="/etc/byypro"
DATA_DIR="${BASE_DIR}/data"
BACKUP_DIR="${BASE_DIR}/backup"
RUN_DIR="${BASE_DIR}/run"
RULES_DB="${DATA_DIR}/rules.db"
SYSCTL_FILE="/etc/sysctl.d/99-byypro.conf"
IPFWD_FILE="/etc/sysctl.d/98-byypro-ipforward.conf"
LOG_DIR="/var/log/byypro"
LOG_FILE="${LOG_DIR}/byypro.log"
SHORTCUT_BIN="/usr/local/bin/byypro"
GOST_BIN="/usr/local/bin/gost"
GOST_VERSION="2.11.5"
UPDATE_URL="https://raw.githubusercontent.com/rd800919/script/refs/heads/main/byypro_v2_final.sh"
CHAIN_PRE="BYYPRO_PREROUTING"
CHAIN_POST="BYYPRO_POSTROUTING"

SELF_PATH="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "$0")"

# ---------------- 公共函数 ----------------
ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_msg() {
    mkdir -p "$LOG_DIR" >/dev/null 2>&1
    echo "[$(ts)] $*" >> "$LOG_FILE"
}

line() {
    echo -e "${CYAN}------------------------------------------------------------${NC}"
}

pause() {
    echo ""
    read -r -p "按回车键继续..." _
}

clear_screen() {
    clear 2>/dev/null || true
}

is_root() {
    [ "${EUID:-$(id -u)}" -eq 0 ]
}

fatal() {
    echo -e "${RED}❌ $*${NC}"
    log_msg "FATAL: $*"
    exit 1
}

warn() {
    echo -e "${YELLOW}⚠ $*${NC}"
    log_msg "WARN: $*"
}

ok() {
    echo -e "${GREEN}✅ $*${NC}"
    log_msg "OK: $*"
}

info() {
    echo -e "${CYAN}$*${NC}"
}

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

ensure_dirs() {
    mkdir -p "$BASE_DIR" "$DATA_DIR" "$BACKUP_DIR" "$RUN_DIR" "$LOG_DIR"
    touch "$RULES_DB" "$LOG_FILE"
}

print_header() {
    clear_screen
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${YELLOW}              ${APP_NAME}              ${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

show_menu() {
    local direct_count="$1"
    local server_count="$2"
    local client_count="$3"

    clear_screen
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${YELLOW}              中转服务器设置菜单（游戏专用版）              ${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e " ${GREEN}当前配置：${NC}单机直连 ${YELLOW}${direct_count}${NC} 条 | 海外接收端 ${YELLOW}${server_count}${NC} 条 | 国内转发端 ${YELLOW}${client_count}${NC} 条"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${GREEN} 1. 新手模式：设置单机直连规则（一台服务器就能用）${NC}"
    echo -e "${GREEN} 2. 双机稳定模式（国内机 + 海外机，更稳）${NC}"
    echo -e "${GREEN} 3. 查看当前转发状态（记录 + 实况）${NC}"
    echo -e "${GREEN} 4. 删除指定编号的配置 / 重新设置${NC}"
    echo -e "${GREEN} 5. 一键网络优化（降低卡顿，建议开启）${NC}"
    echo -e "${GREEN} 6. 一键检测问题（不会排错就点这里）${NC}"
    echo -e "${GREEN} 7. 检查脚本更新${NC}"
    echo -e "${GREEN} 0. 退出${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${PURPLE} 脚本由 BYY 设计 - 2026 最终稳定版${NC}"
    echo -e "${PURPLE} 版本状态：[V2 最终稳定版]（防呆增强 / 更稳 / 更好维护）${NC}"
    echo -e "${PURPLE} WeChat / 微信：x7077796${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${YELLOW} 温馨提示：首次运行会自动安装必要工具，无需手动操作${NC}"
    echo -e "${YELLOW} 温馨提示：以后关闭窗口后，直接输入 ${GREEN}byypro${YELLOW} 回车即可再次打开本菜单${NC}"
    echo ""
}

check_root_or_exit() {
    if ! is_root; then
        clear_screen
        echo -e "${RED}❌ 当前不是 root 权限，脚本无法继续运行${NC}"
        echo -e "请先执行：${YELLOW}sudo su${NC}"
        echo -e "切到 root 后，再重新运行本脚本"
        exit 1
    fi
}

install_shortcut_from_self() {
    [ -f "$SELF_PATH" ] || return 0
    [ -x "$SELF_PATH" ] || chmod +x "$SELF_PATH" >/dev/null 2>&1 || true

    if [ ! -f "$SHORTCUT_BIN" ]; then
        if bash -n "$SELF_PATH" >/dev/null 2>&1; then
            cp -f "$SELF_PATH" "$SHORTCUT_BIN" >/dev/null 2>&1 && chmod +x "$SHORTCUT_BIN" >/dev/null 2>&1
            ok "已自动生成快捷命令 byypro"
            echo -e "以后只要输入 ${YELLOW}byypro${NC} 回车，就能直接打开本菜单"
            log_msg "Installed shortcut: $SHORTCUT_BIN"
        fi
    fi
}

get_pm() {
    if cmd_exists dnf; then
        echo "dnf"
    elif cmd_exists yum; then
        echo "yum"
    elif cmd_exists apt-get; then
        echo "apt-get"
    else
        echo ""
    fi
}

install_pkgs() {
    local pm
    pm="$(get_pm)"
    [ -n "$pm" ] || fatal "没有找到可用的软件包管理器，无法自动安装依赖"

    case "$pm" in
        dnf|yum)
            "$pm" -q -y install "$@" >/dev/null 2>&1
            ;;
        apt-get)
            DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null 2>&1
            ;;
    esac
}

ensure_base_deps() {
    cmd_exists wget || install_pkgs wget
    cmd_exists curl || install_pkgs curl
    cmd_exists gzip || install_pkgs gzip
    if ! cmd_exists ss; then
        case "$(get_pm)" in
            yum|dnf) install_pkgs iproute || true ;;
            apt-get) install_pkgs iproute2 || true ;;
        esac
    fi
}

backup_file() {
    local src="$1"
    [ -f "$src" ] || return 0
    local dst="${BACKUP_DIR}/$(basename "$src").$(date +%Y%m%d_%H%M%S).bak"
    cp -a "$src" "$dst" >/dev/null 2>&1 && log_msg "Backup file: $src -> $dst"
}

backup_iptables() {
    cmd_exists iptables-save || return 0
    local dst="${BACKUP_DIR}/iptables.$(date +%Y%m%d_%H%M%S).bak"
    iptables-save > "$dst" 2>/dev/null && log_msg "Backup iptables: $dst"
}

save_iptables_rules() {
    if cmd_exists service && service iptables save >/dev/null 2>&1; then
        log_msg "iptables rules saved by service iptables save"
        return 0
    fi

    if [ -d /etc/sysconfig ] && cmd_exists iptables-save; then
        iptables-save > /etc/sysconfig/iptables 2>/dev/null && log_msg "iptables rules saved to /etc/sysconfig/iptables"
        return 0
    fi

    if [ -d /etc/iptables ] && cmd_exists iptables-save; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null && log_msg "iptables rules saved to /etc/iptables/rules.v4"
        return 0
    fi

    warn "当前系统未找到可靠的 iptables 持久化方式，重启后规则可能失效"
    return 1
}

ensure_ip_forward() {
    if [ ! -f "$IPFWD_FILE" ] || ! grep -q '^net.ipv4.ip_forward=1$' "$IPFWD_FILE" 2>/dev/null; then
        echo 'net.ipv4.ip_forward=1' > "$IPFWD_FILE"
    fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sysctl --system >/dev/null 2>&1 || true
}

ensure_iptables_ready() {
    if ! cmd_exists iptables; then
        local pm
        pm="$(get_pm)"
        case "$pm" in
            yum|dnf)
                install_pkgs iptables iptables-services
                ;;
            apt-get)
                install_pkgs iptables
                ;;
            *)
                fatal "当前系统无法自动安装 iptables"
                ;;
        esac
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^iptables.service'; then
        systemctl enable --now iptables >/dev/null 2>&1 || true
    fi

    ensure_ip_forward
    ensure_byy_chains
}

ensure_byy_chains() {
    iptables -t nat -N "$CHAIN_PRE" 2>/dev/null || true
    iptables -t nat -N "$CHAIN_POST" 2>/dev/null || true

    iptables -t nat -C PREROUTING -j "$CHAIN_PRE" >/dev/null 2>&1 || iptables -t nat -I PREROUTING 1 -j "$CHAIN_PRE"
    iptables -t nat -C POSTROUTING -j "$CHAIN_POST" >/dev/null 2>&1 || iptables -t nat -I POSTROUTING 1 -j "$CHAIN_POST"
}

get_arch_for_gost() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "" ;;
    esac
}

ensure_gost() {
    if cmd_exists gost; then
        return 0
    fi

    ensure_base_deps

    local arch url tmp_gz tmp_bin
    arch="$(get_arch_for_gost)"
    [ -n "$arch" ] || fatal "暂不支持当前 CPU 架构：$(uname -m)"

    url="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-${arch}-${GOST_VERSION}.gz"
    tmp_gz="/tmp/gost_${arch}_${GOST_VERSION}.gz"
    tmp_bin="/tmp/gost_${arch}_${GOST_VERSION}"

    echo -e "${YELLOW}正在安装 GOST 核心组件，请稍等...${NC}"

    if ! wget -q -O "$tmp_gz" "$url"; then
        rm -f "$tmp_gz" "$tmp_bin"
        fatal "GOST 下载失败，请检查服务器能否访问 GitHub"
    fi

    if ! gzip -dc "$tmp_gz" > "$tmp_bin"; then
        rm -f "$tmp_gz" "$tmp_bin"
        fatal "GOST 解压失败"
    fi

    chmod +x "$tmp_bin" || fatal "GOST 授权失败"
    mv -f "$tmp_bin" "$GOST_BIN" || fatal "GOST 安装失败"
    rm -f "$tmp_gz"
    ok "GOST 安装完成"
}

service_exists() {
    systemctl list-unit-files 2>/dev/null | grep -q "^$1\.service"
}

service_active() {
    systemctl is-active "$1" >/dev/null 2>&1
}

show_local_ips() {
    local ips
    ips="$(hostname -I 2>/dev/null | xargs)"
    if [ -n "$ips" ]; then
        echo "$ips"
    else
        echo "未获取到"
    fi
}

next_rule_id() {
    if [ ! -s "$RULES_DB" ]; then
        echo 1
        return
    fi
    awk -F'|' 'BEGIN{max=0} $1 ~ /^[0-9]+$/ {if ($1>max) max=$1} END{print max+1}' "$RULES_DB"
}

rule_count_by_type() {
    local type="$1"
    awk -F'|' -v t="$type" '$2==t {c++} END{print c+0}' "$RULES_DB"
}

db_add_rule() {
    echo "$*" >> "$RULES_DB"
}

db_get_rule() {
    local id="$1"
    grep -E "^${id}\|" "$RULES_DB" 2>/dev/null | tail -n 1
}

db_delete_rule() {
    local id="$1"
    local tmp="${RULES_DB}.tmp"
    awk -F'|' -v id="$id" '$1 != id' "$RULES_DB" > "$tmp" && mv -f "$tmp" "$RULES_DB"
}

port_in_use() {
    local port="$1"
    ss -lntup 2>/dev/null | awk '{print $5}' | grep -qE "[:.]${port}$"
}

valid_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.'
    local a b c d
    read -r a b c d <<< "$ip"
    for n in "$a" "$b" "$c" "$d"; do
        [ "$n" -ge 0 ] 2>/dev/null && [ "$n" -le 255 ] 2>/dev/null || return 1
    done
    return 0
}

valid_host() {
    local host="$1"
    valid_ipv4 "$host" && return 0
    [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]]
}

mask_text() {
    local s="$1"
    local len=${#s}
    if [ "$len" -le 2 ]; then
        echo "**"
    else
        printf "%s%s" "${s:0:1}" "******"
    fi
}

prompt_port() {
    local prompt="$1"
    local default="${2:-}"
    local v
    while true; do
        if [ -n "$default" ]; then
            read -r -p "$prompt [默认 ${default}，输入 0 返回]: " v
            [ -z "$v" ] && v="$default"
        else
            read -r -p "$prompt [输入 0 返回]: " v
        fi

        [ "$v" = "0" ] && return 1
        if valid_port "$v"; then
            echo "$v"
            return 0
        fi
        echo -e "${RED}❌ 端口必须是 1 到 65535 的纯数字，请重新输入${NC}"
    done
}

prompt_ipv4() {
    local prompt="$1"
    local v
    while true; do
        read -r -p "$prompt [输入 0 返回]: " v
        [ "$v" = "0" ] && return 1
        if valid_ipv4 "$v"; then
            echo "$v"
            return 0
        fi
        echo -e "${RED}❌ 请输入正确的 IPv4 地址，例如：1.2.3.4${NC}"
    done
}

prompt_host() {
    local prompt="$1"
    local v
    while true; do
        read -r -p "$prompt [输入 0 返回]: " v
        [ "$v" = "0" ] && return 1
        if valid_host "$v"; then
            echo "$v"
            return 0
        fi
        echo -e "${RED}❌ 请输入正确的 IP 或域名，例如：1.2.3.4 或 node.example.com${NC}"
    done
}

prompt_text() {
    local prompt="$1"
    local v
    while true; do
        read -r -p "$prompt [输入 0 返回]: " v
        [ "$v" = "0" ] && return 1
        if [ -n "$v" ]; then
            echo "$v"
            return 0
        fi
        echo -e "${RED}❌ 这里不能留空，请重新输入${NC}"
    done
}

confirm_create() {
    while true; do
        echo ""
        echo -e "${YELLOW}确认无误后再创建，避免配错后还要返工${NC}"
        read -r -p "请输入 1 确认创建，2 重新填写，0 返回主菜单: " c
        case "$c" in
            1) return 0 ;;
            2) return 2 ;;
            0) return 1 ;;
            *) echo -e "${RED}请输入 1 / 2 / 0${NC}" ;;
        esac
    done
}

check_tcp_reachable() {
    local host="$1"
    local port="$2"
    timeout 3 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1
}

render_summary_box() {
    line
    printf "%b%s%b\n" "$BLUE" "$1" "$NC"
    shift
    while [ "$#" -gt 0 ]; do
        echo "  $1"
        shift
    done
    line
}

rebuild_direct_rules() {
    ensure_iptables_ready
    backup_iptables

    iptables -t nat -F "$CHAIN_PRE" >/dev/null 2>&1 || true
    iptables -t nat -F "$CHAIN_POST" >/dev/null 2>&1 || true

    while IFS='|' read -r id type name local_port target_host target_port remote_host remote_port service_name extra; do
        [ -n "$id" ] || continue
        [ "$type" = "direct" ] || continue

        iptables -t nat -A "$CHAIN_PRE" -p tcp --dport "$local_port" -m comment --comment "BYYPRO_ID=${id}_TCP" -j DNAT --to-destination "${target_host}:${target_port}"
        iptables -t nat -A "$CHAIN_POST" -p tcp -d "$target_host" --dport "$target_port" -m comment --comment "BYYPRO_ID=${id}_TCP" -j MASQUERADE
        iptables -t nat -A "$CHAIN_PRE" -p udp --dport "$local_port" -m comment --comment "BYYPRO_ID=${id}_UDP" -j DNAT --to-destination "${target_host}:${target_port}"
        iptables -t nat -A "$CHAIN_POST" -p udp -d "$target_host" --dport "$target_port" -m comment --comment "BYYPRO_ID=${id}_UDP" -j MASQUERADE
    done < "$RULES_DB"

    save_iptables_rules >/dev/null 2>&1 || true
    log_msg "Direct rules rebuilt from database"
}

create_direct_rule() {
    local local_port remote_ip remote_port create_result rule_id

    while true; do
        print_header
        echo -e "${GREEN}1）设置中转规则 - 新手模式（单机直连）${NC}"
        echo "适合：你只有一台服务器时使用，把这台机器上的某个端口，直接转发到目标节点"
        echo "你只需要记住：以后你的软件或客户端，直接连这台机器的【本地端口】即可"
        line

        local_port="$(prompt_port '步骤 1/3：你的软件要连这台机器的哪个端口？例如 1080 / 8080')" || return 0
        if port_in_use "$local_port"; then
            warn "检测到端口 ${local_port} 可能已被其他程序占用，继续使用可能会冲突"
            read -r -p "继续创建请按 1，重新填写请按 2，返回请按 0: " create_result
            case "$create_result" in
                1) ;;
                2) continue ;;
                *) return 0 ;;
            esac
        fi

        if grep -E "^[0-9]+\|[^|]+\|[^|]*\|${local_port}\|" "$RULES_DB" >/dev/null 2>&1; then
            warn "数据库里已经存在使用本地端口 ${local_port} 的配置，建议换一个端口，避免冲突"
            pause
            return 0
        fi

        remote_ip="$(prompt_ipv4 '步骤 2/3：最终目标机器 IP 是多少？例如 1.2.3.4')" || return 0
        remote_port="$(prompt_port '步骤 3/3：最终目标机器端口是多少？例如 1080 / 443')" || return 0

        render_summary_box "请确认本次中转规则" \
            "模式：单机直连" \
            "本地端口：${local_port}" \
            "目标地址：${remote_ip}:${remote_port}" \
            "协议：TCP + UDP"

        if check_tcp_reachable "$remote_ip" "$remote_port"; then
            ok "预检测：TCP 目标可连通"
        else
            warn "预检测：TCP 目标暂时无法连通，可能是目标没开、被防火墙拦截，或网络暂时不通"
        fi

        confirm_create
        create_result="$?"
        case "$create_result" in
            0) break ;;
            1) return 0 ;;
            2) continue ;;
        esac
    done

    ensure_iptables_ready
    rule_id="$(next_rule_id)"
    db_add_rule "${rule_id}|direct|单机直连|${local_port}|${remote_ip}|${remote_port}||||$(ts)"
    rebuild_direct_rules

    render_summary_box "设置完成" \
        "规则编号：${rule_id}" \
        "模式：单机直连" \
        "你的软件或客户端以后这样填写：" \
        "服务器地址：这台机器的 IP" \
        "端口：${local_port}"
    ok "单机直连规则已创建成功"
}

create_tunnel_server() {
    local tunnel_port tunnel_pass service_name create_result rule_id

    while true; do
        print_header
        echo -e "${RED}2）双机稳定模式 - 海外机设置${NC}"
        echo "适合：你现在操作的是【海外机】"
        echo "不会配也没关系，按步骤填就行，后面会告诉你国内机要填什么"
        echo "这一步会在海外机上创建接收端，后面国内机要来连接这里"
        line

        tunnel_port="$(prompt_port '步骤 1/2：请设置海外机监听端口，推荐 443' '443')" || return 0
        if port_in_use "$tunnel_port"; then
            warn "检测到端口 ${tunnel_port} 可能已被其他程序占用，继续使用可能会冲突"
            read -r -p "继续创建请按 1，重新填写请按 2，返回请按 0: " create_result
            case "$create_result" in
                1) ;;
                2) continue ;;
                *) return 0 ;;
            esac
        fi

        tunnel_pass="$(prompt_text '步骤 2/2：请设置隧道密码，例如 123456 或自定义复杂一点')" || return 0

        render_summary_box "请确认本次中转规则" \
            "模式：双机稳定模式 - 海外机" \
            "海外监听端口：${tunnel_port}" \
            "隧道密码：$(mask_text "$tunnel_pass")" \
            "作用：等待国内机接入"

        confirm_create
        create_result="$?"
        case "$create_result" in
            0) break ;;
            1) return 0 ;;
            2) continue ;;
        esac
    done

    ensure_gost
    rule_id="$(next_rule_id)"
    service_name="byypro-gost-server-${rule_id}"

    cat > "/etc/systemd/system/${service_name}.service" <<EOF_SERVER
[Unit]
Description=BYYPRO GOST Tunnel Server #${rule_id}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${GOST_BIN} -L relay+tls://admin:${tunnel_pass}@:${tunnel_port}
Restart=always
RestartSec=3
StartLimitIntervalSec=0
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF_SERVER

    systemctl daemon-reload || fatal "systemd 重新加载失败"
    if ! systemctl enable --now "${service_name}" >/dev/null 2>&1; then
        rm -f "/etc/systemd/system/${service_name}.service"
        systemctl daemon-reload >/dev/null 2>&1 || true
        fatal "海外机服务启动失败，请检查端口是否冲突，或查看日志：journalctl -u ${service_name} -n 50"
    fi

    db_add_rule "${rule_id}|tunnel_server|双机稳定-海外机|${tunnel_port}|||||${service_name}|$(ts)"

    render_summary_box "海外机设置完成" \
        "规则编号：${rule_id}" \
        "海外机 IP：$(show_local_ips)" \
        "隧道端口：${tunnel_port}" \
        "隧道密码：${tunnel_pass}" \
        "下一步：去登录国内机，再选择【双机稳定模式】里的国内机设置"

    if service_active "$service_name"; then
        ok "海外机服务正在运行中"
    else
        warn "海外机服务已创建，但当前状态不是运行中，请执行：journalctl -u ${service_name} -n 50"
    fi
}

create_tunnel_client() {
    local local_port game_host game_port remote_host remote_port tunnel_pass create_result rule_id service_name

    while true; do
        print_header
        echo -e "${RED}2）双机稳定模式 - 国内机设置${NC}"
        echo "适合：你现在操作的是【国内机】"
        echo "不会配也没关系，按步骤填就行，前提是海外机那边要先设置好"
        echo "这一步会把国内机的本地端口，通过海外机转发到最终目标地址"
        line

        local_port="$(prompt_port '步骤 1/6：你的软件要连这台国内机的哪个端口？例如 1080 / 8080')" || return 0
        if port_in_use "$local_port"; then
            warn "检测到端口 ${local_port} 可能已被其他程序占用，继续使用可能会冲突"
            read -r -p "继续创建请按 1，重新填写请按 2，返回请按 0: " create_result
            case "$create_result" in
                1) ;;
                2) continue ;;
                *) return 0 ;;
            esac
        fi

        if grep -E "^[0-9]+\|[^|]+\|[^|]*\|${local_port}\|" "$RULES_DB" >/dev/null 2>&1; then
            warn "数据库里已经存在使用本地端口 ${local_port} 的配置，建议换一个端口，避免冲突"
            pause
            return 0
        fi

        game_host="$(prompt_host '步骤 2/6：最终目标机器 IP 或域名是多少？例如 1.2.3.4 或 node.example.com')" || return 0
        game_port="$(prompt_port '步骤 3/6：最终目标机器端口是多少？例如 1080 / 443')" || return 0
        remote_host="$(prompt_host '步骤 4/6：海外机 IP 或域名是多少？例如 8.8.8.8')" || return 0
        remote_port="$(prompt_port '步骤 5/6：海外机隧道端口是多少？通常填 443' '443')" || return 0
        tunnel_pass="$(prompt_text '步骤 6/6：你刚刚在海外机设置的隧道密码是什么？')" || return 0

        render_summary_box "请确认本次中转规则" \
            "模式：双机稳定模式 - 国内机" \
            "国内本地端口：${local_port}" \
            "最终目标：${game_host}:${game_port}" \
            "海外机地址：${remote_host}:${remote_port}" \
            "隧道密码：$(mask_text "$tunnel_pass")"

        if check_tcp_reachable "$remote_host" "$remote_port"; then
            ok "预检测：海外机端口可连通"
        else
            warn "预检测：海外机端口暂时无法连通，请先确认海外机服务已启动、端口已放行"
        fi

        if check_tcp_reachable "$game_host" "$game_port"; then
            ok "预检测：最终目标 TCP 可连通"
        else
            warn "预检测：最终目标 TCP 暂时无法连通，后续可能会导致转发不通"
        fi

        confirm_create
        create_result="$?"
        case "$create_result" in
            0) break ;;
            1) return 0 ;;
            2) continue ;;
        esac
    done

    ensure_gost
    rule_id="$(next_rule_id)"
    service_name="byypro-gost-client-${rule_id}"

    cat > "/etc/systemd/system/${service_name}.service" <<EOF_CLIENT
[Unit]
Description=BYYPRO GOST Tunnel Client #${rule_id}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${GOST_BIN} -L tcp://:${local_port}/${game_host}:${game_port} -L udp://:${local_port}/${game_host}:${game_port} -F relay+tls://admin:${tunnel_pass}@${remote_host}:${remote_port}
Restart=always
RestartSec=3
StartLimitIntervalSec=0
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF_CLIENT

    systemctl daemon-reload || fatal "systemd 重新加载失败"
    if ! systemctl enable --now "${service_name}" >/dev/null 2>&1; then
        rm -f "/etc/systemd/system/${service_name}.service"
        systemctl daemon-reload >/dev/null 2>&1 || true
        fatal "国内机服务启动失败，请检查端口、海外机地址、密码是否填写正确"
    fi

    db_add_rule "${rule_id}|tunnel_client|双机稳定-国内机|${local_port}|${game_host}|${game_port}|${remote_host}|${remote_port}|${service_name}|$(ts)"

    render_summary_box "国内机设置完成" \
        "规则编号：${rule_id}" \
        "你的软件或客户端以后这样填写：" \
        "服务器地址：这台国内机的 IP" \
        "端口：${local_port}" \
        "最终目标：${game_host}:${game_port}" \
        "海外机：${remote_host}:${remote_port}"

    if service_active "$service_name"; then
        ok "国内机服务正在运行中"
    else
        warn "国内机服务已创建，但当前状态不是运行中，请执行：journalctl -u ${service_name} -n 50"
    fi
}

menu_tunnel_mode() {
    while true; do
        print_header
        echo -e "${RED}2）双机稳定模式${NC}"
        echo "如果你有【国内机 + 海外机】两台机器，建议使用这个模式，通常会更稳"
        echo "不知道自己在操作哪台机器，就先看机器所在位置：国外是海外机，国内是国内机"
        echo ""
        echo "  1. 我现在操作的是【海外机】"
        echo "  2. 我现在操作的是【国内机】"
        echo "  0. 返回主菜单"
        line
        read -r -p "请输入数字 [0-2]: " c
        case "$c" in
            1) create_tunnel_server; pause ;;
            2) create_tunnel_client; pause ;;
            0) return 0 ;;
            *) echo -e "${RED}❌ 请输入 0 / 1 / 2${NC}"; sleep 1 ;;
        esac
    done
}

print_status() {
    local direct_count server_count client_count
    direct_count="$(rule_count_by_type direct)"
    server_count="$(rule_count_by_type tunnel_server)"
    client_count="$(rule_count_by_type tunnel_client)"

    print_header
    echo -e "${GREEN}3）查看当前转发状态（记录 + 实况）${NC}"
    echo -e "${GREEN}当前服务器 IP：${NC}$(show_local_ips)"
    echo -e "${GREEN}当前转发数量：${NC}单机直连 ${YELLOW}${direct_count}${NC} 条 | 海外接收端 ${YELLOW}${server_count}${NC} 条 | 国内转发端 ${YELLOW}${client_count}${NC} 条"
    line

    if [ ! -s "$RULES_DB" ]; then
        echo "当前还没有任何转发配置"
        return 0
    fi

    while IFS='|' read -r id type name local_port target_host target_port remote_host remote_port service_name extra; do
        [ -n "$id" ] || continue
        case "$type" in
            direct)
                echo -e "${BLUE}[编号 ${id}] 新手模式 - 单机直连${NC}"
                echo "  本地端口：${local_port}"
                echo "  目标地址：${target_host}:${target_port}"
                if check_tcp_reachable "$target_host" "$target_port"; then
                    echo -e "  TCP 检测：${GREEN}可连接${NC}"
                else
                    echo -e "  TCP 检测：${RED}暂时不可连接${NC}"
                fi
                line
                ;;
            tunnel_server)
                echo -e "${BLUE}[编号 ${id}] 双机稳定模式 - 海外机${NC}"
                echo "  监听端口：${local_port}"
                echo "  服务名：${service_name}.service"
                if service_active "$service_name"; then
                    echo -e "  服务状态：${GREEN}运行中${NC}"
                else
                    echo -e "  服务状态：${RED}异常或未运行${NC}"
                fi
                line
                ;;
            tunnel_client)
                echo -e "${BLUE}[编号 ${id}] 双机稳定模式 - 国内机${NC}"
                echo "  本地端口：${local_port}"
                echo "  最终目标：${target_host}:${target_port}"
                echo "  海外机：${remote_host}:${remote_port}"
                echo "  服务名：${service_name}.service"
                if service_active "$service_name"; then
                    echo -e "  服务状态：${GREEN}运行中${NC}"
                else
                    echo -e "  服务状态：${RED}异常或未运行${NC}"
                fi
                if check_tcp_reachable "$remote_host" "$remote_port"; then
                    echo -e "  海外机连通：${GREEN}可连接${NC}"
                else
                    echo -e "  海外机连通：${RED}暂时不可连接${NC}"
                fi
                if check_tcp_reachable "$target_host" "$target_port"; then
                    echo -e "  最终目标 TCP：${GREEN}可连接${NC}"
                else
                    echo -e "  最终目标 TCP：${RED}暂时不可连接${NC}"
                fi
                line
                ;;
        esac
    done < "$RULES_DB"
}

remove_rule_menu() {
    local id rule type name local_port target_host target_port remote_host remote_port service_name extra c

    if [ ! -s "$RULES_DB" ]; then
        print_header
        echo "当前没有任何配置可以删除"
        pause
        return 0
    fi

    while true; do
        print_status
        echo ""
        echo -e "${GREEN}4）删除指定编号的配置 / 重新设置${NC}"
        read -r -p "请输入要删除的【规则编号】，输入 0 返回主菜单: " id
        [ "$id" = "0" ] && return 0
        rule="$(db_get_rule "$id")"
        if [ -z "$rule" ]; then
            echo -e "${RED}❌ 找不到这个编号，请重新输入${NC}"
            sleep 1
            continue
        fi

        IFS='|' read -r id type name local_port target_host target_port remote_host remote_port service_name extra <<< "$rule"
        render_summary_box "请确认要删除的配置" \
            "编号：${id}" \
            "类型：${name}" \
            "本地端口：${local_port}" \
            "目标：${target_host:+${target_host}:${target_port}}" \
            "海外机：${remote_host:+${remote_host}:${remote_port}}" \
            "服务：${service_name:+${service_name}.service}"

        read -r -p "确认删除请输入 1，重新选择请输入 2，返回请输入 0: " c
        case "$c" in
            1)
                case "$type" in
                    direct)
                        db_delete_rule "$id"
                        rebuild_direct_rules
                        ok "单机直连规则已删除"
                        ;;
                    tunnel_server|tunnel_client)
                        if [ -n "$service_name" ] && service_exists "$service_name"; then
                            systemctl stop "$service_name" >/dev/null 2>&1 || true
                            systemctl disable "$service_name" >/dev/null 2>&1 || true
                            rm -f "/etc/systemd/system/${service_name}.service"
                            systemctl daemon-reload >/dev/null 2>&1 || true
                        fi
                        db_delete_rule "$id"
                        ok "服务配置已删除"
                        ;;
                    *)
                        warn "未知规则类型，已仅从数据库中移除"
                        db_delete_rule "$id"
                        ;;
                esac
                pause
                return 0
                ;;
            2) continue ;;
            0) return 0 ;;
            *) echo -e "${RED}请输入 1 / 2 / 0${NC}"; sleep 1 ;;
        esac
    done
}

apply_network_optimization() {
    print_header
    echo -e "${GREEN}5）一键网络优化（降低卡顿，建议开启）${NC}"
    echo "这一步会把优化写入独立配置文件，不会乱改系统主配置"
    echo "适合想提升 TCP 稳定性、连接恢复能力、减少卡顿的场景"
    line
    echo "即将写入：${SYSCTL_FILE}"
    echo ""
    read -r -p "确认应用请输入 1，取消请输入 0: " c
    [ "$c" = "1" ] || return 0

    backup_file "$SYSCTL_FILE"

    cat > "$SYSCTL_FILE" <<'EOF_SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=8192
net.ipv4.tcp_fin_timeout=15
EOF_SYSCTL

    sysctl --system >/dev/null 2>&1 || true

    render_summary_box "优化已写入" \
        "配置文件：${SYSCTL_FILE}" \
        "当前拥塞控制：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)" \
        "当前队列算法：$(sysctl -n net.core.default_qdisc 2>/dev/null || echo 未知)" \
        "如需恢复，可在主菜单里执行一键检测后手动删除该文件，再执行 sysctl --system"
    ok "网络优化已应用"
    pause
}

run_diagnostics() {
    print_header
    echo -e "${GREEN}6）一键检测问题（不会排错就点这里）${NC}"
    line

    echo -n "1. root 权限："
    if is_root; then echo -e "${GREEN}正常${NC}"; else echo -e "${RED}异常${NC}"; fi

    echo -n "2. systemd："
    if cmd_exists systemctl; then echo -e "${GREEN}已检测到${NC}"; else echo -e "${RED}未检测到${NC}"; fi

    echo -n "3. iptables："
    if cmd_exists iptables; then echo -e "${GREEN}已安装${NC}"; else echo -e "${RED}未安装${NC}"; fi

    echo -n "4. GOST："
    if cmd_exists gost; then
        echo -e "${GREEN}已安装${NC} ($(gost -V 2>/dev/null | head -n 1 || echo version_unknown))"
    else
        echo -e "${YELLOW}未安装${NC}（只有使用双机稳定模式时才需要）"
    fi

    echo -n "5. IP 转发："
    if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" = "1" ]; then
        echo -e "${GREEN}已开启${NC}"
    else
        echo -e "${RED}未开启${NC}"
    fi

    echo -n "6. BBR："
    if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo none)" = "bbr" ]; then
        echo -e "${GREEN}已开启${NC}"
    else
        echo -e "${YELLOW}未开启${NC}"
    fi

    echo -e "7. 当前服务器 IP：${GREEN}$(show_local_ips)${NC}"

    echo -n "8. BYYPRO NAT 独立链："
    if iptables -t nat -S "$CHAIN_PRE" >/dev/null 2>&1 && iptables -t nat -S "$CHAIN_POST" >/dev/null 2>&1; then
        echo -e "${GREEN}存在${NC}"
    else
        echo -e "${RED}不存在${NC}"
    fi

    line
    echo -e "${YELLOW}服务状态速览${NC}"
    if [ -s "$RULES_DB" ]; then
        while IFS='|' read -r id type name local_port target_host target_port remote_host remote_port service_name extra; do
            [ -n "$id" ] || continue
            case "$type" in
                tunnel_server|tunnel_client)
                    printf "[%s] %s -> " "$id" "$name"
                    if [ -n "$service_name" ] && service_active "$service_name"; then
                        echo -e "${GREEN}运行中${NC}"
                    else
                        echo -e "${RED}异常或未运行${NC}"
                    fi
                    ;;
                direct)
                    printf "[%s] 单机直连 %s -> %s:%s\n" "$id" "$local_port" "$target_host" "$target_port"
                    ;;
            esac
        done < "$RULES_DB"
    else
        echo "当前没有配置"
    fi

    line
    echo -e "${YELLOW}最近日志位置：${NC}${LOG_FILE}"
    echo -e "${YELLOW}如服务异常，可查看：${NC}journalctl -u 服务名 -n 50 --no-pager"
    pause
}

update_script() {
    print_header
    echo -e "${GREEN}7）检查脚本更新${NC}"
    if [ -z "$UPDATE_URL" ]; then
        warn "当前脚本未配置更新地址"
        pause
        return 0
    fi

    ensure_base_deps
    local tmp_file current_hash new_hash
    tmp_file="/tmp/byypro_update_$$.sh"

    echo "正在检查更新..."
    if ! curl -fsSL "$UPDATE_URL" -o "$tmp_file" && ! wget -q -O "$tmp_file" "$UPDATE_URL"; then
        rm -f "$tmp_file"
        warn "下载更新失败，已保留当前版本"
        pause
        return 0
    fi

    if ! bash -n "$tmp_file" >/dev/null 2>&1; then
        rm -f "$tmp_file"
        warn "下载到的新版本语法校验未通过，已保留当前版本"
        pause
        return 0
    fi

    current_hash="$(sha256sum "$SHORTCUT_BIN" 2>/dev/null | awk '{print $1}')"
    new_hash="$(sha256sum "$tmp_file" | awk '{print $1}')"

    if [ -n "$current_hash" ] && [ "$current_hash" = "$new_hash" ]; then
        rm -f "$tmp_file"
        ok "当前已经是最新内容，无需更新"
        pause
        return 0
    fi

    if [ -f "$SHORTCUT_BIN" ]; then
        backup_file "$SHORTCUT_BIN"
    fi

    mv -f "$tmp_file" "$SHORTCUT_BIN" && chmod +x "$SHORTCUT_BIN"
    ok "脚本已更新成功"
    echo -e "以后直接输入 ${YELLOW}byypro${NC} 回车，即可进入新版本"
    pause
}

main_menu() {
    while true; do
        local direct_count server_count client_count
        direct_count="$(rule_count_by_type direct)"
        server_count="$(rule_count_by_type tunnel_server)"
        client_count="$(rule_count_by_type tunnel_client)"

        show_menu "$direct_count" "$server_count" "$client_count"
        read -r -p "请输入对应的数字 [0-7]: " choice
        case "$choice" in
            1) create_direct_rule; pause ;;
            2) menu_tunnel_mode ;;
            3) print_status; pause ;;
            4) remove_rule_menu ;;
            5) apply_network_optimization ;;
            6) run_diagnostics ;;
            7) update_script ;;
            0)
                echo ""
                ok "感谢使用，祝老板使用顺利、一路稳定"
                echo -e "${YELLOW}下次如需继续设置，直接输入 ${GREEN}byypro${YELLOW} 回车即可再次打开菜单${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 请输入菜单上有的数字 0 到 7${NC}"
                sleep 1
                ;;
        esac
    done
}

main() {
    check_root_or_exit
    ensure_dirs
    install_shortcut_from_self
    ensure_base_deps
    log_msg "Script started by user $(whoami) from $SELF_PATH"
    main_menu
}

main "$@"
