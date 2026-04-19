#!/bin/sh
set -e

# ==========================================
# 0. DEBUG 模式与双语日志系统初始化
# ==========================================
if [ "${DEBUG:-0}" = "1" ]; then
    set -x
fi

C_RST="\033[0m"
C_INF="\033[32m"
C_WRN="\033[33m"
C_ERR="\033[31m"
C_STP="\033[36m"

log_info() { echo -e "${C_INF}[INFO] $1${C_RST}"; [ -n "$2" ] && echo -e "${C_INF}[INFO] $2${C_RST}"; }
log_warn() { echo -e "${C_WRN}[WARN] $1${C_RST}";[ -n "$2" ] && echo -e "${C_WRN}[WARN] $2${C_RST}"; }
log_err()  { echo -e "${C_ERR}[ERROR] $1${C_RST}";[ -n "$2" ] && echo -e "${C_ERR}[ERROR] $2${C_RST}"; }
log_step() { echo -e "${C_STP}[STEP] $1${C_RST}"; [ -n "$2" ] && echo -e "${C_STP}[STEP] $2${C_RST}"; }

build_wgcf_download_url() {
    WGCF_VER=$1
    WGCF_ARCH=$2
    RAW_URL="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VER}/wgcf_${WGCF_VER}_linux_${WGCF_ARCH}"
    if [ -n "${GH_PROXY:-}" ]; then
        echo "${GH_PROXY%/}/${RAW_URL}"
        return 0
    fi
    echo "$RAW_URL"
}

if [ "${MICROWARP_TEST_MODE:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

# ==========================================
# 1. 核心业务函数定义 (配置生成与规范化)
# ==========================================
WG_CONF="/etc/wireguard/wg0.conf"
WP_CONF="/etc/wireguard/wireproxy.conf"
mkdir -p /etc/wireguard

LISTEN_ADDR=${BIND_ADDR:-"0.0.0.0"}
LISTEN_PORT=${BIND_PORT:-"1080"}
AUTO_RENEW_DAYS=${AUTO_RENEW_DAYS:-7}
AUTO_RENEW_SECONDS=${AUTO_RENEW_SECONDS:-$((AUTO_RENEW_DAYS * 86400))}

ensure_wgcf_installed() {
    if [ ! -x "/usr/local/bin/wgcf" ]; then
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64) WGCF_ARCH="amd64" ;;
            aarch64) WGCF_ARCH="arm64" ;;
            *) log_err "不支持的架构: $ARCH" "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        WGCF_VER=$(curl -sL https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/')
        log_info "正在下载 wgcf v${WGCF_VER}..." "Downloading wgcf v${WGCF_VER}..."
        wget --timeout=15 -qO /usr/local/bin/wgcf "$(build_wgcf_download_url "$WGCF_VER" "$WGCF_ARCH")"
        chmod +x /usr/local/bin/wgcf
    fi
}

sanitize_wg_conf() {
    local conf_file=$1
    IPV4_ADDR=$(grep '^Address' "$conf_file" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | head -n 1)

    sed -i -e '/^Address/d' -e '/^AllowedIPs/d' -e '/^DNS.*/d' "$conf_file"

    if [ -n "$IPV4_ADDR" ]; then
        sed -i "/\[Interface\]/a Address = $IPV4_ADDR" "$conf_file"
    else
        log_err "无法提取 IPv4 地址！配置可能异常。" "Failed to extract IPv4 address!"
    fi
    
    sed -i "/\[Peer\]/a AllowedIPs = 0.0.0.0\/0" "$conf_file"

    if ! grep -q "PersistentKeepalive" "$conf_file"; then
        sed -i '/\[Peer\]/a PersistentKeepalive = 15' "$conf_file"
    else
        sed -i 's/PersistentKeepalive.*/PersistentKeepalive = 15/g' "$conf_file"
    fi

    if [ -n "$ENDPOINT_IP" ]; then
        sed -i "s/^Endpoint.*/Endpoint = $ENDPOINT_IP/g" "$conf_file"
    fi
}

