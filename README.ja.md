# MicroWARP 🚀

[![Docker Pulls](https://img.shields.io/badge/docker-ready-blue.svg)](https://github.com/ccbkkb/MicroWARP/packages)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> *お住まいの国または地域の法令を厳守してください。本プロジェクトの違法または規約に反する使用から生じる法的紛争や結果について、本プロジェクトおよび作者は一切責任を負いません。*
>
> *お住まいの国または地域の法令を厳守してください。本プロジェクトの違法な使用から生じる法的紛争や結果は、本プロジェクトおよび作者とは一切関係ありません。*

[英語セクション](#英語セクションの日本語訳) | [中国語セクション](#中国語セクションの日本語訳) | [日本語](README.ja.md)

### 📊 パフォーマンス比較

以下は、1C1G（1 vCPU、1GB RAM）の VPS 上で MicroWARP と広く利用されている `caomingjun/warp` を比較した、実環境のパフォーマンステストです。

以下は、1C1G サーバー上で実際に稼働させた際のデータを比較したものです。

| 指標 | `caomingjun/warp`（公式デーモン） | 🚀 `MicroWARP`（Pure C + カーネル方式） | 改善率 |
| :--- | :--- | :--- | :--- |
| **イメージサイズ**<br>（Docker イメージ容量） | 201 MB | **9.08 MB** | 📉 **-95%** |
| **RAM 使用量**<br>（通常時のメモリ使用量） | ~150 MB | **800 KiB**（< 1MB） | 📉 **-99.4%** |
| **CPU オーバーヘッド**<br>（高並行処理時の CPU 負荷） | 高（ユーザー空間アプリ） | **~0.25%**（カーネル空間） | ⚡ **ほぼゼロ** |
| **コアエンジン**<br>（基盤となるエンジン） | Cloudflare `warp-cli`（Rust） | Linux `wg0` + Pure C `microsocks` | 🛠️ **ミニマル** |

> **🔥 実際の `docker stats` 出力：**
> ```text
> CONTAINER ID   NAME       CPU %     MEM USAGE / LIMIT     MEM %     NET I/O           BLOCK I/O
> 2fa58f84c517   warp       0.25%     800KiB / 967.4MiB     0.08%     48.8MB / 39.1MB   238kB / 36.9kB
> ```
> *見間違いではありません。わずか **800 KB** の RAM で約 90 MB のトラフィックを処理しました。*

---

<a name="english"></a>
## 🇬🇧 英語セクションの日本語訳

Docker で動作する、ミニマルかつ高性能な Cloudflare WARP SOCKS5 プロキシです。
標準的な WARP プロキシイメージ（例：`caomingjun/warp`）を置き換えられる、軽量なドロップイン代替として設計されています。

### 🌟 MicroWARP を選ぶ理由

一般的な WARP Docker イメージの多くは、Cloudflare 公式の `warp-cli` デーモンに依存しています。この方式では通常、メモリ使用量が大きくなり（多くの場合 **150MB 以上**）、高並行処理時にはプロセスのオーバーヘッドが発生する可能性があります。

**MicroWARP** は異なる方法で構築されています。
1. **カーネルレベルの WireGuard**：ユーザー空間クライアントの代わりに Linux ネイティブの `wg0` インターフェースを利用し、CPU オーバーヘッドをほぼゼロにします。
2. **MicroSOCKS エンジン**：Pure C ベースの `microsocks` サーバーを使用し、リソース消費を最小限に抑えます。
3. **最小限のメモリ使用量**：**5MB 未満の RAM**（多くの場合は約 800KB）で安定して動作します。1C1G VPS など、リソースが限られた環境向けに高度に最適化されています。
4. **シームレスな Tailscale 統合**：非対称ルーティングによるブラックホールをネイティブに解消し、Tailnet からの受信接続に完全対応します。
5. **マルチアーキテクチャ**：`amd64` と `arm64` をネイティブにサポートします。

### 🎯 ユースケース
*   **API ルーティング**：クローラーや AI API ゲートウェイ（Grok、ChatGPT など）を MicroWARP 経由でルーティングし、信頼度の高い Cloudflare IP を利用します。
*   **外向き通信のプライバシー**：WARP をデフォルトの外向きネットワークとして使用し、サーバーの実 IP を隠して直接追跡されることを防ぎます。
*   **サイドカープロキシ**：超軽量な Docker Sidecar ネットワークゲートウェイとして最適です。

### 📦 クイックスタート

ポート `1080` をマッピングし、`NET_ADMIN` 権限を付与します。次の `docker-compose.yml` を作成してください。

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
      - warp-data:/etc/wireguard # Keep account data to avoid rate limits

volumes:
  warp-data:
```

コンテナを起動します。
```bash
docker compose up -d
```

### ⚙️ 高度な設定

MicroWARP では、メモリ使用量を 800KB に保ちながら、環境変数で設定をカスタマイズできます。

```yaml
    environment:
      - BIND_ADDR=0.0.0.0     # Bind address
      - BIND_PORT=1080        # Custom SOCKS5 port
      - SOCKS_USER=admin      # Enable authentication
      - SOCKS_PASS=123456     # Auth password

      # ⚠️ Port Hopping (Mitigating Datacenter QoS):
      # If your VPS is in a datacenter (e.g., DMIT, AWS) where UDP 2408 is throttled or blocked,
      # use port 4500 (standard IPsec NAT-T) to bypass restrictive firewall rules.
      - ENDPOINT_IP=162.159.192.1:4500
```

---

<a name="chinese"></a>
## 🇨🇳 中国語セクションの日本語訳

Docker で動作する、ミニマルかつ高性能な Cloudflare WARP SOCKS5 プロキシです。
サーバー向けに、極めて少ないリソースで外向きネットワークを分離する仕組みを提供します。

### 🌟 MicroWARP を選ぶ理由

一般的な WARP イメージの多く（例：`caomingjun/warp`）は、Cloudflare 公式の `warp-cli` デーモンに依存しています。この方式では通常、メモリ使用量が大きくなり（約 **150MB 以上**）、高並行処理時にはパフォーマンス上のボトルネックが生じる可能性があります。

**MicroWARP** は異なる基盤アーキテクチャを採用しています。
1. **カーネルレベルの WireGuard**：Linux ネイティブのカーネル空間 `wg0` インターフェースでトラフィックを処理し、CPU オーバーヘッドをほぼゼロにします。
2. **MicroSOCKS エンジン**：Pure C で実装された `microsocks` サーバーを使用し、リソース消費を大幅に削減します。
3. **極めて少ないメモリ使用量**：高並行処理時でも **5MB 未満**（常駐時は実測で約 800KB）に収まり、リソースが限られたクラウドサーバー向けに設計されています。
4. **Tailscale にネイティブ対応**：戻り経路を適切に維持し、全トラフィックの引き受けによる非対称ルーティングのブラックホールを解消して、遠隔ネットワークからの直接接続に対応します。
5. **マルチアーキテクチャ対応**：`amd64` と `arm64`（ARM マシンを含む）をネイティブにサポートします。

### 🎯 代表的なユースケース
**⚠️ 注意：本プロジェクトはサーバーサイド向けであり、個人 PC 用のローカルプロキシソフトウェアではありません。**

1. **API ネットワークルーティング**：サーバー上のクローラーや大規模モデル API ゲートウェイ（Grok / ChatGPT など）に、安定した Cloudflare の外向き IP を提供します。
2. **サーバーの外向き通信におけるプライバシー**：MicroWARP をサーバーの外向きゲートウェイとして接続し、VPS の実 IP を隠して、追跡目的のスキャンを受けるリスクを低減します。
3. **マイクロサービスの Sidecar**：リソース使用量が極めて少ないため、Docker Sidecar コンテナとして特定のバックエンドサービスに独立した外向きネットワークを提供する用途に適しています。

### 📦 クイックスタート

ポート `1080` をマッピングし、コンテナに `NET_ADMIN` 権限を付与するだけです。次の `docker-compose.yml` を作成してください。

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
    volumes:
      - warp-data:/etc/wireguard # 持久化保存账号凭证

volumes:
  warp-data:
```

コンテナを起動します。
```bash
docker compose up -d
```

### ⚙️ 高度な設定：認証とネットワーク接続の最適化

MicroWARP は環境変数によるパラメーターのカスタマイズに対応しています。

```yaml
    environment:
      - BIND_ADDR=0.0.0.0     # 监听地址 (默认 0.0.0.0)
      - BIND_PORT=1080        # 监听端口 (默认 1080)
      - SOCKS_USER=admin      # SOCKS5 认证用户名 (留空则为无密码模式)
      - SOCKS_PASS=123456     # SOCKS5 认证密码
      - GH_PROXY=https://github.ednovas.xyz # 代理 wgcf 二进制下载地址

      # ⚠️ 网络连通性优化 (Port Hopping)
      # 针对部分对 UDP 2408 端口存在 QoS 限制的机房（如 DMIT、搬瓦工等）。
      # 可将端口修改为 4500 (标准 IPsec NAT-T 端口) 规避审查特征，提升连通率。
      - ENDPOINT_IP=162.159.192.1:4500
```

### 🚀 応用：HTTP プロキシへの変換

Unix 哲学に基づき、基盤イメージには極限まで軽量に保つための HTTP 解析エンジンを組み込んでいません。HTTP プロキシが必要な場合は、`gost` を使用してローカル変換することを推奨します。
```bash
nohup gost -F=socks5://admin:123456@127.0.0.1:1080 -L=http://127.0.0.1:8081 > /dev/null 2>&1 &
```
*注：ホスト側で DNS を解決し、起動時の名前解決タイムアウトを避けるため、必ず `socks5://` を使用し、`socks5h://` は使用しないでください。*

---

*__LinuxDo__ コミュニティに心より感謝します* ❤️

---

## 📈 Star History

<a href="https://star-history.com/#ccbkkb/MicroWARP&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=ccbkkb/MicroWARP&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=ccbkkb/MicroWARP&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=ccbkkb/MicroWARP&type=Date" />
  </picture>
</a>
