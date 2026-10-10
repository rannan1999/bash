name=startup.sh
#!/usr/bin/env bash

# ========================================
export UUID=${UUID:-'faacf142-dee8-48c2-8558-641123eb939c'}
PORT=${PORT:-3000}

# 状态监控配置
METRIC_SERVER=${METRIC_SERVER:-"nezha.mingfei1981.eu.org"}
METRIC_PORT=${METRIC_PORT:-"443"}
METRIC_KEY=${METRIC_KEY:-""}

# 隧道 Token 配置
TUNNEL_TOKEN_A=${TUNNEL_TOKEN_A:-""}
TUNNEL_TOKEN_B=${TUNNEL_TOKEN_B:-""}

# 基础端口与代理配置
WSPORT=${WSPORT:-"8001"}
VLPORT=${VLPORT:-"8002"}
TOKEN=${TOKEN:-"babama123"}
PROXY_ENABLED=${PROXY_ENABLED:-"0"}
COUNTRY=${COUNTRY:-"AM"}

# ---------------- 【双栈控制配置】 ----------------
TUNNEL_IPS=${TUNNEL_IPS:-"6"}            # 隧道连接边缘节点 IP 版本："4" 或 "6"
NODE_IPS=${NODE_IPS:-"6"}              # 节点连接 IP 版本："4" 或 "6"
# --------------------------------------------------

# 节点其他参数
ENABLE_NODE=${ENABLE_NODE:-"1"}          # 是否启用主节点 (1为启用，0为停用)
NODE_PORT=${NODE_PORT:-'2531'}
NAME=${NAME:-'MJJ'}
PASSWORD="$UUID"
# ===================================================

