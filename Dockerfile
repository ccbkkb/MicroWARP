# ==========================================
# Stage 1: Build microsocks (pure C SOCKS5)
# ==========================================
FROM alpine:3.21 AS builder

RUN apk add --no-cache build-base git

ARG MICROSOCKS_REF=master
RUN git clone --depth 1 --branch "${MICROSOCKS_REF}" \
        https://github.com/rofl0r/microsocks.git /src \
    && make -C /src

# ==========================================
# Stage 2: Minimal runtime
# ==========================================
FROM alpine:3.21

# iptables package ships both iptables & ip6tables on Alpine.
# openresolv satisfies resolvconf calls from some wg-quick code paths.
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

COPY --from=builder /src/microsocks /usr/local/bin/microsocks

WORKDIR /app
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh \
    && mkdir -p /etc/wireguard

EXPOSE 1080/tcp
VOLUME ["/etc/wireguard"]

CMD ["./entrypoint.sh"]
