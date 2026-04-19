# ==========================================
# 阶段 1：极速编译 MicroSOCKS 引擎 & 获取 WireProxy
# ==========================================
FROM alpine:latest AS builder
# 安装构建依赖
RUN apk add --no-cache build-base git wget tar

# 1. 从官方仓库拉取源码并编译 MicroSOCKS (用于内核特权态)
RUN git clone https://github.com/rofl0r/microsocks.git /src && \
    cd /src && make

# 2. 获取 WireProxy (用于 LXC/OVZ 用户态降级)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64) WP_ARCH="amd64" ;; \
        aarch64) WP_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    wget -O /tmp/wireproxy.tar.gz "https://github.com/octeep/wireproxy/releases/latest/download/wireproxy_linux_${WP_ARCH}.tar.gz" && \
    tar -xzf /tmp/wireproxy.tar.gz -C /tmp

# ==========================================
# 阶段 2：极净运行环境
# ==========================================
FROM alpine:latest

# 仅安装必要的内核级 WireGuard 和网络控制工具
RUN apk add --no-cache wireguard-tools iptables iproute2 wget curl

# 打包 microsocks 和 wireproxy
COPY --from=builder /src/microsocks /usr/local/bin/microsocks
COPY --from=builder /tmp/wireproxy /usr/local/bin/wireproxy
RUN chmod +x /usr/local/bin/microsocks /usr/local/bin/wireproxy

WORKDIR /app
COPY entrypoint.sh .
# 后续任务 #6 的排查脚本也会拷入这里
# COPY diag.sh . 
RUN chmod +x entrypoint.sh

# 启动引擎
CMD ["./entrypoint.sh"]
