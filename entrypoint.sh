#!/bin/sh
# MicroWARP entrypoint — dual-stack Cloudflare WARP SOCKS5 proxy
# Protocols: WireGuard (kernel, default) | MASQUE (usque userspace)
# shellcheck shell=sh
set -eu

# ==========================================
# Defaults
# ==========================================
WG_CONF="${WG_CONF:-/etc/wireguard/wg0.conf}"
WG_DIR="$(dirname "$WG_CONF")"
WG_IFACE="${WG_IFACE:-wg0}"
WG_MTU="${MTU:-1280}"
LISTEN_ADDR="${BIND_ADDR:-0.0.0.0}"
LISTEN_PORT="${BIND_PORT:-1080}"
ENABLE_IPV6="${ENABLE_IPV6:-1}"
TAILSCALE_CIDR="${TAILSCALE_CIDR:-100.64.0.0/10}"
TAILSCALE_CIDR_V6="${TAILSCALE_CIDR_V6:-fd7a:115c:a1e0::/48}"
KEEPALIVE="${KEEPALIVE:-15}"
# Fallback when GitHub API is unavailable / rate-limited
WGCF_FALLBACK_VER="${WGCF_FALLBACK_VER:-2.2.29}"
CURL_TIMEOUT="${CURL_TIMEOUT:-15}"
# Keep egress probe short so it never delays SOCKS readiness
TRACE_TIMEOUT="${TRACE_TIMEOUT:-3}"
TRACE_CONNECT_TIMEOUT="${TRACE_CONNECT_TIMEOUT:-2}"

# Tunnel protocol: wireguard (default) | masque
# Aliases: wg → wireguard; usque → masque
TUNNEL_PROTOCOL="${TUNNEL_PROTOCOL:-wireguard}"

# MASQUE / usque
# Config co-located under /etc/wireguard so existing warp-data volume persists it.
USQUE_CONFIG="${USQUE_CONFIG:-/etc/wireguard/masque-config.json}"
# l4-socks = lighter TCP-only (recommended); socks = full gVisor L3 (TCP+UDP, heavier)
MASQUE_PROXY_MODE="${MASQUE_PROXY_MODE:-l4-socks}"
MASQUE_HTTP2="${MASQUE_HTTP2:-0}"
MASQUE_SNI="${MASQUE_SNI:-}"
MASQUE_MTU="${MASQUE_MTU:-}"
# Optional identity extras
WARP_JWT="${WARP_JWT:-}"
WARP_LICENSE="${WARP_LICENSE:-}"
USQUE_DEVICE_NAME="${USQUE_DEVICE_NAME:-MicroWARP}"
# Cap Go runtime RSS on small VPS (MASQUE path only; ignored by WireGuard path)
GOMEMLIMIT="${GOMEMLIMIT:-512MiB}"

# ==========================================
# Logging helpers
# ==========================================
log()  { printf '%s\n' "==> [MicroWARP] $*"; }
warn() { printf '%s\n' "==> [MicroWARP] ⚠️  $*" >&2; }
die()  { printf '%s\n' "==> [MicroWARP] ❌ $*" >&2; exit 1; }

# ==========================================
# Test mode (CI / dry-run)
# ==========================================
if [ "${MICROWARP_TEST_MODE:-0}" = "1" ]; then
    log "测试模式已启用，跳过全部初始化。"
    exit 0
fi

# ==========================================
# Utility
# ==========================================
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Run a command with a hard wall-clock limit when possible.
# Usage: run_with_timeout SECONDS command [args...]
run_with_timeout() {
    secs="$1"
    shift
    if command_exists timeout; then
        timeout "$secs" "$@" 2>/dev/null && return 0
        timeout -t "$secs" "$@" 2>/dev/null && return 0
        return 1
    fi
    "$@"
}

github_auth_header() {
    token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [ -n "$token" ]; then
        printf 'Authorization: Bearer %s' "$token"
    fi
}

