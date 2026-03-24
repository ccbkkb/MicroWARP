#!/bin/sh
set -e

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

# ==========================================
# 1. 账号全自动申请与配置生成 (阅后即焚)
# ==========================================
if [ ! -f "$WG_CONF" ]; then
    echo "==> [MicroWARP] 未检测到配置，正在全自动初始化 Cloudflare WARP..."

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) WGCF_ARCH="amd64" ;;
        aarch64) WGCF_ARCH="arm64" ;;
        *) echo "==> [ERROR] 不支持的架构: $ARCH"; exit 1 ;;
    esac

    WGCF_VER=$(curl -sL https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/')
    echo "==> [MicroWARP] 检测到最新 wgcf 版本: v${WGCF_VER}"
    wget --timeout=15 -qO wgcf "$(build_wgcf_download_url "$WGCF_VER" "$WGCF_ARCH")"
    chmod +x wgcf

    echo "==> [MicroWARP] 正在向 CF 注册设备..."
    ./wgcf register --accept-tos > /dev/null

    echo "==> [MicroWARP] 正在生成 WireGuard 配置文件..."
    ./wgcf generate > /dev/null

    mv wgcf-profile.conf "$WG_CONF"

    # 【核心安全】阅后即焚：删除注册工具和生成的账号明文文件
    rm -f wgcf wgcf-account.toml
    echo "==> [MicroWARP] 节点配置生成成功！"
else
    echo "==> [MicroWARP] 检测到已有持久化配置，跳过注册。"
fi

# ==========================================
# 2. 强力洗白与内核兼容性处理 (防正则误杀版)
# ==========================================

# 1. 智能提取出纯 IPv4 地址 (防止 wgcf v2.2.30 将双栈 IP 写在同一行导致误杀)
IPV4_ADDR=$(grep '^Address' "$WG_CONF" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | head -n 1)

# 2. 物理删除所有原始的 Address, AllowedIPs, DNS，防止 RTNETLINK 崩溃或 DNS 死锁
sed -i '/^Address/d' "$WG_CONF"
sed -i '/^AllowedIPs/d' "$WG_CONF"
sed -i '/^DNS.*/d' "$WG_CONF"

# 3. 重建最纯净的 IPv4 路由规则
if [ -n "$IPV4_ADDR" ]; then
    sed -i "/\[Interface\]/a Address = $IPV4_ADDR" "$WG_CONF"
fi
sed -i "/\[Peer\]/a AllowedIPs = 0.0.0.0\/0" "$WG_CONF"

# 删除 Alpine 系统自带 wg-quick 中不兼容的路由标记
sed -i '/src_valid_mark/d' /usr/bin/wg-quick

# 【新增：抗断流绝杀】强制注入 15 秒 UDP 心跳保活，对抗运营商 QoS 丢包
if ! grep -q "PersistentKeepalive" "$WG_CONF"; then
    sed -i '/\[Peer\]/a PersistentKeepalive = 15' "$WG_CONF"
else
    sed -i 's/PersistentKeepalive.*/PersistentKeepalive = 15/g' "$WG_CONF"
fi

# 【新增：防阻断绝杀】针对 HK/US 强校验机房，注入自定义优选 Endpoint IP
if [ -n "$ENDPOINT_IP" ]; then
    echo "==> [MicroWARP] 🔀 检测到自定义 Endpoint IP，正在覆盖默认节点: $ENDPOINT_IP"
    sed -i "s/^Endpoint.*/Endpoint = $ENDPOINT_IP/g" "$WG_CONF"
fi

# ==========================================
# 3. 拉起内核网卡
# ==========================================
echo "==> [MicroWARP] 正在启动 Linux 内核级 wg0 网卡..."
wg-quick up wg0 > /dev/null 2>&1

echo "==> [MicroWARP] 当前出口 IP 已成功变更为："
# 获取最新的 CF 溯源 IP (加入 5 秒强制超时，完美替代有缺陷的 & 后台执行)
curl -s -m 5 https://1.1.1.1/cdn-cgi/trace | grep ip= || echo "⚠️ 获取超时 (可能是底层握手延迟或节点被强阻断)"

# ==========================================
# 4. 启动 C 语言 SOCKS5 代理服务 (带高级参数绑定)
# ==========================================
# 读取环境变量，如果未设置则使用默认值 0.0.0.0 和 1080
LISTEN_ADDR=${BIND_ADDR:-"0.0.0.0"}
LISTEN_PORT=${BIND_PORT:-"1080"}

if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASS" ]; then
    echo "==> [MicroWARP] 🔒 身份认证已开启 (User: $SOCKS_USER)"
    echo "==> [MicroWARP] 🚀 MicroSOCKS 引擎已启动，正在监听 ${LISTEN_ADDR}:${LISTEN_PORT}"
    # 使用 exec 接管进程，实现 Zero-Overhead 的底层进程控制
    exec microsocks -i "$LISTEN_ADDR" -p "$LISTEN_PORT" -u "$SOCKS_USER" -P "$SOCKS_PASS"
else
    echo "==> [MicroWARP] ⚠️ 未设置密码，当前为公开访问模式"
    echo "==>[MicroWARP] 🚀 MicroSOCKS 引擎已启动，正在监听 ${LISTEN_ADDR}:${LISTEN_PORT}"
    exec microsocks -i "$LISTEN_ADDR" -p "$LISTEN_PORT"
fi
