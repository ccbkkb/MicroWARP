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

| Metric (指标) | `caomingjun/warp` (Official Daemon) | 🚀 `MicroWARP` (Pure C + Kernel) | Improvement (提升) |
| :--- | :--- | :--- | :--- |
| **Image Size**<br>(Docker 镜像体积) | 201 MB | **~10 MB** | 📉 **-95%** |
| **RAM Usage**<br>(日常内存占用) | ~150 MB | **800 KiB** (< 1MB) | 📉 **-99.4%** |
| **CPU Overhead**<br>(高并发 CPU 损耗) | High (Userspace App) | **~0.25%** (Kernel Space) | ⚡ **Near Zero** |
| **Core Engine**<br>(底层核心引擎) | Cloudflare `warp-cli` (Rust) | Linux `wg0` + Pure C `microsocks` | 🛠️ **Minimalist** |

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
Designed as a lightweight drop-in replacement for standard WARP proxy images.

### ✨ Feature Highlights
*   **Automated Account Rotation**: Automatically requests a new free account in the background every 7 days by default, achieving "millisecond-level replacement" via native Linux kernel commands.
*   **Dual-Stack Network Support**: Enable IPv4-only (`4`) or full Dual-Stack (`dual`) outbound proxy capabilities out of the box via a single environment variable.
*   **LXC / OVZ Unprivileged Compatibility**: Automatically detects the host environment. If deployed in restricted container architectures (without network interface privileges), it seamlessly falls back to a userspace network stack, completely eliminating crash errors.
*   **Cloudflare Zero Trust (Teams) Support**: No complex login simulation scripts required. Simply drop your extracted `wg0.conf` Team profile into the config volume, and the container will automatically mount it and route your traffic through the enterprise network!

### 📦 Quick Start

Map port `1080` and grant privileges. Create a `docker-compose.yml`:

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
    volumes:
      - warp-data:/etc/wireguard

volumes:
  warp-data:
```

### ⚙️ Advanced Features

MicroWARP supports powerful environment variables to customize your setup:

```yaml
    environment:
      - SOCKS_USER=admin      # Enable authentication
      - SOCKS_PASS=123456     # Auth password
      - IPV6_MODE=dual        # '4' (default), '6' (IPv6 Only), or 'dual' (Dual Stack)
      - AUTO_RENEW_DAYS=7     # Auto-rotate account every 7 days to prevent blocks
      - ENDPOINT_IP=162.159.192.1:4500 # Port Hopping to bypass QoS in certain Datacenters
```

#### 🛡️ Scaleway / IPv6-Only VPS Setup
If your server does not have a public IPv4 address, you must use Docker's host network and set `IPV6_MODE=6`. MicroWARP will automatically bind to Cloudflare's IPv6 endpoints:
```yaml
    network_mode: "host" # Replace 'ports' mapping with this
    environment:
      - IPV6_MODE=6
      - GH_PROXY=https://ghproxy.net/ # Required to download wgcf via IPv4 GitHub
```

#### 🛠️ Built-in Diagnostic Tool
Connection issues? Run the built-in diagnostic tool to quickly troubleshoot TUN permissions, wg0 status, and CF API reachability:
```bash
docker exec -it microwarp diag
```

---

<a name="chinese"></a>
## 🇨🇳 中文说明

一个极简、高性能的 Cloudflare WARP SOCKS5 Docker 代理。
致力于为服务器提供极低资源占用的出口网络解耦方案。

### ✨ 杀手级特性
*   **账户自动化注册轮换**：后台默认每 7 天自动申请新账号，并通过 Linux 内核原生指令实现“毫秒级替换”。
*   **双栈3网络支持**：支持通过环境变量一键开启 纯 IPv4 (`4`) / 双栈 (`dual`) 代理出站能力。
*   **LXC / OVZ 无特权兼容**：自动检测宿主机环境。如果在受限的容器架构（无网卡特权）中启动，会自动平滑降级至用户态网络栈运行，告别崩溃报错。
*   **CF-Team (Zero Trust) 接入**：无需复杂的脚本模拟登录，只需将提取好的团队版 `wg0.conf` 文件放进配置卷，容器会自动挂载并连入企业专线！

### 🎯 典型应用场景
**⚠️ 声明：本项目专为服务端 (Server-side) 设计，绝对禁止在位于中国大陆境内的云服务器上运行，否则会导致封号封机。**
1. **API 网络路由**：为爬虫或大模型 API 网关（如 Grok / ChatGPT）提供干净稳定的原生 Cloudflare 出口 IP。
2. **服务端出口隐私**：挂载 MicroWARP 隐藏 VPS 真实 IP，降低遭到溯源扫描的风险。

### 📦 快速开始

新建一个 `docker-compose.yml`：

```yaml
services:
  microwarp:
    image: ghcr.io/ccbkkb/microwarp:latest
    container_name: microwarp
    restart: always
    ports:
      - "127.0.0.1:1080:1080" # 默认无密码，仅监听本机
    
    # KVM/物理机用户保留此权限以开启 800KB 内存模式。
    # LXC/OVZ 用户若启动报错，请直接删除下方 4 行，程序将自动降级。
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      
    volumes:
      - warp-data:/etc/wireguard

volumes:
  warp-data:
```
启动容器：`docker compose up -d`

### ⚙️ 进阶配置与高级玩法

MicroWARP 支持通过环境变量解锁更强大的能力：

```yaml
    environment:
      - SOCKS_USER=admin      # SOCKS5 认证用户名 (留空则为无密码模式)
      - SOCKS_PASS=123456     # SOCKS5 认证密码
      - AUTO_RENEW_DAYS=7     # 开启零停机热重载，每 7 天自动更换一次账号
      - IPV6_MODE=dual        # 出口网络支持：'4' (默认IPv4), '6' (纯IPv6), 或 'dual' (全能双栈)
      - ENDPOINT_IP=162.159.192.1:4500 # 自定义 Endpoint 端口，绕过机房对 2408 UDP 的阻断
```

#### 🛡️ Scaleway 等纯 IPv6 机器配置指南
如果你的 VPS 连 IPv4 地址都没有（IPv6_Only VPS），请勿配置 Docker 的复杂网络栈。直接使用宿主机网络并开启纯 v6 模式，MicroWARP 会自动寻找 CF 的 IPv6 接入点：
```yaml
    network_mode: "host" # 删除原有的 ports 映射，改为这行
    environment:
      - IPV6_MODE=6
      - GH_PROXY=https://ghproxy.net/ # 纯 v6 机器必备，否则无法下载核心组件
```

#### 🔑 如何使用 Cloudflare Zero Trust (Team版)？
本项目原生支持外部配置文件。
1. 在本地使用 `warp-cli` 或第三方工具提取出 Team 账户的配置文件。
2. 将文件重命名为 `wg0.conf`。
3. 替换掉宿主机 `warp-data` 目录中的同名文件并重启容器。程序会自动跳过注册流程，为你开启无限流量的 Team 专线！

#### 🛠️ 一键排障工具
如果代理无法连通，无需盲目猜测，进入容器执行内置自检脚本即可快速定位问题（TUN 权限、内核状态、CF 连通性）：
```bash
docker exec -it microwarp diag
```

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