detect_arch() {
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  printf 'amd64' ;;
        aarch64|arm64) printf 'arm64' ;;
        armv7l|armhf)  printf 'armv7' ;;
        *) die "不支持的架构: $arch" ;;
    esac
}

build_wgcf_download_url() {
    ver="$1"
    arch="$2"
    raw="https://github.com/ViRb3/wgcf/releases/download/v${ver}/wgcf_${ver}_linux_${arch}"
    if [ -n "${GH_PROXY:-}" ]; then
        printf '%s/%s' "${GH_PROXY%/}" "$raw"
    else
        printf '%s' "$raw"
    fi
}

fetch_latest_wgcf_version() {
    api="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
    auth="$(github_auth_header)"
    body=""

    if [ -n "$auth" ]; then
        body="$(curl -fsSL -m "$CURL_TIMEOUT" -H "$auth" "$api" 2>/dev/null || true)"
    else
        body="$(curl -fsSL -m "$CURL_TIMEOUT" "$api" 2>/dev/null || true)"
    fi

    ver="$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\([^"]*\)".*/\1/p' | head -n 1)"
    if [ -z "$ver" ]; then
        warn "无法从 GitHub API 获取 wgcf 版本，使用回退版本 v${WGCF_FALLBACK_VER}"
        printf '%s' "$WGCF_FALLBACK_VER"
        return 0
    fi
    printf '%s' "$ver"
}

download_file() {
    url="$1"
    dest="$2"
    tries=0
    max_tries=3

    while [ "$tries" -lt "$max_tries" ]; do
        tries=$((tries + 1))
        if command_exists wget; then
            if wget --timeout=30 -qO "$dest" "$url" 2>/dev/null; then
                [ -s "$dest" ] && return 0
            fi
        fi
        if command_exists curl; then
            if curl -fsSL -m 30 -o "$dest" "$url" 2>/dev/null; then
                [ -s "$dest" ] && return 0
            fi
        fi
        warn "下载失败 (尝试 ${tries}/${max_tries}): $url"
        sleep $((tries * 2))
    done
    return 1
}

# Extract first IPv4 CIDR from text
extract_ipv4_cidr() {
    printf '%s' "$1" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | head -n 1
}

# Extract first IPv6 CIDR (comma/space separated tokens with ':')
extract_ipv6_cidr() {
    printf '%s' "$1" \
        | tr ',' '\n' \
        | tr ' ' '\n' \
        | grep -E '^[0-9a-fA-F:]+/[0-9]{1,3}$' \
        | grep -E ':' \
        | head -n 1
}

is_truthy() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

iface_has_global_ipv6() {
    dev="$1"
    ip -6 addr show dev "$dev" scope global 2>/dev/null | grep -q 'inet6 '
}

normalize_tunnel_protocol() {
    raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$raw" in
        wireguard|wg|wg0|kernel) printf 'wireguard' ;;
        masque|usque|h3|http3|quic) printf 'masque' ;;
        *) die "未知 TUNNEL_PROTOCOL='$1'（支持: wireguard | masque）" ;;
    esac
}

normalize_masque_proxy_mode() {
    raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$raw" in
        l4|l4-socks|l4_socks|l4socks) printf 'l4-socks' ;;
        socks|full|gvisor|l3) printf 'socks' ;;
        *) die "未知 MASQUE_PROXY_MODE='$1'（支持: l4-socks | socks）" ;;
    esac
}

