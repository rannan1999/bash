#!/usr/bin/env bash

# ==================== 【在此處填寫你的自訂變數】 ====================
export UUID=${UUID:-'faacf142-dee8-48c2-8558-641123eb939c'}
PORT=${PORT:-3000}

# 哪吒探針設定
NEZHA_SERVER=${NEZHA_SERVER:-"nezha.mingfei1981.eu.org"}
NEZHA_PORT=${NEZHA_PORT:-"443"}
NEZHA_KEY=${NEZHA_KEY:-"7LHjlPcj7gRgOrTCxl"}

# Cloudflare Argo 隧道設定
ARGO_DOMAIN=${ARGO_DOMAIN:-"adkynet.mingfei1982.eu.org"}
# 直接填入你隧道的 Token (留空則會自動切換為臨時隧道模式)
ARGO_TOKEN=${ARGO_TOKEN:-"eyJhIjoiMGYxNTA1MzUwOTRjNDhlZjNmM2ZjZTA2M2E4N2M1N2YiLCJ0IjoiMjkxNzNmYjItOTY4Yi00ODhmLWI4OTUtMjAzMzJlODcyYWEwIiwicyI6Ik1UaGxNakkyT0RBdFlXWTVaaTAwWTJRMExXRTBaREV0TVRabU1tVmhPREF6WkdVMyJ9"}

# ECH Server 與 Opera 設定
WSPORT=${WSPORT:-"8001"}
TOKEN=${TOKEN:-"babama123"}
OPERA=${OPERA:-"0"}
COUNTRY=${COUNTRY:-"AM"}

# ---------------- 【雙棧核心控制：各自自定義 V4 / V6】 ----------------
ECH_IPS=${ECH_IPS:-"6"}               # ECH (Cloudflared) 連接邊緣節點的 IP 版本："4" 或 "6"
HY_IPS=${HY_IPS:-"4"}                # HY2 (Hysteria 2) 訂閱與直連使用的 IP 版本："4" 或 "6"
# ------------------------------------------------------------------

# Hysteria 2 其他變數
ENABLE_HY2=${ENABLE_HY2:-"1"}           # 是否啟用 HY2 (1為啟用，0為停用)
HY_PORT=${HY_PORT:-'1130'}             # HY2 監聽埠號
NAME=${NAME:-'MJJ'}                     # 節點自訂名稱
PASSWORD="$UUID"                        # HY2 連線密碼
# ====================================================================

