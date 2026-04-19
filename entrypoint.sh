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
log_warn() { echo -e "${C_WRN}[WARN] $1${C_RST}"; [ -n "$2" ] && echo -e "${C_WRN}[WARN] $2${C_RST}"; }
log_err()  { echo -e "${C_ERR}[ERROR] $1${C_RST}"; [ -n "$2" ] && echo -e "${C_ERR}[ERROR] $2${C_RST}"; }
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

WG_CONF="/etc/wireguard/wg0.conf"
mkdir -p /etc/wireguard

# 读取环境变量监听配置
LISTEN_ADDR=${BIND_ADDR:-"0.0.0.0"}
LISTEN_PORT=${BIND_PORT:-"1080"}

# ==========================================
# 1. 账号全自动申请与配置生成 (阅后即焚)
# ==========================================
if [ ! -f "$WG_CONF" ]; then
    log_step "未检测到配置，正在全自动初始化 Cloudflare WARP..." "No configuration detected, auto-initializing Cloudflare WARP..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) WGCF_ARCH="amd64" ;;
        aarch64) WGCF_ARCH="arm64" ;;
        *) log_err "不支持的架构: $ARCH" "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    WGCF_VER=$(curl -sL https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/')
    log_info "检测到最新 wgcf 版本: v${WGCF_VER}" "Detected latest wgcf version: v${WGCF_VER}"
    
    wget --timeout=15 -qO wgcf "$(build_wgcf_download_url "$WGCF_VER" "$WGCF_ARCH")"
    chmod +x wgcf

    log_step "正在向 CF 注册设备..." "Registering device with CF..."
    ./wgcf register --accept-tos > /dev/null
    log_step "正在生成 WireGuard 配置文件..." "Generating WireGuard configuration file..."
    ./wgcf generate > /dev/null

    mv wgcf-profile.conf "$WG_CONF"
    rm -f wgcf wgcf-account.toml
    log_info "节点配置生成成功！" "Node configuration generated successfully!"
else
    log_info "检测到已有持久化配置，跳过注册。" "Persistent config detected, skipping registration."
fi

# ==========================================
# 2. 强力洗白与内核兼容性处理 (防正则误杀版)
# ==========================================
IPV4_ADDR=$(grep '^Address' "$WG_CONF" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | head -n 1)

sed -i '/^Address/d' "$WG_CONF"
sed -i '/^AllowedIPs/d' "$WG_CONF"
sed -i '/^DNS.*/d' "$WG_CONF"

if [ -n "$IPV4_ADDR" ]; then
    sed -i "/\[Interface\]/a Address = $IPV4_ADDR" "$WG_CONF"
fi
sed -i "/\[Peer\]/a AllowedIPs = 0.0.0.0\/0" "$WG_CONF"

sed -i '/src_valid_mark/d' /usr/bin/wg-quick

if ! grep -q "PersistentKeepalive" "$WG_CONF"; then
    sed -i '/\[Peer\]/a PersistentKeepalive = 15' "$WG_CONF"
else
    sed -i 's/PersistentKeepalive.*/PersistentKeepalive = 15/g' "$WG_CONF"
fi

if [ -n "$ENDPOINT_IP" ]; then
    log_warn "检测到自定义 Endpoint IP，覆盖默认节点: $ENDPOINT_IP" "Custom Endpoint IP detected, overriding default node: $ENDPOINT_IP"
    sed -i "s/^Endpoint.*/Endpoint = $ENDPOINT_IP/g" "$WG_CONF"
fi

# ==========================================
# 3. 运行模式智能检测 (KVM 内核态 vs LXC 用户态降级)
# ==========================================
log_step "正在检测宿主机网络特权环境..." "Detecting host network privileges..."

USE_FALLBACK=0
# 核心检测逻辑：尝试创建 wireguard 虚拟网卡
if ip link add dev wg_test type wireguard 2>/dev/null; then
    ip link del dev wg_test
    log_info "特权检测通过！将使用原生内核态 wg0 (极致低内存模式)。" "Privilege check passed! Native kernel wg0 will be used (Ultra-low memory mode)."
else
    log_warn "未检测到 TUN/特权网络权限 (常见于 LXC/OVZ VPS)。" "No TUN/Privilege detected (Common in LXC/OVZ VPS)."
    log_warn "正在自动回退至用户态网络栈 (WireProxy 模式)，内存占用将略微上升。" "Auto-falling back to user-space network stack (WireProxy mode), memory usage will slightly increase."
    USE_FALLBACK=1
fi