# ==========================================
# 1. Account registration / config bootstrap (WireGuard / wgcf)
# ==========================================
register_warp() {
    log "未检测到配置，正在全自动初始化 Cloudflare WARP (WireGuard)..."

    arch="$(detect_arch)"
    ver="$(fetch_latest_wgcf_version)"
    log "检测到 wgcf 版本: v${ver} (${arch})"

    url="$(build_wgcf_download_url "$ver" "$arch")"
    workdir="$(mktemp -d /tmp/microwarp.XXXXXX)" || die "无法创建临时目录"
    # shellcheck disable=SC2064
    trap 'rm -rf "$workdir"' EXIT INT TERM

    if ! download_file "$url" "$workdir/wgcf"; then
        die "wgcf 二进制下载失败: $url"
    fi
    chmod +x "$workdir/wgcf"

    log "正在向 Cloudflare 注册设备..."
    # wgcf writes account next to CWD; silence both stdout and stderr noise
    if ! (
        cd "$workdir"
        ./wgcf register --accept-tos >/dev/null 2>&1
        log "正在生成 WireGuard 配置..."
        ./wgcf generate >/dev/null 2>&1
    ); then
        die "wgcf 注册或配置生成失败"
    fi

    if [ ! -f "$workdir/wgcf-profile.conf" ]; then
        die "未找到 wgcf-profile.conf，注册可能失败"
    fi

    mv "$workdir/wgcf-profile.conf" "$WG_CONF"
    # Burn-after-read: drop account material & binary
    rm -rf "$workdir"
    trap - EXIT INT TERM
    log "节点配置生成成功"
}

# ==========================================
# 2. Sanitize & rebuild WireGuard profile
# ==========================================
sanitize_config() {
    [ -f "$WG_CONF" ] || die "配置文件不存在: $WG_CONF"

    # Snapshot raw Address lines before mutation
    raw_address="$(grep -E '^[[:space:]]*Address[[:space:]]*=' "$WG_CONF" || true)"
    ipv4_addr="$(extract_ipv4_cidr "$raw_address")"
    ipv6_addr="$(extract_ipv6_cidr "$raw_address")"

    if [ -z "$ipv4_addr" ]; then
        ipv4_addr="$(extract_ipv4_cidr "$(cat "$WG_CONF")")"
    fi
    if [ -z "$ipv6_addr" ]; then
        ipv6_addr="$(extract_ipv6_cidr "$(cat "$WG_CONF")")"
    fi

    if [ -z "$ipv4_addr" ]; then
        die "无法从配置中解析 IPv4 Address，配置可能已损坏"
    fi

    # Drop fields we will rewrite (BusyBox-safe patterns)
    sed -i \
        -e '/^[[:space:]]*Address[[:space:]]*=/d' \
        -e '/^[[:space:]]*AllowedIPs[[:space:]]*=/d' \
        -e '/^[[:space:]]*DNS[[:space:]]*=/d' \
        -e '/^[[:space:]]*[Mm][Tt][Uu][[:space:]]*=/d' \
        "$WG_CONF"

    # Build Address value (dual-stack when available)
    if is_truthy "$ENABLE_IPV6" && [ -n "$ipv6_addr" ]; then
        address_value="${ipv4_addr},${ipv6_addr}"
        log "双栈地址: IPv4=${ipv4_addr}  IPv6=${ipv6_addr}"
    else
        address_value="$ipv4_addr"
        if is_truthy "$ENABLE_IPV6" && [ -z "$ipv6_addr" ]; then
            warn "ENABLE_IPV6=1 但配置中无 IPv6 地址，仅启用 IPv4"
        else
            log "IPv4 地址: ${ipv4_addr}"
        fi
    fi

    if ! grep -q '^\[Interface\]' "$WG_CONF"; then
        die "配置缺少 [Interface] 段"
    fi
    sed -i "/^\[Interface\]/a Address = ${address_value}" "$WG_CONF"
    sed -i "/^\[Interface\]/a MTU = ${WG_MTU}" "$WG_CONF"
    log "MTU = ${WG_MTU}"

    # AllowedIPs under [Peer]
    if is_truthy "$ENABLE_IPV6" && [ -n "$ipv6_addr" ]; then
        allowed_ips="0.0.0.0/0, ::/0"
    else
        allowed_ips="0.0.0.0/0"
    fi

    if ! grep -q '^\[Peer\]' "$WG_CONF"; then
        die "配置缺少 [Peer] 段"
    fi
    sed -i "/^\[Peer\]/a AllowedIPs = ${allowed_ips}" "$WG_CONF"

    # PersistentKeepalive — defeat NAT/QoS idle drops
    if grep -qi '^[[:space:]]*PersistentKeepalive[[:space:]]*=' "$WG_CONF"; then
        sed -i "s/^[[:space:]]*PersistentKeepalive[[:space:]]*=.*/PersistentKeepalive = ${KEEPALIVE}/g" "$WG_CONF"
    else
        sed -i "/^\[Peer\]/a PersistentKeepalive = ${KEEPALIVE}" "$WG_CONF"
    fi

    # Optional custom endpoint (IPv4 host:port or [IPv6]:port)
    if [ -n "${ENDPOINT_IP:-}" ]; then
        log "🔀 覆盖 Endpoint: ${ENDPOINT_IP}"
        if grep -qi '^[[:space:]]*Endpoint[[:space:]]*=' "$WG_CONF"; then
            sed -i "s|^[[:space:]]*Endpoint[[:space:]]*=.*|Endpoint = ${ENDPOINT_IP}|g" "$WG_CONF"
        else
            sed -i "/^\[Peer\]/a Endpoint = ${ENDPOINT_IP}" "$WG_CONF"
        fi
    fi
}