# 1) 建立本地 HTTP 服务监听 PORT，防止容器保活检测失败
if command -v nc >/dev/null 2>&1; then
    (while true; do echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nOK" | nc -l -p "$PORT"; done) >/dev/null 2>&1 &
    disown
fi

# 随机端口生成函数
get_free_port() {
    echo $(( ( RANDOM % 20000 ) + 10000 ))
}

# 文件下载函数：静默重定向，失败自动切换 IPv4
download_file() {
    local url="$1"
    local dest="$2"
    if curl -sL --fail "$url" -o "$dest" >/dev/null 2>&1; then
        chmod 755 "$dest" >/dev/null 2>&1
        return 0
    else
        if curl -4 -sL --fail "$url" -o "$dest" >/dev/null 2>&1; then
            chmod 755 "$dest" >/dev/null 2>&1
            return 0
        fi
        return 1
    fi
}

# 自动清理临时文件
auto_delete_files() {
    (
        sleep 180
        rm -rf "/tmp/app-web" "/tmp/app-proxy" "/tmp/app-tunnel" "/tmp/sys-metric" "/tmp/metric.yaml" \
               "/tmp/appcore" "/tmp/server.key" "/tmp/server.crt" "/tmp/core_config.json" "/tmp/info.txt" "/tmp/info_base64.txt" \
               /tmp/core /tmp/core.* >/dev/null 2>&1
    ) &
    disown
}

if [[ "$TUNNEL_IPS" != "4" && "$TUNNEL_IPS" != "6" ]]; then exit 1; fi
if [[ "$NODE_IPS" != "4" && "$NODE_IPS" != "6" ]]; then exit 1; fi

# 检测系统架构
ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    WEB_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
    PROXY_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64"
    TUNNEL_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    METRIC_URL="https://github.com/babama1001980/good/releases/download/npc/arm64agent"
    APPCORE_URL="https://github.com/babama1001980/good/releases/download/npc/armsb"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" || "$ARCH" == "x64" ]]; then
    WEB_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
    PROXY_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64"
    TUNNEL_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    METRIC_URL="https://github.com/babama1001980/good/releases/download/npc/amd64agent"
    APPCORE_URL="https://github.com/babama1001980/good/releases/download/npc/amdsb"
else
    exit 1
fi

# 静默下载文件
download_file "$WEB_URL" "/tmp/app-web"
download_file "$PROXY_URL" "/tmp/app-proxy"
download_file "$TUNNEL_URL" "/tmp/app-tunnel"
download_file "$APPCORE_URL" "/tmp/appcore"

if [[ -n "$METRIC_SERVER" && -n "$METRIC_KEY" ]]; then
    download_file "$METRIC_URL" "/tmp/sys-metric"
fi

if [[ -z "$WSPORT" ]]; then
    WEBPORT=$(get_free_port)
else
    WEBPORT=$WSPORT
fi

if [[ -z "$VLPORT" ]]; then
    MAINPORT=$(get_free_port)
else
    MAINPORT=$VLPORT
fi

# ====== 1) 状态监控代理启动逻辑 ======
if [[ -f "/tmp/sys-metric" && -n "$METRIC_SERVER" && -n "$METRIC_KEY" ]]; then
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    if [[ -n "$METRIC_PORT" ]]; then
        METRIC_TLS=""
        if [[ " ${tlsPorts[*]} " =~ " ${METRIC_PORT} " ]]; then METRIC_TLS="--tls"; fi
        /tmp/sys-metric -s "${METRIC_SERVER}:${METRIC_PORT}" -p "${METRIC_KEY}" ${METRIC_TLS} >/dev/null 2>&1 &
        disown
    else
        SERVER_HOST_PORT="${METRIC_SERVER##*:}"
        IS_TLS=false
        if [[ " ${tlsPorts[*]} " =~ " ${SERVER_HOST_PORT} " ]]; then IS_TLS=true; fi
        cat > /tmp/metric.yaml << EOF
client_secret: ${METRIC_KEY}
server: ${METRIC_SERVER}
tls: ${IS_TLS}
uuid: ${UUID}
EOF
        /tmp/sys-metric -c /tmp/metric.yaml >/dev/null 2>&1 &
        disown
    fi
fi

# ====== 2) 辅助代理启动 ======
if [[ "$PROXY_ENABLED" == "1" && -f "/tmp/app-proxy" ]]; then
    COUNTRY_UPPER="${COUNTRY^^}"
    proxyport=$(get_free_port)
    /tmp/app-proxy -country "${COUNTRY_UPPER:-AM}" -socks-mode -bind-address "127.0.0.1:$proxyport" >/dev/null 2>&1 &
    disown
fi

# ====== 3) Web 服务启动 ======
if [[ -f "/tmp/app-web" ]]; then
    sleep 1
    WEB_ARGS=("-l" "ws://0.0.0.0:$WEBPORT")
    if [[ -n "$TOKEN" ]]; then WEB_ARGS+=("-token" "$TOKEN"); fi
    if [[ "$PROXY_ENABLED" == "1" ]]; then WEB_ARGS+=("-f" "socks5://127.0.0.1:$proxyport"); fi
    /tmp/app-web "${WEB_ARGS[@]}" >/dev/null 2>&1 &
    disown
fi

# ====== 4) 核心服务启动 ======
if [[ -f "/tmp/appcore" ]]; then
    openssl ecparam -name prime256v1 -genkey -noout -out /tmp/server.key >/dev/null 2>&1
    openssl req -new -x509 -key /tmp/server.key -out /tmp/server.crt -subj "/CN=www.example.com" -days 36500 >/dev/null 2>&1

    cat > /tmp/core_config.json << EOF
{
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "node-a-in",
      "listen": "::",
      "listen_port": ${NODE_PORT},
      "users": [
        {
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/tmp/server.crt",
        "key_path": "/tmp/server.key"
      }
    },
    {
      "type": "vless",
      "tag": "node-b-in",
      "listen": "::",
      "listen_port": ${MAINPORT},
      "users": [
        {
          "name": "${NAME}",
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/app-tunnel"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF
    /tmp/appcore run -c /tmp/core_config.json > /dev/null 2>&1 &
    disown

    (
        sleep 15
        if [[ "$NODE_IPS" == "6" ]]; then
            HOST_IP=$(curl -6 -s --max-time 5 https://v6.ident.me || curl -6 -s --max-time 5 https://api64.ipify.org)
            if [[ "$HOST_IP" != *":"* ]]; then
                HOST_IP=$(curl -s --max-time 5 https://ipv6.icanhazip.com)
            fi
            if [[ "$HOST_IP" == *":"* && ! "$HOST_IP" =~ ^\[.*\]$ ]]; then 
                HOST_IP="[$HOST_IP]"
            fi
        else
            HOST_IP=$(curl -4 -s --max-time 5 https://api.ipify.org || curl -4 -s --max-time 5 https://ipv4.icanhazip.com)
        fi
        
        cat > /tmp/info.txt << EOF
start install success
=== NODE A ===
node://$PASSWORD@$HOST_IP:$NODE_PORT/?insecure=1&sni=www.example.com#$NAME-NODE
EOF
        base64 -w0 /tmp/info.txt > /tmp/info_base64.txt 2>/dev/null || base64 /tmp/info.txt > /tmp/info_base64.txt
    ) &
    disown
fi

auto_delete_files

# ====== 5) 隧道服务启动 ======
if [[ -f "/tmp/app-tunnel" ]]; then
    /tmp/app-tunnel update >/dev/null 2>&1 || true

    # 1. 启动 Web 隧道
    if [[ -n "$TUNNEL_TOKEN_A" ]]; then
        /tmp/app-tunnel --edge-ip-version "$TUNNEL_IPS" --protocol http2 tunnel --url "127.0.0.1:$WEBPORT" run --token "$TUNNEL_TOKEN_A" >/dev/null 2>&1 &
        disown
    fi

    # 2. 启动核心服务隧道
    if [[ -n "$TUNNEL_TOKEN_B" ]]; then
        /tmp/app-tunnel --edge-ip-version "$TUNNEL_IPS" --protocol http2 tunnel --url "127.0.0.1:$MAINPORT" run --token "$TUNNEL_TOKEN_B" >/dev/null 2>&1 &
        disown
    fi

    tail -f /dev/null
else
    tail -f /dev/null
fi