# ==========================================
# 4. 路由拉起与代理引擎启动
# ==========================================
if [ "$USE_FALLBACK" = "0" ]; then
    # ----------------------------------------
    # 模式 A: 原生内核级 MicroSOCKS (KVM 环境)
    # ----------------------------------------
    PRE_WARP_ROUTE=$(ip route get 100.64.0.1 2>/dev/null | head -n 1 || true)
    PRE_WARP_GW=$(printf '%s\n' "$PRE_WARP_ROUTE" | awk '{for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1)}')
    PRE_WARP_DEV=$(printf '%s\n' "$PRE_WARP_ROUTE" | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") print $(i + 1)}')

    log_step "启动 Linux 内核级 wg0 网卡..." "Starting Linux kernel wg0 interface..."
    wg-quick up wg0 > /dev/null 2>&1

    TAILSCALE_CIDR=${TAILSCALE_CIDR:-"100.64.0.0/10"}
    if [ -n "$PRE_WARP_GW" ] && [ -n "$PRE_WARP_DEV" ]; then
        if ip route replace "$TAILSCALE_CIDR" via "$PRE_WARP_GW" dev "$PRE_WARP_DEV" > /dev/null 2>&1; then
            log_info "已恢复 Tailscale 路由: via ${PRE_WARP_GW} dev ${PRE_WARP_DEV}" "Tailscale route restored."
        fi
    fi

    log_info "当前出口 IP (内核模式):" "Current outbound IP (Kernel mode):"
    curl -s -m 5 https://1.1.1.1/cdn-cgi/trace | grep ip= || log_warn "获取超时" "Fetch timeout"

    if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASS" ]; then
        log_info "身份认证已开启 (User: $SOCKS_USER)" "Authentication enabled (User: $SOCKS_USER)"
        log_step "MicroSOCKS 引擎已启动，监听 ${LISTEN_ADDR}:${LISTEN_PORT}" "MicroSOCKS engine started, listening on ${LISTEN_ADDR}:${LISTEN_PORT}"
        exec microsocks -i "$LISTEN_ADDR" -p "$LISTEN_PORT" -u "$SOCKS_USER" -P "$SOCKS_PASS"
    else
        log_warn "未设置密码，当前为公开访问模式" "No password set, public access mode"
        log_step "MicroSOCKS 引擎已启动，监听 ${LISTEN_ADDR}:${LISTEN_PORT}" "MicroSOCKS engine started, listening on ${LISTEN_ADDR}:${LISTEN_PORT}"
        exec microsocks -i "$LISTEN_ADDR" -p "$LISTEN_PORT"
    fi

else
    # ----------------------------------------
    # 模式 B: 用户态 WireProxy 降级 (LXC/OVZ 环境)
    # ----------------------------------------
    # 提取现有 wg0.conf 参数，无缝转换为 wireproxy 格式
    # 【修复】使用精准正则截取，防止 Base64 密钥末尾的 '=' 填充符被误删
    WG_PRIV_KEY=$(grep '^PrivateKey' "$WG_CONF" | sed 's/^[^=]*= *//')
    WG_PUB_KEY=$(grep '^PublicKey' "$WG_CONF" | sed 's/^[^=]*= *//')
    WG_ENDPOINT=$(grep '^Endpoint' "$WG_CONF" | sed 's/^[^=]*= *//')
    
    WP_CONF="/etc/wireguard/wireproxy.conf"
    cat <<EOF > "$WP_CONF"
[Interface]
Address = $IPV4_ADDR
PrivateKey = $WG_PRIV_KEY
MTU = 1280

[Peer]
PublicKey = $WG_PUB_KEY
Endpoint = $WG_ENDPOINT[Socks5]
BindAddress = ${LISTEN_ADDR}:${LISTEN_PORT}
EOF

    if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASS" ]; then
        sed -i "/\[Socks5\]/a Username = $SOCKS_USER\nPassword = $SOCKS_PASS" "$WP_CONF"
        log_info "身份认证已开启 (User: $SOCKS_USER)" "Authentication enabled (User: $SOCKS_USER)"
    else
        log_warn "未设置密码，当前为公开访问模式" "No password set, public access mode"
    fi

    log_step "WireProxy 引擎已启动，监听 ${LISTEN_ADDR}:${LISTEN_PORT}" "WireProxy engine started, listening on ${LISTEN_ADDR}:${LISTEN_PORT}"
    # 使用 exec 直接拉起 wireproxy，完全接管 PID 1
    exec wireproxy -c "$WP_CONF"
fi