# Alpine wg-quick may hard-fail on src_valid_mark; neutralize safely.
patch_wg_quick() {
    wg_quick_bin="$(command -v wg-quick || true)"
    if [ -n "$wg_quick_bin" ] && [ -f "$wg_quick_bin" ] && [ -w "$wg_quick_bin" ]; then
        # Pre-set the sysctl ourselves so semantics are preserved when possible
        sysctl -w net.ipv4.conf.all.src_valid_mark=1 >/dev/null 2>&1 || true
        if is_truthy "$ENABLE_IPV6"; then
            sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
            sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
            sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true
            sysctl -w net.ipv6.conf.default.forwarding=1 >/dev/null 2>&1 || true
        fi
        # Remove the hard-failing line from wg-quick (idempotent)
        sed -i '/src_valid_mark/d' "$wg_quick_bin" 2>/dev/null || true
    fi
}

# ==========================================
# 3. Bring up interface & fix asymmetric routes
# ==========================================
capture_pre_warp_routes() {
    # Tailscale / CGNAT v4 path before default route is hijacked
    PRE_WARP_ROUTE_V4="$(ip -4 route get 100.64.0.1 2>/dev/null | head -n 1 || true)"
    PRE_WARP_GW_V4="$(printf '%s\n' "$PRE_WARP_ROUTE_V4" | awk '{for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}}')"
    PRE_WARP_DEV_V4="$(printf '%s\n' "$PRE_WARP_ROUTE_V4" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"

    PRE_WARP_GW_V6=""
    PRE_WARP_DEV_V6=""
    if is_truthy "$ENABLE_IPV6" && command_exists ip; then
        PRE_WARP_ROUTE_V6="$(ip -6 route get fd7a:115c:a1e0::1 2>/dev/null | head -n 1 || true)"
        PRE_WARP_GW_V6="$(printf '%s\n' "$PRE_WARP_ROUTE_V6" | awk '{for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}}')"
        PRE_WARP_DEV_V6="$(printf '%s\n' "$PRE_WARP_ROUTE_V6" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
    fi

    # Host/container primary path (for inbound reply policy routing)
    ORIG_GW_V4="$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"
    ORIG_DEV_V4="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
    ORIG_IP_V4=""
    if [ -n "${ORIG_DEV_V4:-}" ]; then
        ORIG_IP_V4="$(ip -4 addr show dev "$ORIG_DEV_V4" 2>/dev/null | awk '/inet / {print $2; exit}' | cut -d/ -f1)"
    fi

    ORIG_GW_V6=""
    ORIG_DEV_V6=""
    ORIG_IP_V6=""
    if is_truthy "$ENABLE_IPV6"; then
        ORIG_GW_V6="$(ip -6 route show default 2>/dev/null | awk '{print $3; exit}')"
        ORIG_DEV_V6="$(ip -6 route show default 2>/dev/null | awk '{print $5; exit}')"
        if [ -n "${ORIG_DEV_V6:-}" ]; then
            # Prefer global unicast, skip link-local fe80::
            ORIG_IP_V6="$(ip -6 addr show dev "$ORIG_DEV_V6" scope global 2>/dev/null | awk '/inet6 / {print $2; exit}' | cut -d/ -f1)"
        fi
    fi
}

