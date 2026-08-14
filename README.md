# MicroWARP 🚀

[![Docker Pulls](https://img.shields.io/badge/docker-ready-blue.svg)](https://github.com/ccbkkb/MicroWARP/packages)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> *请严格遵守您所在国家和地区的法律法规。任何因违法违规使用本项目而引发的法律纠纷或后果，均与本项目及作者无关。*
>
> *Please strictly comply with the laws and regulations of your country and region. Any legal disputes or consequences arising from illegal use of this project have nothing to do with this project and its authors.*

[English](#english) | [中文说明](#chinese)

### 📊 Performance Comparison

Here is a real-world performance test on a 1C1G (1 vCPU, 1GB RAM) VPS, comparing MicroWARP with the widely used `caomingjun/warp`.

以下是在 1C1G 服务器上的真实运行数据截图对比：

| Metric (指标) | `caomingjun/warp` (Official Daemon) | 🚀 `MicroWARP` (Pure C + Kernel approach) | Improvement (提升) |
| :--- | :--- | :--- | :--- |
| **Image Size**<br>(Docker 镜像体积) | 201 MB | **~15–20 MB** *(含可选 usque)* | 📉 **~-90%** |
| **RAM Usage**<br>(日常内存占用) | ~150 MB | **~800 KiB** WG 默认<br>*(MASQUE 为用户态，更高)* | 📉 **-99.4%** *(WG)* |
| **CPU Overhead**<br>(高并发 CPU 损耗) | High (Userspace App) | **~0.25%** (Kernel Space) | ⚡ **Near Zero** |
| **Core Engine**<br>(底层核心引擎) | Cloudflare `warp-cli` (Rust) | Linux `wg0` + Pure C `microsocks` *(default)*<br>Optional **MASQUE** via `usque` | 🛠️ **Minimalist + Compatible** |
| **IP Stack**<br>(协议栈) | Mostly IPv4-focused | **Dual-stack IPv4 + IPv6** | 🌐 **Native** |
| **Tunnel protocol**<br>(隧道协议) | WireGuard / MASQUE (daemon) | **WireGuard kernel (default)** or **MASQUE userspace** | 🔀 **Selectable** |



> **🔥 Real `docker stats` output:**
> ```text
> CONTAINER ID   NAME       CPU %     MEM USAGE / LIMIT     MEM %     NET I/O           BLOCK I/O
> 2fa58f84c517   warp       0.25%     800KiB / 967.4MiB     0.08%     48.8MB / 39.1MB   238kB / 36.9kB
> ```
> *Yes, you read that right. It processed ~90MB of traffic using only **800 KB** of RAM!* *是的，你没看错。它仅使用了 **800 KB** 的内存，就处理了约 90 MB 的流量！*

---

<a name="english"></a>
## 🇬🇧 English

A minimalist, high-performance Cloudflare WARP SOCKS5 proxy in Docker.
Designed as a lightweight drop-in replacement for standard WARP proxy images (e.g., `caomingjun/warp`).

### 🌟 Why MicroWARP?

Many popular WARP Docker images rely on the official Cloudflare `warp-cli` daemon. This approach typically results in significant memory usage (often **150MB+**) and potential process overhead under high concurrency.

**MicroWARP** is built differently:
1. **Kernel-Level WireGuard (default)**: Instead of the userspace client, it leverages the native Linux `wg0` interface for near-zero CPU overhead.
2. **Optional MASQUE**: Set `TUNNEL_PROTOCOL=masque` to use [usque](https://github.com/Diniboy1123/usque) (CONNECT-IP over HTTP/3). Better when WireGuard UDP is QoS'd/blocked; traffic looks like HTTPS on **UDP/TCP 443**.
3. **MicroSOCKS Engine**: WireGuard path uses pure C `microsocks`; MASQUE path uses `usque` `l4-socks` / `socks`.
4. **Minimal Memory Footprint (WireGuard)**: Runs smoothly on **< 5MB RAM** (often ~800KB). MASQUE is userspace QUIC and needs far more RAM (see below).
5. **Native Dual-Stack**: Full **IPv4 + IPv6** WARP routing on the WireGuard path (`AllowedIPs = 0.0.0.0/0, ::/0`), with IPv6 policy routing for inbound reply paths.
6. **Seamless Tailscale Integration**: On the WireGuard path, restores asymmetric routing for IPv4 (`100.64.0.0/10`) and IPv6 (`fd7a:115c:a1e0::/48`).
7. **Multi-Arch**: Native support for `amd64` and `arm64` (plus `armv7` registration path).


### 🎯 Use Cases
*   **API Routing**: Route crawlers or AI API gateways (like Grok, ChatGPT) through MicroWARP to leverage high-trust Cloudflare IPs.
*   **Outbound Privacy**: Obfuscate your server's real IP by using WARP as your default egress network to prevent direct traceback.
*   **Sidecar Proxy**: Perfectly designed as an ultra-lightweight Docker Sidecar network gateway.
*   **IPv6 Egress**: Reach IPv6-only destinations via Cloudflare WARP when the host has limited or no native IPv6 peering.

### 📦 Quick Start

Map port `1080` and grant `NET_ADMIN` privileges. Create a `docker-compose.yml`:

```yaml
services:
  microwarp:
    image: ghcr.io/ccbkkb/microwarp:latest
    container_name: microwarp
    restart: always
    ports:
      - "127.0.0.1:1080:1080"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv6.conf.default.disable_ipv6=0
      - net.ipv6.conf.all.forwarding=1
    volumes:
      - warp-data:/etc/wireguard

volumes:
  warp-data:
```

Run the container:
```bash
docker compose up -d
```

### ⚙️ Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| **`TUNNEL_PROTOCOL`** | `wireguard` | `wireguard` (kernel, default) or `masque` (usque). Aliases: `wg` / `usque`. |
| `BIND_ADDR` | `0.0.0.0` | SOCKS5 listen address. Use `::` for IPv6 / dual-stack listen. |
| `BIND_PORT` | `1080` | SOCKS5 listen port. |
| `SOCKS_USER` / `SOCKS_PASS` | *(empty)* | Optional SOCKS5 authentication. Both must be set. |
| `ENABLE_IPV6` | `1` | `1`/`true` = dual-stack WARP; `0` = IPv4-only. |
| `MTU` | `1280` | WireGuard interface MTU. |
| `KEEPALIVE` | `15` | `PersistentKeepalive` seconds (NAT/QoS keep-alive). |
| `ENDPOINT_IP` | *(wgcf default)* | Override **WireGuard** endpoint, e.g. `162.159.192.1:4500` or `[2606:4700:d0::a29f:c001]:4500`. |
| `GH_PROXY` | *(none)* | GitHub download proxy prefix for the `wgcf` binary. |
| `TAILSCALE_CIDR` | `100.64.0.0/10` | IPv4 mesh return-path CIDR restored after WireGuard up. |
| `TAILSCALE_CIDR_V6` | `fd7a:115c:a1e0::/48` | IPv6 mesh return-path CIDR restored after WireGuard up. |
| `MASQUE_PROXY_MODE` | `l4-socks` | `l4-socks` (TCP-only, lighter) or `socks` (full gVisor L3, TCP+UDP, heavier). |
| `MASQUE_HTTP2` | `0` | `1` = TCP/HTTP2 fallback when QUIC is blocked. Requires `MASQUE_PROXY_MODE=socks`. |
| `MASQUE_SNI` | *(empty)* | Optional SNI override (full `socks` only; ignored on `l4-socks`). |
| `MASQUE_MTU` | *(empty)* | Optional usque MTU (full `socks` only). |
| `GOMEMLIMIT` | `512MiB` | Soft cap for Go RSS on the MASQUE path (small VPS). |
| `WARP_JWT` | *(empty)* | Zero Trust team token for MASQUE `usque register`. |
| `WARP_LICENSE` | *(empty)* | Optional WARP+ license (best-effort apply via usque). |
| `USQUE_DEVICE_NAME` | `MicroWARP` | Device name sent during MASQUE registration. |
| `USQUE_CONFIG` | `/etc/wireguard/masque-config.json` | Persisted MASQUE identity (same volume as `wg0.conf`). |
| `MICROWARP_TEST_MODE` | `0` | `1` skips all init (CI / dry-run). |

Example with auth + dual-stack + port hopping (WireGuard):

```yaml
    environment:
      - TUNNEL_PROTOCOL=wireguard
      - BIND_ADDR=0.0.0.0
      - BIND_PORT=1080
      - SOCKS_USER=admin
      - SOCKS_PASS=123456
      - ENABLE_IPV6=1
      - ENDPOINT_IP=162.159.192.1:4500
```

Example MASQUE (anti-block / UDP QoS):

```yaml
    environment:
      - TUNNEL_PROTOCOL=masque
      - MASQUE_PROXY_MODE=l4-socks   # or socks + MASQUE_HTTP2=1 for TCP fallback
      - GOMEMLIMIT=512MiB
      - SOCKS_USER=admin
      - SOCKS_PASS=123456
```

### 🔀 WireGuard vs MASQUE

| | **WireGuard (default)** | **MASQUE** |
| :--- | :--- | :--- |
| Engine | Linux kernel `wg0` + `microsocks` | [usque](https://github.com/Diniboy1123/usque) userspace |
| Wire image | UDP 2408 / 4500 (non-standard-ish) | HTTP/3 QUIC **UDP 443** (optional HTTP/2 **TCP 443**) |
| RAM | **~800 KB** | Tens–hundreds of MB (set `GOMEMLIMIT`) |
| Best for | 1C1G VPS, max efficiency | WG blocked/QoSed, captive portals, "looks like HTTPS" |
| Capabilities | Full IP tunnel + dual-stack policy routing | `l4-socks` = TCP only; `socks` = TCP+UDP via gVisor |


> **Identity persistence:** both `wg0.conf` and `masque-config.json` live under `/etc/wireguard`. Always mount the volume — re-registering every restart will hit Cloudflare rate limits.


### 🌐 IPv6 notes

* **WARP tunnel dual-stack** is enabled by default (`ENABLE_IPV6=1`). The entrypoint keeps the IPv6 address from `wgcf` and sets `AllowedIPs = 0.0.0.0/0, ::/0`.
* **Docker host IPv6** must be available for end-to-end IPv6 SOCKS clients. Enable Docker daemon IPv6 if you need published IPv6 ports.
* **SOCKS listen**: default `BIND_ADDR=0.0.0.0` is IPv4-only on the listen socket. Set `BIND_ADDR=::` if clients should connect over IPv6.
* **Disable dual-stack** anytime with `ENABLE_IPV6=0` (useful on hosts where IPv6 breaks `wg-quick`).

### 🚀 Convert to HTTP proxy

The image stays SOCKS-only to remain tiny. Use `gost` (or similar) on the host:

```bash
nohup gost -F=socks5://admin:123456@127.0.0.1:1080 -L=http://127.0.0.1:8081 > /dev/null 2>&1 &
```

*Use `socks5://` (not `socks5h://`) so the host resolves DNS and avoids startup resolve timeouts.*

---

<a name="chinese"></a>
## 🇨🇳 中文说明

一个极简、高性能的 Cloudflare WARP SOCKS5 Docker 代理。
致力于为服务器提供极低资源占用的出口网络解耦方案，现已原生支持 **IPv4 / IPv6 双栈**。

### 🌟 为什么选择 MicroWARP？

市面上大多数 WARP 镜像（例如 `caomingjun/warp`）依赖于 Cloudflare 官方的 `warp-cli` 守护进程。这种方式通常会导致较高的内存占用（约 **150MB+**），且在高并发场景下存在一定的性能瓶颈。

**MicroWARP** 采用了不同的底层架构：
1. **内核级 WireGuard（默认）**：采用 Linux 原生内核态的 `wg0` 接口接管流量，CPU 损耗近乎为零。
2. **可选 MASQUE**：`TUNNEL_PROTOCOL=masque` 时使用 [usque](https://github.com/Diniboy1123/usque)（CONNECT-IP / HTTP/3）。适合 WireGuard UDP 被 QoS/封锁的环境，流量外观接近 **443 HTTPS**。
3. **MicroSOCKS 引擎**：WireGuard 路径使用纯 C `microsocks`；MASQUE 路径使用 usque 的 `l4-socks` / `socks`。
4. **极低内存占用（WireGuard）**：高并发下仍 **< 5MB**（常驻约 800KB）。MASQUE 为用户态 QUIC，内存显著更高（见下表）。
5. **原生双栈**：WireGuard 路径完整保留 IPv6，`AllowedIPs` 含 `0.0.0.0/0` 与 `::/0`，并补齐 IPv6 策略路由。
6. **原生兼容 Tailscale**：WireGuard 路径智能保留 IPv4 / IPv6 回程路由，解决非对称路由黑洞。
7. **多架构支持**：原生支持 `amd64` 与 `arm64`（注册路径亦兼容 `armv7`）。


### 🎯 典型应用场景
**⚠️ 声明：本项目专为服务端 (Server-side) 设计，并非个人电脑本地代理软件。**

1. **API 网络路由**：为服务器上的爬虫或大模型 API 网关（如 Grok / ChatGPT）提供稳定的 Cloudflare 出口 IP。
2. **服务端出口隐私**：挂载 MicroWARP 作为服务器的出站网关，隐藏 VPS 真实 IP，降低遭到溯源扫描的风险。
3. **微服务 Sidecar**：极低的资源占用使其非常适合作为 Docker Sidecar 容器，为特定的后端服务提供独立的网络出口。
4. **IPv6 出口**：在宿主机 IPv6 对等质量不佳时，通过 WARP 访问仅 IPv6 的目标。

### 📦 快速开始

只需映射 `1080` 端口并赋予容器 `NET_ADMIN` 权限。新建一个 `docker-compose.yml`：

```yaml
services:
  microwarp:
    image: ghcr.io/ccbkkb/microwarp:latest
    container_name: microwarp
    restart: always
    ports:
      - "127.0.0.1:1080:1080" # 默认无密码 SOCKS5 端口，仅监听本机
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv6.conf.default.disable_ipv6=0
      - net.ipv6.conf.all.forwarding=1
    volumes:
      - warp-data:/etc/wireguard # 持久化保存账号凭证

volumes:
  warp-data:
```

启动容器：
```bash
docker compose up -d
```

### ⚙️ 环境变量一览

| 变量 | 默认值 | 说明 |
| :--- | :--- | :--- |
| **`TUNNEL_PROTOCOL`** | `wireguard` | `wireguard`（内核，默认）或 `masque`（usque）。别名：`wg` / `usque` |
| `BIND_ADDR` | `0.0.0.0` | SOCKS5 监听地址；需要 IPv6 入站时设为 `::` |
| `BIND_PORT` | `1080` | SOCKS5 监听端口 |
| `SOCKS_USER` / `SOCKS_PASS` | 空 | 可选认证；需同时设置 |
| `ENABLE_IPV6` | `1` | `1` 双栈 / `0` 仅 IPv4 |
| `MTU` | `1280` | WireGuard MTU |
| `KEEPALIVE` | `15` | UDP 心跳秒数，对抗 NAT/QoS |
| `ENDPOINT_IP` | wgcf 默认 | **仅 WireGuard** 自定义节点，如 `162.159.192.1:4500` |
| `GH_PROXY` | 无 | 加速 `wgcf` 二进制下载的 GitHub 代理前缀 |
| `TAILSCALE_CIDR` | `100.64.0.0/10` | IPv4 组网回程网段（WireGuard 路径） |
| `TAILSCALE_CIDR_V6` | `fd7a:115c:a1e0::/48` | IPv6 组网回程网段（WireGuard 路径） |
| `MASQUE_PROXY_MODE` | `l4-socks` | `l4-socks`（仅 TCP，更轻）或 `socks`（gVisor 全栈，更重） |
| `MASQUE_HTTP2` | `0` | `1` = QUIC 不可用时走 TCP/HTTP2；需 `MASQUE_PROXY_MODE=socks` |
| `MASQUE_SNI` | 空 | 可选 SNI（仅 full `socks`；`l4-socks` 忽略） |
| `GOMEMLIMIT` | `512MiB` | MASQUE 路径限制 Go 进程 RSS（小内存 VPS） |
| `WARP_JWT` | 空 | Zero Trust team token（MASQUE 注册） |
| `WARP_LICENSE` | 空 | 可选 WARP+（尽力通过 usque 绑定） |
| `USQUE_DEVICE_NAME` | `MicroWARP` | MASQUE 注册设备名 |
| `USQUE_CONFIG` | `/etc/wireguard/masque-config.json` | MASQUE 身份持久化路径（与 wg 共用 volume） |
| `MICROWARP_TEST_MODE` | `0` | `1` 跳过初始化（CI） |

进阶示例（WireGuard）：

```yaml
    environment:
      - TUNNEL_PROTOCOL=wireguard
      - BIND_ADDR=0.0.0.0
      - BIND_PORT=1080
      - SOCKS_USER=admin
      - SOCKS_PASS=123456
      - ENABLE_IPV6=1
      # 部分机房对 UDP 2408 有 QoS，可改 4500 提升连通率
      - ENDPOINT_IP=162.159.192.1:4500
      - GH_PROXY=https://github.ednovas.xyz
```

MASQUE 示例（抗封锁 / UDP 被 QoS）：

```yaml
    environment:
      - TUNNEL_PROTOCOL=masque
      - MASQUE_PROXY_MODE=l4-socks
      # 若 UDP/QUIC 也被拦：改 socks + HTTP2
      # - MASQUE_PROXY_MODE=socks
      # - MASQUE_HTTP2=1
      - GOMEMLIMIT=512MiB
      - SOCKS_USER=admin
      - SOCKS_PASS=123456
```

### 🔀 WireGuard 与 MASQUE 怎么选

| | **WireGuard（默认）** | **MASQUE** |
| :--- | :--- | :--- |
| 引擎 | 内核 `wg0` + `microsocks` | [usque](https://github.com/Diniboy1123/usque) 用户态 |
| 流量特征 | UDP 2408 / 4500 | HTTP/3 **UDP 443**（可选 HTTP/2 **TCP 443**） |
| 内存 | **约 800 KB** | 数十～上百 MB（请设 `GOMEMLIMIT`） |
| 适用 | 1C1G、极致省资源 | WG 被封/QoS、需要更像 HTTPS |
| 能力 | 完整 IP 隧道 + 双栈策略路由 | `l4-socks` 仅 TCP；`socks` 经 gVisor 支持 TCP+UDP |


> **务必挂载 volume**：`wg0.conf` 与 `masque-config.json` 都在 `/etc/wireguard`。每次重启重新注册会触发 Cloudflare 限流。


### 🌐 IPv6 说明

* 默认开启双栈（`ENABLE_IPV6=1`），保留 wgcf 配置中的 IPv6 地址，并写入 `AllowedIPs = 0.0.0.0/0, ::/0`。
* 若要让 SOCKS 客户端通过 IPv6 连入，请设置 `BIND_ADDR=::`，并确保 Docker / 宿主机已启用 IPv6。
* 若宿主环境 IPv6 异常导致 `wg-quick` 失败，可设 `ENABLE_IPV6=0` 回退纯 IPv4。
* 入站发布端口的回包路径会通过 IPv4 table 128 / IPv6 table 129 策略路由修复，避免非对称黑洞。

### 🚀 扩展用法：转换为 HTTP 代理

基于 Unix 哲学，底层镜像未内置 HTTP 解析引擎以维持极限轻量化。如需 HTTP 代理，推荐使用 `gost` 进行本地转换：

```bash
nohup gost -F=socks5://admin:123456@127.0.0.1:1080 -L=http://127.0.0.1:8081 > /dev/null 2>&1 &
```

*注：请务必使用 `socks5://`（而非 `socks5h://`）以由宿主机处理 DNS 解析，避免启动时的解析超时问题。*

---

### 🔧 相对旧版的主要修复（重构摘要）

* **IPv6 不再被强行剥离**：旧版会删除全部 `Address`/`AllowedIPs` 后只写回 IPv4。
* **错误处理**：`set -eu`、下载重试、GitHub API 失败回退版本、`wg-quick` 失败时打印诊断而非静默成功。
* **配置清洗更安全**：按字段精确删除并重建，避免 BusyBox `sed` 误伤。
* **策略路由双栈**：IPv4 table 128 + IPv6 table 129；Tailscale IPv6 ULA 回程同步恢复。
* **注册流程隔离**：`wgcf` 在临时目录执行，阅后即焚，避免污染工作目录。
* **镜像依赖补齐**：`ip6tables`、`ca-certificates`、`openresolv`；基础镜像固定 `alpine:3.21`。
* **可选 MASQUE**：镜像内置 [usque](https://github.com/Diniboy1123/usque)；`TUNNEL_PROTOCOL=masque` 走 CONNECT-IP，默认仍为内核 WireGuard。

### 🙏 致谢

* [ViRb3/wgcf](https://github.com/ViRb3/wgcf) — WireGuard 账号注册
* [rofl0r/microsocks](https://github.com/rofl0r/microsocks) — 极简 SOCKS5
* [Diniboy1123/usque](https://github.com/Diniboy1123/usque) — 开源 WARP MASQUE / CONNECT-IP 客户端


---

*特别鸣谢 __LinuxDo__ 社区* ❤️

---

## Star History

<a href="https://www.star-history.com/?repos=ccbkkb%2FMicroWARP&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=ccbkkb/MicroWARP&type=date&theme=dark&legend=top-left&sealed_token=E9V7v_-roZj_Qp5MPtcMNG7kMJbD6SAkh_nWVRl5EjGhbH2qNhuRyVWMxv0sgElkhUhAtY-F4AN8fQAeQ6dHl7dWqXAIOyfkX5r7Vx6X9IVI27axW9eBvg" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=ccbkkb/MicroWARP&type=date&legend=top-left&sealed_token=E9V7v_-roZj_Qp5MPtcMNG7kMJbD6SAkh_nWVRl5EjGhbH2qNhuRyVWMxv0sgElkhUhAtY-F4AN8fQAeQ6dHl7dWqXAIOyfkX5r7Vx6X9IVI27axW9eBvg" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=ccbkkb/MicroWARP&type=date&legend=top-left&sealed_token=E9V7v_-roZj_Qp5MPtcMNG7kMJbD6SAkh_nWVRl5EjGhbH2qNhuRyVWMxv0sgElkhUhAtY-F4AN8fQAeQ6dHl7dWqXAIOyfkX5r7Vx6X9IVI27axW9eBvg" />
 </picture>
</a>
