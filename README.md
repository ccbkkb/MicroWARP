# MicroWARP 🚀

[![Docker Pulls](https://img.shields.io/badge/docker-ready-blue.svg)](https://github.com/ccbkkb/MicroWARP/packages)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[English](#english) |[中文说明](#chinese)

### 📊 Performance Comparison (性能碾压对比)

Here is a real-world performance test on a 1C1G (1 vCPU, 1GB RAM) VPS, comparing MicroWARP with the widely used `caomingjun/warp`.

以下是在 1C1G 廉价小鸡上的真实运行数据截图对比。你可以清楚地看到 MicroWARP 是如何榨干物理机极限的：

| Metric (性能指标) | `caomingjun/warp` (Official Daemon) | 🚀 `MicroWARP` (Our pure C + Kernel approach) | 碾压级提升 (Improvement) |
| :--- | :--- | :--- | :--- |
| **Image Size**<br>(Docker 镜像体积) | 201 MB | **9.08 MB** | 📉 **直降 95%** |
| **RAM Usage**<br>(日常内存占用) | ~150 MB | **800 KiB** (< 1MB) | 📉 **暴降 99.4%** |
| **CPU Overhead**<br>(高并发 CPU 损耗) | High (Userspace App) | **~0.25%** (Kernel Space) | ⚡ **近乎为零** |
| **Core Engine**<br>(底层核心引擎) | Cloudflare `warp-cli` (Rust/Heavy) | Linux `wg0` + Pure C `microsocks` | 🛠️ **极简硬核** |

> **🔥 Real `docker stats` output (真实的生产环境终端输出):**
> ```text
> CONTAINER ID   NAME       CPU %     MEM USAGE / LIMIT     MEM %     NET I/O           BLOCK I/O
> 2fa58f84c517   warp       0.25%     800KiB / 967.4MiB     0.08%     48.8MB / 39.1MB   238kB / 36.9kB
> ```
> *Yes, you read that right. It processed ~90MB of traffic using only **800 KB** of RAM!*
> *(没看错，它在处理了近 90MB 网络吞吐的同时，仅仅占用了 **800 KB** 的内存！)*

---

<a name="english"></a>
## 🇬🇧 English

An ultra-lightweight, high-performance Cloudflare WARP SOCKS5 proxy in Docker. 
A perfect drop-in replacement for `caomingjun/warp`.

### 🌟 Why MicroWARP?

Many popular WARP Docker images (like `caomingjun/warp`) rely on the official Cloudflare `warp-cli` daemon. This results in heavy memory usage (often **150MB+**) and potential process deadlocks under high concurrency.

**MicroWARP** does things differently:
1. **Kernel-Level WireGuard**: It drops the bloated official client and uses Linux's native `wg0` interface. CPU usage is almost zero.
2. **MicroSOCKS**: It uses a pure C-based `microsocks` server instead of heavy Go/Rust proxies.
3. **Extreme Low RAM**: Runs smoothly on **< 5MB RAM** (often under 1MB). Perfect for 1C1G cheap VPS.
4. **Multi-Arch**: Native support for `amd64` and `arm64` (Oracle Cloud ARM ready).

### 📦 Quick Start

You can seamlessly replace your existing WARP proxy. Just map port `1080` and give it `NET_ADMIN` privileges. Create a `docker-compose.yml`:

```yaml
version: '3.8'

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
      - warp-data:/etc/wireguard # Keep account data to avoid rate limits

volumes:
  warp-data:
```

Run the container:
```bash
docker compose up -d
```

### 🔥 Advanced Features (Auth, Port, Bypass DPI)

MicroWARP supports powerful environment variables to customize your setup while keeping the RAM at 800KB:

```yaml
    environment:
      - BIND_ADDR=0.0.0.0     # Bind address (default: 0.0.0.0)
      - BIND_PORT=1080        # Custom SOCKS5 port (default: 1080)
      - SOCKS_USER=admin      # Enable authentication (leave empty for no auth)
      - SOCKS_PASS=123456     # Auth password
      - ENDPOINT_IP=162.159.193.10:2408 # Custom WARP Endpoint IP (Bypass regional blocks)
```

*(Note: If your VPS is in HK or US and cannot connect to WARP due to Cloudflare's `reserved` bytes verification, simply scan a clean CF endpoint IP and inject it via `ENDPOINT_IP`. MicroWARP will seamlessly route traffic through it!)*

### 🚀 Need an HTTP Proxy?

MicroWARP strictly adheres to the Unix philosophy. We keep the memory usage at **800KB** by providing a pure L4 SOCKS5 engine. We will never bloat the image with heavy L7 HTTP parsers. 

If your app only supports HTTP proxies, you can elegantly chain it with tools like `gost`:
```bash
nohup gost -F=socks5://admin:123456@127.0.0.1:1080 -L=http://:8081 > /dev/null 2>&1 &
```
*⚠️ **Pro Tip**: Use `socks5://` instead of `socks5h://`. This forces the host to resolve DNS locally, completely avoiding `503 Service Unavailable` errors caused by WireGuard's UDP handshake delay!*

### 📝 Auto-Registration
Zero configuration required. On the first run, MicroWARP will automatically register a free WARP account and persist the configuration in the Docker volume.

---

<a name="chinese"></a>
## 🇨🇳 中文说明

一个超轻量、高性能的 Cloudflare WARP SOCKS5 Docker 代理。
完美平替 `caomingjun/warp` 的终极方案。

### 🌟 为什么选择 MicroWARP？

市面上流行的 WARP 镜像（例如 `caomingjun/warp`）绝大多数打包了 Cloudflare 官方的 `warp-cli` 守护进程。这会导致极高的内存占用（通常在 **150MB 以上**），并且在高并发下极易发生进程死锁和崩溃。

**MicroWARP** 采用了完全不同的极客底层架构：
1. **内核级 WireGuard**：彻底抛弃臃肿的官方客户端，直接调用 Linux 原生内核态的 `wg0` 网卡接管流量，CPU 损耗近乎为零。
2. **MicroSOCKS 引擎**：使用纯 C 语言编写的 `microsocks` 服务器替代繁重的 Go/Rust 代理引擎。
3. **极致极低内存**：高并发下内存占用依然 **< 5MB**（实测常驻 800KB 左右）。专为 1C1G 的廉价小内存 VPS 打造的拯救者。
4. **多架构支持**：原生支持 `amd64` 和 `arm64`（完美兼容甲骨文免费 ARM 机器）。

### 📦 快速开始

你可以零成本无缝替换掉现有的 WARP 代理。只需映射 `1080` 端口并赋予容器 `NET_ADMIN` 网络管理权限。新建一个 `docker-compose.yml`：

```yaml
version: '3.8'

services:
  microwarp:
    image: ghcr.io/ccbkkb/microwarp:latest
    container_name: microwarp
    restart: always
    ports:
      - "127.0.0.1:1080:1080" # 标准的无密码 SOCKS5 端口，仅监听本机
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    volumes:
      - warp-data:/etc/wireguard # 持久化保存账号凭证，防止重启触发风控

volumes:
  warp-data:
```

启动容器：
```bash
docker compose up -d
```

启动后，将你的应用（Telegram、v2ray、Xray、AIzaSy、Grok2API 等）的 SOCKS5 代理指向 `127.0.0.1:1080`，你的出站流量就已经被 Cloudflare 骨干网完美接管并洗白了！

### 🔥 进阶配置：自定义端口、密码认证与抗阻断

MicroWARP 支持极其强大的环境变量注入配置，并且开启这些功能后，内存依旧保持 **800KB** 的神话：

```yaml
    environment:
      - BIND_ADDR=0.0.0.0     # 监听地址 (默认 0.0.0.0，请不要修改这里，除非你知道自己在做什么)
      - BIND_PORT=1080        # 监听端口 (默认 1080)
      - SOCKS_USER=admin      # SOCKS5 认证用户名 (留空则为无密码模式)
      - SOCKS_PASS=123456     # SOCKS5 认证密码
      
      # ⚠️ 针对香港/美西机房的防阻断绝杀：
      - ENDPOINT_IP=162.159.193.10:2408 # 注入你扫出的优选 IP，完美绕过 CF 的 reserved 字节阻断！
```

### 🚀 高级玩法：如何将其转换为 HTTP 代理？

MicroWARP 坚守 Unix 哲学（Do one thing and do it well）。为了保持 800KB 的极限内存，我们绝不会在底层内置臃肿的七层 HTTP 解析引擎。

如果你需要 HTTP 代理，可以使用 `gost` 极其优雅地串联转换（L4 转 L7）：
```bash
nohup gost -F=socks5://admin:123456@127.0.0.1:1080 -L=http://:8081 > /dev/null 2>&1 &
```
*⚠️ **避坑诊断指南**：请务必使用 `socks5://` 而不是 `socks5h://`。去掉 `h` 可以让 gost 在宿主机本地网络解析 DNS，完美避开 WARP UDP 隧道冷启动握手时容易触发的 DNS 解析死锁，彻底告别偶尔出现的 `503 Service Unavailable` 报错！稳如老狗！*

### 📝 全自动免配置
你不需要手动提取任何密钥。首次启动时，MicroWARP 会在后台全自动向 Cloudflare 申请注册免费 WARP 账户，提取节点信息，并永久保存在本地的数据卷中。

---

*特别鸣谢: __LinuxDo__, __NodeSeek__ (排名不分先后)* ❤️