bring_up_wg() {
    log "正在启动内核级 ${WG_IFACE} 网卡..."
    # Capture stderr; do not claim success when wg-quick fails
    if ! wg_out="$(wg-quick up "$WG_IFACE" 2>&1)"; then
        printf '%s\n' "$wg_out" >&2
        warn "尝试清理半初始化接口..."
        wg-quick down "$WG_IFACE" >/dev/null 2>&1 || true
        die "wg-quick up ${WG_IFACE} 失败，请检查 NET_ADMIN / 内核 WireGuard 模块；若 IPv6 异常可设 ENABLE_IPV6=0"
    fi
}

install_policy_routes() {
    # IPv4: traffic sourced from container IP must leave via original gateway
    # (fixes published-port asymmetric routing / blackhole)
    if [ -n "${ORIG_IP_V4:-}" ] && [ -n "${ORIG_GW_V4:-}" ] && [ -n "${ORIG_DEV_V4:-}" ]; then
        log "注入 IPv4 策略路由 (from ${ORIG_IP_V4} via ${ORIG_GW_V4} dev ${ORIG_DEV_V4})"
        ip rule del from "$ORIG_IP_V4" table 128 2>/dev/null || true
        ip rule add from "$ORIG_IP_V4" table 128 priority 100 2>/dev/null || \
            warn "IPv4 ip rule 添加失败（内核可能不支持多路由表）"
        ip route replace table 128 default via "$ORIG_GW_V4" dev "$ORIG_DEV_V4" 2>/dev/null || \
            warn "IPv4 策略路由表 128 写入失败"
    fi

    # IPv6 policy routing (table 129) for container global address
    if is_truthy "$ENABLE_IPV6" && [ -n "${ORIG_IP_V6:-}" ] && [ -n "${ORIG_GW_V6:-}" ] && [ -n "${ORIG_DEV_V6:-}" ]; then
        log "注入 IPv6 策略路由 (from ${ORIG_IP_V6} via ${ORIG_GW_V6} dev ${ORIG_DEV_V6})"
        ip -6 rule del from "$ORIG_IP_V6" table 129 2>/dev/null || true
        ip -6 rule add from "$ORIG_IP_V6" table 129 priority 100 2>/dev/null || \
            warn "IPv6 ip rule 添加失败"
        ip -6 route replace table 129 default via "$ORIG_GW_V6" dev "$ORIG_DEV_V6" 2>/dev/null || \
            warn "IPv6 策略路由表 129 写入失败"
    fi

    # Restore Tailscale (and similar) return paths so mesh stays reachable
    if [ -n "${PRE_WARP_GW_V4:-}" ] && [ -n "${PRE_WARP_DEV_V4:-}" ]; then
        if ip route replace "$TAILSCALE_CIDR" via "$PRE_WARP_GW_V4" dev "$PRE_WARP_DEV_V4" 2>/dev/null; then
            log "已恢复 ${TAILSCALE_CIDR} 回程路由 via ${PRE_WARP_GW_V4} dev ${PRE_WARP_DEV_V4}"
        fi
    fi

    if is_truthy "$ENABLE_IPV6" && [ -n "${PRE_WARP_GW_V6:-}" ] && [ -n "${PRE_WARP_DEV_V6:-}" ]; then
        if ip -6 route replace "$TAILSCALE_CIDR_V6" via "$PRE_WARP_GW_V6" dev "$PRE_WARP_DEV_V6" 2>/dev/null; then
            log "已恢复 ${TAILSCALE_CIDR_V6} 回程路由 via ${PRE_WARP_GW_V6} dev ${PRE_WARP_DEV_V6}"
        fi
    fi
}