# 1) 建立簡易 HTTP 伺服器監聽 PORT，防止翼手龍面板因沒有監聽而判定容器崩潰
if command -v nc >/dev/null 2>&1; then
    (while true; do echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nOK" | nc -l -p "$PORT"; done) >/dev/null 2>&1 &
    disown
fi

# 隨機埠號生成函式
get_free_port() {
    echo $(( ( RANDOM % 20000 ) + 10000 ))
}

# 雙棧優化下載函式：靜默重導向，失敗自動切換 V4
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

# 核心功能：3 分鐘後自動刪除所有下載的執行檔與配置 (無痕清理)
auto_delete_files() {
    (
        sleep 180
        rm -rf "./ech-server-linux" "./opera-linux" "./cloudflared-linux" "./iccagent" "./nezha.yaml" \
               "./icchy" "./server.key" "./server.crt" "./hy_config.json" "./sub.txt" "./sub_base64.txt" \
               core core.* >/dev/null 2>&1
    ) &
    disown
}

# 🌟【修正點】移除 echo 提示，並將 DNS 修改時的錯誤輸出重導向到 /dev/null 防止容器權限報錯
rm -f /etc/resolv.conf >/dev/null 2>&1 || true
echo "nameserver 1.1.1.1" > /etc/resolv.conf 2>/dev/null || true
echo "nameserver 2606:4700:4700::1111" >> /etc/resolv.conf 2>/dev/null || true

if [[ "$ECH_IPS" != "4" && "$ECH_IPS" != "6" ]]; then exit 1; fi
if [[ "$HY_IPS" != "4" && "$HY_IPS" != "6" ]]; then exit 1; fi

# 檢測系統架構
ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
    OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64"
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    NEZHA_URL="https://github.com/babama1001980/good/releases/download/npc/arm64agent"
    HY2_URL="https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.5/hysteria-linux-arm64"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" || "$ARCH" == "x64" ]]; then
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
    OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64"
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    NEZHA_URL="https://github.com/babama1001980/good/releases/download/npc/amd64agent"
    HY2_URL="https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.5/hysteria-linux-amd64"
else
    exit 1
fi

# 🌟【修正點】移除了下載提示 echo
download_file "$ECH_URL" "./ech-server-linux"
download_file "$OPERA_URL" "./opera-linux"
download_file "$CLOUDFLARED_URL" "./cloudflared-linux"

if [[ -n "$NEZHA_SERVER" && -n "$NEZHA_KEY" ]]; then
    download_file "$NEZHA_URL" "./iccagent"
fi

if [[ "$ENABLE_HY2" == "1" ]]; then
    download_file "$HY2_URL" "./icchy"
fi

if [[ -z "$WSPORT" ]]; then
    ECHPORT=$(get_free_port)
else
    ECHPORT=$WSPORT
fi

# ====== 1) 哪吒探針啟動邏輯 ======
if [[ -f "./iccagent" && -n "$NEZHA_SERVER" && -n "$NEZHA_KEY" ]]; then
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    if [[ -n "$NEZHA_PORT" ]]; then
        NEZHA_TLS=""
        if [[ " ${tlsPorts[*]} " =~ " ${NEZHA_PORT} " ]]; then NEZHA_TLS="--tls"; fi
        ./iccagent -s "${NEZHA_SERVER}:${NEZHA_PORT}" -p "${NEZHA_KEY}" ${NEZHA_TLS} >/dev/null 2>&1 &
        disown
    else
        SERVER_HOST_PORT="${NEZHA_SERVER##*:}"
        IS_TLS=false
        if [[ " ${tlsPorts[*]} " =~ " ${SERVER_HOST_PORT} " ]]; then IS_TLS=true; fi
        cat > nezha.yaml << EOF
client_secret: ${NEZHA_KEY}
server: ${NEZHA_SERVER}
tls: ${IS_TLS}
uuid: ${UUID}
EOF
        ./iccagent -c nezha.yaml >/dev/null 2>&1 &
        disown
    fi
fi

# ====== 2) Opera Proxy 啟動 ======
if [[ "$OPERA" == "1" && -f "./opera-linux" ]]; then
    COUNTRY_UPPER="${COUNTRY^^}"
    operaport=$(get_free_port)
    ./opera-linux -country "${COUNTRY_UPPER:-AM}" -socks-mode -bind-address "127.0.0.1:$operaport" >/dev/null 2>&1 &
    disown
fi

# ====== 3) ECH Server 啟動 ======
if [[ -f "./ech-server-linux" ]]; then
    sleep 1
    ECH_ARGS=("-l" "ws://0.0.0.0:$ECHPORT")
    if [[ -n "$TOKEN" ]]; then ECH_ARGS+=("-token" "$TOKEN"); fi
    if [[ "$OPERA" == "1" ]]; then ECH_ARGS+=("-f" "socks5://127.0.0.1:$operaport"); fi
    ./ech-server-linux "${ECH_ARGS[@]}" >/dev/null 2>&1 &
    disown
fi

# ====== 4) Hysteria 2 啟動與憑證生成 ======
if [[ "$ENABLE_HY2" == "1" && -f "./icchy" ]]; then
    openssl ecparam -name prime256v1 -genkey -noout -out server.key >/dev/null 2>&1
    openssl req -new -x509 -key server.key -out server.crt -subj "/CN=www.bing.com" -days 36500 >/dev/null 2>&1

    cat > hy_config.json << EOF
{
  "listen": ":$HY_PORT",
  "tls": { "cert": "server.crt", "key": "server.key" },
  "auth": { "type": "password", "password": "$PASSWORD" }
}
EOF
    ./icchy server -c hy_config.json > /dev/null 2>&1 &
    disown

    (
        sleep 15
        if [[ "$HY_IPS" == "6" ]]; then
            HOST_IP=$(curl -6 -s ipv6.ip.sb || curl -6 -s https://api6.ipify.org || curl -s ipv6.ip.sb)
            if [[ ! "$HOST_IP" =~ ^\[.*\]$ && -n "$HOST_IP" ]]; then HOST_IP="[$HOST_IP]"; fi
        else
            HOST_IP=$(curl -4 -s ipv4.ip.sb || curl -4 -s https://api.ipify.org || curl -s ipv4.ip.sb)
        fi
        
        ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed 's/ /_/g')
        cat > sub.txt << EOF
start install success
=== HY2 ===
hysteria2://$PASSWORD@$HOST_IP:$HY_PORT/?insecure=1&sni=www.bing.com#$NAME-HY-$ISP
EOF
        base64 -w0 sub.txt > sub_base64.txt 2>/dev/null || base64 sub.txt > sub_base64.txt
    ) &
    disown
fi

auto_delete_files

# ====== 5) Cloudflared 隧道啟動 ======
if [[ -f "./cloudflared-linux" ]]; then
    ./cloudflared-linux update >/dev/null 2>&1 || true
    if [[ -n "$ARGO_TOKEN" ]]; then
        exec ./cloudflared-linux --edge-ip-version "$ECH_IPS" --protocol http2 tunnel run --token "$ARGO_TOKEN" >/dev/null 2>&1
    else
        metricsport=$(get_free_port)
        ./cloudflared-linux --edge-ip-version "$ECH_IPS" --protocol http2 tunnel --url "127.0.0.1:$ECHPORT" --metrics "0.0.0.0:$metricsport" >/dev/null 2>&1 &
        disown
        tail -f /dev/null
    fi
else
    tail -f /dev/null
fi