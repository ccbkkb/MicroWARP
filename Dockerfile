# ==========================================
# Stage 1: Build microsocks (pure C SOCKS5)
# ==========================================
FROM alpine:3.21 AS microsocks-builder

RUN apk add --no-cache build-base git

ARG MICROSOCKS_REF=master
RUN git clone --depth 1 --branch "${MICROSOCKS_REF}" \
        https://github.com/rofl0r/microsocks.git /src \
    && make -C /src

# ==========================================
# Stage 2: Fetch usque (MASQUE / CONNECT-IP client)
# Prebuilt official releases — no Go toolchain in image build.
# ==========================================
FROM alpine:3.21 AS usque-downloader

RUN apk add --no-cache curl ca-certificates unzip \
    && update-ca-certificates

# Pin a known-good release; override at build time if needed.
ARG USQUE_VERSION=4.2.1
ARG TARGETARCH

RUN set -eu; \
    case "${TARGETARCH}" in \
        amd64|x86_64) arch=amd64 ;; \
        arm64|aarch64) arch=arm64 ;; \
        arm|arm/v7) arch=armv7 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/Diniboy1123/usque/releases/download/v${USQUE_VERSION}/usque_${USQUE_VERSION}_linux_${arch}.zip"; \
    echo "Downloading ${url}"; \
    curl -fsSL -o /tmp/usque.zip "${url}"; \
    unzip -q /tmp/usque.zip -d /tmp/usque-extract; \
    # Release zip layout may be flat or nested — find the binary.
    bin="$(find /tmp/usque-extract -type f -name 'usque' | head -n 1)"; \
    test -n "${bin}" && test -s "${bin}"; \
    install -m 755 "${bin}" /usr/local/bin/usque; \
    /usr/local/bin/usque version || /usr/local/bin/usque --help >/dev/null || true

# ==========================================
# Stage 3: Minimal runtime
# ==========================================
FROM alpine:3.21

# iptables package ships both iptables & ip6tables on Alpine.
# openresolv satisfies resolvconf calls from some wg-quick code paths.
# unzip not needed at runtime; ca-certificates for HTTPS (wgcf + usque + probes).
RUN apk add --no-cache \
        wireguard-tools \
        iptables \
        iproute2 \
        curl \
        wget \
        ca-certificates \
        openresolv \
    && update-ca-certificates \
    && rm -rf /var/cache/apk/*

COPY --from=microsocks-builder /src/microsocks /usr/local/bin/microsocks
COPY --from=usque-downloader /usr/local/bin/usque /usr/local/bin/usque

WORKDIR /app
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh \
    && mkdir -p /etc/wireguard /etc/usque

EXPOSE 1080/tcp
# WireGuard profile lives under /etc/wireguard (legacy).
# MASQUE (usque) config defaults to /etc/wireguard/masque-config.json so a
# single named volume can persist both protocol identities.
VOLUME ["/etc/wireguard"]

CMD ["./entrypoint.sh"]