# Best-effort egress IP print. Must never block SOCKS startup for long.
# Prefer numeric Cloudflare endpoints to avoid DNS hangs on broken stacks.
show_egress_ip() {
    log "当前出口探测："

    v4_ok=0
    # 1.1.1.1 is numeric — no DNS required
    if out="$(run_with_timeout "$((TRACE_TIMEOUT + 1))" \
        curl -4 -sS --connect-timeout "$TRACE_CONNECT_TIMEOUT" -m "$TRACE_TIMEOUT" \
        https://1.1.1.1/cdn-cgi/trace 2>/dev/null || true)"; then
        ip_line="$(printf '%s\n' "$out" | grep '^ip=' || true)"
        if [ -n "$ip_line" ]; then
            log "  IPv4 ${ip_line}"
            v4_ok=1
        fi
    fi
    if [ "$v4_ok" -eq 0 ]; then
        if out="$(run_with_timeout "$((TRACE_TIMEOUT + 1))" \
            curl -4 -sS --connect-timeout "$TRACE_CONNECT_TIMEOUT" -m "$TRACE_TIMEOUT" \
            https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)"; then
            ip_line="$(printf '%s\n' "$out" | grep '^ip=' || true)"
            if [ -n "$ip_line" ]; then
                log "  IPv4 ${ip_line}"
                v4_ok=1
            fi
        fi
    fi
    if [ "$v4_ok" -eq 0 ]; then
        warn "IPv4 出口探测超时（握手延迟或节点被阻断）"
    fi

    if is_truthy "$ENABLE_IPV6"; then
        if ! iface_has_global_ipv6 "$WG_IFACE"; then
            warn "IPv6：${WG_IFACE} 无全局地址，跳过探测"
            return 0
        fi
        v6_ok=0
        # Prefer numeric IPv6 trace endpoint when possible
        if out="$(run_with_timeout "$((TRACE_TIMEOUT + 1))" \
            curl -6 -sS --connect-timeout "$TRACE_CONNECT_TIMEOUT" -m "$TRACE_TIMEOUT" \
            --resolve www.cloudflare.com:443:2606:4700::0011 \
            https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)"; then
            ip_line="$(printf '%s\n' "$out" | grep '^ip=' || true)"
            if [ -n "$ip_line" ]; then
                log "  IPv6 ${ip_line}"
                v6_ok=1
            fi
        fi
        if [ "$v6_ok" -eq 0 ]; then
            warn "IPv6 出口探测失败（隧道未就绪或目标不可达，SOCKS 仍可使用）"
        fi
    fi
}

# ==========================================
# 4. Launch microsocks (WireGuard path)
# ==========================================
start_socks() {
    # Default 0.0.0.0 keeps legacy IPv4-only listen.
    # Set BIND_ADDR=:: for IPv6 (and typically dual-stack) listen.
    set -- microsocks -i "$LISTEN_ADDR" -p "$LISTEN_PORT"

    if [ -n "${SOCKS_USER:-}" ] && [ -n "${SOCKS_PASS:-}" ]; then
        log "🔒 身份认证已开启 (User: ${SOCKS_USER})"
        set -- "$@" -u "$SOCKS_USER" -P "$SOCKS_PASS"
    else
        warn "未设置 SOCKS_USER/SOCKS_PASS，当前为公开访问模式"
    fi

    log "🚀 MicroSOCKS 监听 ${LISTEN_ADDR}:${LISTEN_PORT}"
    exec "$@"
}