generate_new_warp() {
    ensure_wgcf_installed
    log_step "正在向 CF 申请新设备..." "Registering new device with CF..."
    
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR"
    
    # 1. 应对 CF 限流的注册重试机制 (最多 5 次)
    RETRY=0
    MAX_RETRY=5
    while[ ! -f "wgcf-account.toml" ]; do
        wgcf register --accept-tos > /dev/null 2>&1 || true
        if [ ! -f "wgcf-account.toml" ]; then
            RETRY=$((RETRY+1))
            if [ "$RETRY" -gt "$MAX_RETRY" ]; then
                log_err "账号注册失败已达 $MAX_RETRY 次！放弃本次申请。" "Registration failed $MAX_RETRY times, aborting."
                cd /app && rm -rf "$WORK_DIR"
                return 1
            fi
            log_warn "账号注册被拦截 (可能触发风控)，等待 10s 后重试 (第 $RETRY/$MAX_RETRY 次)..." "Registration limited, retrying in 10s..."
            sleep 10
        fi
    done
    
    # 2. 应对生成失败的配置重试机制 (最多 5 次)
    RETRY_GEN=0
    while[ ! -f "wgcf-profile.conf" ]; do
        wgcf generate > /dev/null 2>&1 || true
        if [ ! -f "wgcf-profile.conf" ]; then
            RETRY_GEN=$((RETRY_GEN+1))
            if [ "$RETRY_GEN" -gt "$MAX_RETRY" ]; then
                log_err "配置生成失败已达 $MAX_RETRY 次！放弃本次申请。" "Profile generation failed $MAX_RETRY times, aborting."
                cd /app && rm -rf "$WORK_DIR"
                return 1
            fi
            log_warn "配置提取失败，等待 5s 后重试 (第 $RETRY_GEN/$MAX_RETRY 次)..." "Profile extraction failed, retrying in 5s..."
            sleep 5
        fi
    done
    
    mv wgcf-profile.conf "$WG_CONF"
    cd /app && rm -rf "$WORK_DIR"
    
    sanitize_wg_conf "$WG_CONF"
    log_info "节点配置生成/更新成功！" "Node config generated/updated successfully!"
    return 0
}

generate_wireproxy_conf() {
    WG_PRIV_KEY=$(grep '^PrivateKey' "$WG_CONF" | sed 's/^[^=]*= *//')
    WG_PUB_KEY=$(grep '^PublicKey' "$WG_CONF" | sed 's/^[^=]*= *//')
    WG_ENDPOINT=$(grep '^Endpoint' "$WG_CONF" | sed 's/^[^=]*= *//')
    IPV4_ADDR=$(grep '^Address' "$WG_CONF" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | head -n 1)

    cat <<EOF > "$WP_CONF"
[Interface]
Address = $IPV4_ADDR
PrivateKey = $WG_PRIV_KEY
MTU = 1280

[Peer]
PublicKey = $WG_PUB_KEY
Endpoint = $WG_ENDPOINT

[Socks5]
BindAddress = ${LISTEN_ADDR}:${LISTEN_PORT}
EOF
    if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASS" ]; then
        sed -i "/\[Socks5\]/a Username = $SOCKS_USER\nPassword = $SOCKS_PASS" "$WP_CONF"
    fi
}

# ==========================================
# 2. 初始化环境与特权检测
# ==========================================
if [ ! -f "$WG_CONF" ]; then
    log_step "未检测到配置，自动初始化 WARP..." "No configuration detected, initializing WARP..."
    if ! generate_new_warp; then
        log_err "首次初始化彻底失败！容器将停止运行以避免触发无限死循环滥用。" "Initial setup completely failed! Container stopping."
        exit 1
    fi
else
    log_info "检测到已有持久化配置，跳过注册。" "Persistent config detected, skipping registration."
    if [ "$AUTO_RENEW_SECONDS" -gt 0 ]; then ensure_wgcf_installed; fi
fi

log_step "正在检测宿主机网络特权环境..." "Detecting host network privileges..."
USE_FALLBACK=0
if ip link add dev wg_test type wireguard 2>/dev/null; then
    ip link del dev wg_test
    log_info "特权检测通过！将使用原生内核态 wg0 (极致低内存模式)。" "Privilege check passed! Native kernel wg0 will be used."
else
    log_warn "未检测到 TUN/特权网络权限 (常见于 LXC/OVZ VPS)。" "No TUN/Privilege detected (Common in LXC/OVZ VPS)."
    log_warn "正在自动回退至用户态网络栈 (WireProxy 模式)。" "Auto-falling back to user-space network stack (WireProxy mode)."
    USE_FALLBACK=1
fi

