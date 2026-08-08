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
| **Image Size**<br>(Docker 镜像体积) | 201 MB | **~10 MB** | 📉 **-95%** |
| **RAM Usage**<br>(日常内存占用) | ~150 MB | **~800 KiB** (< 1MB) | 📉 **-99.4%** |
| **CPU Overhead**<br>(高并发 CPU 损耗) | High (Userspace App) | **~0.25%** (Kernel Space) | ⚡ **Near Zero** |
| **Core Engine**<br>(底层核心引擎) | Cloudflare `warp-cli` (Rust) | Linux `wg0` + Pure C `microsocks` | 🛠️ **Minimalist** |
| **IP Stack**<br>(协议栈) | Mostly IPv4-focused | **Dual-stack IPv4 + IPv6** | 🌐 **Native** |

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
1. **Kernel-Level WireGuard**: Instead of the userspace client, it leverages the native Linux `wg0` interface for near-zero CPU overhead.
2. **MicroSOCKS Engine**: Uses a pure C-based `microsocks` server to minimize resource consumption.
3. **Minimal Memory Footprint**: Runs smoothly on **< 5MB RAM** (often ~800KB). Highly optimized for resource-constrained environments (e.g., 1C1G VPS).
4. **Native Dual-Stack**: Full **IPv4 + IPv6** WARP routing (`AllowedIPs = 0.0.0.0/0, ::/0`), with IPv6 policy routing for inbound reply paths.
5. **Seamless Tailscale Integration**: Natively resolves asymmetric routing blackholes for both IPv4 (`100.64.0.0/10`) and IPv6 (`fd7a:115c:a1e0::/48`).
6. **Multi-Arch**: Native support for `amd64` and `arm64` (plus `armv7` registration path).

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
| `BIND_ADDR` | `0.0.0.0` | SOCKS5 listen address. Use `::` for IPv6 / dual-stack listen. |
| `BIND_PORT` | `1080` | SOCKS5 listen port. |
| `SOCKS_USER` / `SOCKS_PASS` | *(empty)* | Optional SOCKS5 authentication. Both must be set. |
| `ENABLE_IPV6` | `1` | `1`/`true` = dual-stack WARP; `0` = IPv4-only. |
| `MTU` | `1280` | WireGuard interface MTU. |
| `KEEPALIVE` | `15` | `PersistentKeepalive` seconds (NAT/QoS keep-alive). |
| `ENDPOINT_IP` | *(wgcf default)* | Override WARP endpoint, e.g. `162.159.192.1:4500` or `[2606:4700:d0::a29f:c001]:4500`. |
| `GH_PROXY` | *(none)* | GitHub download proxy prefix for the `wgcf` binary. |
| `TAILSCALE_CIDR` | `100.64.0.0/10` | IPv4 mesh return-path CIDR restored after WARP up. |
| `TAILSCALE_CIDR_V6` | `fd7a:115c:a1e0::/48` | IPv6 mesh return-path CIDR restored after WARP up. |
| `MICROWARP_TEST_MODE` | `0` | `1` skips all init (CI / dry-run). |

Example with auth + dual-stack + port hopping:

```yaml
    environment:
      - BIND_ADDR=0.0.0.0
      - BIND_PORT=1080
      - SOCKS_USER=admin
      - SOCKS_PASS=123456
      - ENABLE_IPV6=1
      - ENDPOINT_IP=162.159.192.1:4500
```

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
1. **内核级 WireGuard**：采用 Linux 原生内核态的 `wg0` 接口接管流量，CPU 损耗近乎为零。
2. **MicroSOCKS 引擎**：使用纯 C 语言编写的 `microsocks` 服务器，极大降低资源消耗。
3. **极低内存占用**：高并发下内存占用依然 **< 5MB**（实测常驻 800KB 左右），专为资源受限的云服务器环境打造。
4. **原生双栈**：完整保留 WARP 下发的 IPv6 地址，`AllowedIPs` 同时包含 `0.0.0.0/0` 与 `::/0`，并补齐 IPv6 策略路由。
5. **原生兼容 Tailscale**：智能保留 IPv4 / IPv6 回程路由，解决全局接管导致的非对称路由黑洞。
6. **多架构支持**：原生支持 `amd64` 与 `arm64`（注册路径亦兼容 `armv7`）。

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
| `BIND_ADDR` | `0.0.0.0` | SOCKS5 监听地址；需要 IPv6 入站时设为 `::` |
| `BIND_PORT` | `1080` | SOCKS5 监听端口 |
| `SOCKS_USER` / `SOCKS_PASS` | 空 | 可选认证；需同时设置 |
| `ENABLE_IPV6` | `1` | `1` 双栈 / `0` 仅 IPv4 |
| `MTU` | `1280` | WireGuard MTU |
| `KEEPALIVE` | `15` | UDP 心跳秒数，对抗 NAT/QoS |
| `ENDPOINT_IP` | wgcf 默认 | 自定义节点，如 `162.159.192.1:4500` 或 `[IPv6]:4500` |
| `GH_PROXY` | 无 | 加速 `wgcf` 二进制下载的 GitHub 代理前缀 |
| `TAILSCALE_CIDR` | `100.64.0.0/10` | IPv4 组网回程网段 |
| `TAILSCALE_CIDR_V6` | `fd7a:115c:a1e0::/48` | IPv6 组网回程网段 |
| `MICROWARP_TEST_MODE` | `0` | `1` 跳过初始化（CI） |

进阶示例：

```yaml
    environment:
      - BIND_ADDR=0.0.0.0
      - BIND_PORT=1080
      - SOCKS_USER=admin
      - SOCKS_PASS=123456
      - ENABLE_IPV6=1
      # 部分机房对 UDP 2408 有 QoS，可改 4500 提升连通率
      - ENDPOINT_IP=162.159.192.1:4500
      - GH_PROXY=https://github.ednovas.xyz
```

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

---

*特别鸣谢 __LinuxDo__ 社区* ❤️

---

## 📈 Star History

<a href="https://star-history.com/#ccbkkb/MicroWARP&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=ccbkkb/MicroWARP&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=ccbkkb/MicroWARP&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=ccbkkb/MicroWARP&type=Date" />
  </picture>
</a>