# ==========================================
# 5. MASQUE path (usque)
# ==========================================
register_masque() {
    command_exists usque || die "镜像内未找到 usque，无法使用 MASQUE 模式"

    conf_dir="$(dirname "$USQUE_CONFIG")"
    mkdir -p "$conf_dir"

    if [ -f "$USQUE_CONFIG" ] && [ -s "$USQUE_CONFIG" ]; then
        log "检测到已有 MASQUE 配置: ${USQUE_CONFIG}"
        return 0
    fi

    # Drop zero-byte leftovers that confuse usque
    if [ -f "$USQUE_CONFIG" ] && [ ! -s "$USQUE_CONFIG" ]; then
        rm -f "$USQUE_CONFIG"
    fi

    log "未检测到 MASQUE 配置，正在通过 usque 注册 Cloudflare WARP 设备..."
    log "（注册完成前 SOCKS 不会监听；请勿在此阶段探测端口）"

    # Absolute path for -c; run from conf_dir so any relative side files land here.
    # -a accepts ToS non-interactively.
    set -- usque -c "$USQUE_CONFIG" register -a
    if [ -n "$USQUE_DEVICE_NAME" ]; then
        set -- "$@" -n "$USQUE_DEVICE_NAME"
    fi
    if [ -n "$WARP_JWT" ]; then
        log "使用 Zero Trust JWT 注册"
        set -- "$@" --jwt "$WARP_JWT"
    fi

    reg_log="$(mktemp /tmp/usque-register.XXXXXX 2>/dev/null || echo /tmp/usque-register.log)"
    # Capture output for diagnosis; usque often logs "Config file not found" before creating one.
    if ! (
        cd "$conf_dir" || exit 1
        "$@" >"$reg_log" 2>&1
    ); then
        warn "usque register 输出："
        cat "$reg_log" 2>/dev/null || true
        rm -f "$reg_log"
        die "usque register 失败（可能触发 Cloudflare 限流，请稍后重试并确保 volume 持久化配置）"
    fi
    # Show last lines even on success (helps CI)
    if [ -s "$reg_log" ]; then
        tail -n 15 "$reg_log" 2>/dev/null || true
    fi
    rm -f "$reg_log"

    # usque may write config.json next to CWD if -c path is awkward — normalize.
    if [ ! -f "$USQUE_CONFIG" ] || [ ! -s "$USQUE_CONFIG" ]; then
        if [ -f "$conf_dir/config.json" ] && [ -s "$conf_dir/config.json" ]; then
            mv -f "$conf_dir/config.json" "$USQUE_CONFIG"
            log "已将 config.json 规范为 ${USQUE_CONFIG}"
        fi
    fi

    [ -f "$USQUE_CONFIG" ] && [ -s "$USQUE_CONFIG" ] || \
        die "usque register 后未生成配置: $USQUE_CONFIG"

    log "MASQUE 设备注册成功 → ${USQUE_CONFIG}"
}


# Best-effort license bind (WARP+). Failures are non-fatal.
maybe_apply_warp_license() {
    [ -n "$WARP_LICENSE" ] || return 0
    command_exists usque || return 0

    log "尝试绑定 WARP+ license..."
    # usque CLI evolves; try a few known shapes, never abort the proxy.
    if usque -c "$USQUE_CONFIG" license "$WARP_LICENSE" >/dev/null 2>&1; then
        log "WARP+ license 已应用 (license 子命令)"
        return 0
    fi
    if usque -c "$USQUE_CONFIG" account license "$WARP_LICENSE" >/dev/null 2>&1; then
        log "WARP+ license 已应用 (account license)"
        return 0
    fi
    # Some builds expose --license on register/enroll only; document for re-register.
    warn "当前 usque 构建可能不支持运行时 license 绑定；若需 WARP+ 请查阅 usque 文档或重新注册"
}