# ==========================================
# 3. [防限流大杀器] 后台零停机自动热重载守护进程
# ==========================================
if [ "$AUTO_RENEW_SECONDS" -gt 0 ]; then
    log_info "防限流热重载已开启 (后台循环刷新间隔: $AUTO_RENEW_SECONDS 秒)" "Auto-renew enabled (Interval: $AUTO_RENEW_SECONDS seconds)"
    (
        while true; do
            sleep "$AUTO_RENEW_SECONDS"
            log_step "触发后台定期更换账号..." "Triggering background auto-renew..."
            
            if generate_new_warp; then
                if [ "$USE_FALLBACK" = "0" ]; then
                    WG_PRIV_KEY=$(grep '^PrivateKey' "$WG_CONF" | sed 's/^[^=]*= *//')
                    WG_PUB_KEY=$(grep '^PublicKey' "$WG_CONF" | sed 's/^[^=]*= *//')
                    WG_ENDPOINT=$(grep '^Endpoint' "$WG_CONF" | sed 's/^[^=]*= *//')
                    
                    for peer in $(wg show wg0 peers 2>/dev/null); do wg set wg0 peer "$peer" remove; done
                    
                    TMP_KEY=$(mktemp)
                    echo "$WG_PRIV_KEY" > "$TMP_KEY"
                    wg set wg0 private-key "$TMP_KEY" peer "$WG_PUB_KEY" endpoint "$WG_ENDPOINT" allowed-ips 0.0.0.0/0 persistent-keepalive 15
                    rm -f "$TMP_KEY"
                    
                    log_info "内核网卡热重载完成，代理服务 0 中断。" "Kernel interface hot-reloaded, zero downtime."
                else
                    generate_wireproxy_conf
                    killall -TERM wireproxy 2>/dev/null || true
                    log_info "WireProxy 配置已刷新并重启。" "WireProxy config reloaded and restarted."
                fi
            else
                log_warn "后台热重载失败，跳过本次配置应用，继续使用旧账号。" "Background hot-reload failed, retaining old config."
            fi
        done
    ) &
fi

# ==========================================
# 4. 路由拉起与代理引擎启动
# ==========================================
if [ "$USE_FALLBACK" = "0" ]; then
    sed -i '/src_valid_mark/d' /usr/bin/wg-quick
    PRE_WARP_ROUTE=$(ip route get 100.64.0.1 2>/dev/null | head -n 1 || true)
    PRE_WARP_GW=$(printf '%s\n' "$PRE_WARP_ROUTE" | awk '{for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1)}')
    PRE_WARP_DEV=$(printf '%s\n' "$PRE_WARP_ROUTE" | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") print $(i + 1)}')

    log_step "启动 Linux 内核级 wg0 网卡..." "Starting Linux kernel wg0 interface..."
    wg-quick up wg0 > /dev/null 2>&1
    
    # 【新增缓冲】等待底层的 UDP 隧道握手连通
    sleep 3

    TAILSCALE_CIDR=${TAILSCALE_CIDR:-"100.64.0.0/10"}
    if [ -n "$PRE_WARP_GW" ] && [ -n "$PRE_WARP_DEV" ]; then
        ip route replace "$TAILSCALE_CIDR" via "$PRE_WARP_GW" dev "$PRE_WARP_DEV" > /dev/null 2>&1 && \
        log_info "已恢复 Tailscale 路由: via ${PRE_WARP_GW} dev ${PRE_WARP_DEV}" "Tailscale route restored."
    fi

    log_info "当前出口 IP (内核模式):" "Current outbound IP (Kernel mode):"
    curl -s -m 5 https://1.1.1.1/cdn-cgi/trace | grep ip= || log_warn "获取超时，底层隧道可能遭遇延迟" "Fetch timeout"

    if [ -n "$SOCKS_USER" ] &&[ -n "$SOCKS_PASS" ]; then
        log_info "身份认证已开启 (User: $SOCKS_USER)" "Authentication enabled."
        log_step "MicroSOCKS 引擎已启动，监听 ${LISTEN_ADDR}:${LISTEN_PORT}" "MicroSOCKS engine started."
        exec microsocks -i "$LISTEN_ADDR" -p "$LISTEN_PORT" -u "$SOCKS_USER" -P "$SOCKS_PASS"
    else
        log_warn "未设置密码，当前为公开访问模式" "No password set, public access mode."
        log_step "MicroSOCKS 引擎已启动，监听 ${LISTEN_ADDR}:${LISTEN_PORT}" "MicroSOCKS engine started."
        exec microsocks -i "$LISTEN_ADDR" -p "$LISTEN_PORT"
    fi

else
    generate_wireproxy_conf
    
    if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASS" ]; then
        log_info "身份认证已开启 (User: $SOCKS_USER)" "Authentication enabled."
    else
        log_warn "未设置密码，当前为公开访问模式" "No password set, public access mode."
    fi

    log_step "WireProxy 引擎已启动，监听 ${LISTEN_ADDR}:${LISTEN_PORT}" "WireProxy engine started."
    
    trap 'kill $(jobs -p) 2>/dev/null; exit 0' TERM INT
    
    while true; do
        if [ "${DEBUG:-0}" = "1" ]; then
            wireproxy -c "$WP_CONF" &
        else
            wireproxy --silent -c "$WP_CONF" &
        fi
        wait $! || true
        sleep 1
    done
fi