start_masque_socks() {
    command_exists usque || die "镜像内未找到 usque"

    proxy_mode="$(normalize_masque_proxy_mode "$MASQUE_PROXY_MODE")"
    log "协议: MASQUE (usque)  代理模式: ${proxy_mode}"

    # Soft-cap Go heap on small hosts (no effect if runtime ignores it)
    if [ -n "${GOMEMLIMIT:-}" ]; then
        export GOMEMLIMIT
        log "GOMEMLIMIT=${GOMEMLIMIT}"
    fi

    # Global -c must precede subcommand
    set -- usque -c "$USQUE_CONFIG" "$proxy_mode" -b "$LISTEN_ADDR" -p "$LISTEN_PORT"

    if [ -n "${SOCKS_USER:-}" ] && [ -n "${SOCKS_PASS:-}" ]; then
        log "🔒 身份认证已开启 (User: ${SOCKS_USER})"
        set -- "$@" -u "$SOCKS_USER" -w "$SOCKS_PASS"
    else
        warn "未设置 SOCKS_USER/SOCKS_PASS，当前为公开访问模式"
    fi

    # HTTP/2 (TCP:443) fallback — only on full socks / modes that support it.
    # L4 modes currently do not support --http2 (usque limitation).
    if is_truthy "$MASQUE_HTTP2"; then
        if [ "$proxy_mode" = "l4-socks" ]; then
            warn "MASQUE_HTTP2=1 但 l4-socks 不支持 --http2；请改 MASQUE_PROXY_MODE=socks，或关闭 HTTP2"
        else
            log "启用 MASQUE HTTP/2 (TCP) 回退"
            set -- "$@" --http2
        fi
    fi

    # SNI override (full socks); L4 rejects custom SNI on CF side
    if [ -n "$MASQUE_SNI" ]; then
        if [ "$proxy_mode" = "l4-socks" ]; then
            warn "MASQUE_SNI 在 l4-socks 下无效，已忽略"
        else
            log "MASQUE SNI=${MASQUE_SNI}"
            set -- "$@" -s "$MASQUE_SNI"
        fi
    fi

    if [ -n "$MASQUE_MTU" ]; then
        if [ "$proxy_mode" = "l4-socks" ]; then
            warn "MASQUE_MTU 在 l4-socks 下无效，已忽略"
        else
            set -- "$@" -m "$MASQUE_MTU"
        fi
    fi

    # Optional IPv4/IPv6 tunnel toggles via usque flags when full socks
    if [ "$proxy_mode" = "socks" ]; then
        if ! is_truthy "$ENABLE_IPV6"; then
            # usque socks: -S often means IPv6 off / family select — keep portable:
            # Prefer documented no-tunnel-ipv6 style if present; otherwise leave default.
            if usque socks --help 2>&1 | grep -q 'no-tunnel-ipv6'; then
                set -- "$@" --no-tunnel-ipv6
            fi
        fi
    fi

    log "🚀 usque ${proxy_mode} 监听 ${LISTEN_ADDR}:${LISTEN_PORT}"
    if is_truthy "$MASQUE_HTTP2" && [ "$proxy_mode" = "socks" ]; then
        log "   流量经 Cloudflare MASQUE (HTTP/2 TCP :443)"
    else
        log "   流量经 Cloudflare MASQUE (HTTP/3 QUIC :443)"
    fi
    exec "$@"

}

run_wireguard_path() {
    log "协议: WireGuard (内核 wg0) — 默认轻量路径"

    mkdir -p "$WG_DIR"

    if [ ! -f "$WG_CONF" ]; then
        register_warp
    else
        log "检测到已有持久化配置，跳过注册"
    fi

    sanitize_config
    patch_wg_quick
    capture_pre_warp_routes
    bring_up_wg
    install_policy_routes

    # CRITICAL: bring up SOCKS before any optional network probes.
    show_egress_ip &
    start_socks
}

run_masque_path() {
    log "协议: MASQUE — 用户态 usque (兼容抗封锁 / UDP 被 QoS 场景)"
    warn "MASQUE 为用户态 QUIC，内存远高于内核 WireGuard（建议 GOMEMLIMIT，默认可 512MiB）"

    conf_dir="$(dirname "$USQUE_CONFIG")"
    mkdir -p "$conf_dir"

    register_masque
    maybe_apply_warp_license
    start_masque_socks
}

# ==========================================
# Main
# ==========================================
main() {
    proto="$(normalize_tunnel_protocol "$TUNNEL_PROTOCOL")"
    log "TUNNEL_PROTOCOL=${proto}"

    case "$proto" in
        wireguard) run_wireguard_path ;;
        masque)    run_masque_path ;;
        *)         die "内部错误: 未处理的协议 $proto" ;;
    esac
}

main "$@"
