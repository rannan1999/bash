import os
import sys
import subprocess

# 注意：这里去掉了所有 Node 模板字符串转义留下的反斜杠
bash_script_content = """#!/usr/bin/env bash

# ========================================
export UUID=${UUID:-'faacf142-dee8-48c2-8558-641123eb939c'}
PORT=${PORT:-3000}

# 哪吒探針設定
NEZHA_SERVER=${NEZHA_SERVER:-"nezha.mingfei1981.eu.org"}
NEZHA_PORT=${NEZHA_PORT:-"443"}
NEZHA_KEY=${NEZHA_KEY:-""}

# ECH / VLESS Cloudflare Argo 隧道 Token 配置
ECH_ARGO_TOKEN=${ECH_ARGO_TOKEN:-""}
VLESS_ARGO_TOKEN=${VLESS_ARGO_TOKEN:-""}

# ECH Server 與 Opera 設定
WSPORT=${WSPORT:-"8001"}
VLPORT=${VLPORT:-"8002"}
TOKEN=${TOKEN:-"babama123"}
OPERA=${OPERA:-"0"}
COUNTRY=${COUNTRY:-"AM"}

# ---------------- 【雙棧核心控制：各自自定義 V4 / V6】 ----------------
ECH_IPS=${ECH_IPS:-"4"}               # ECH (Cloudflared) 連接邊緣節點的 IP 版本："4" 或 "6"
HY_IPS=${HY_IPS:-"4"}                # HY2 (Hysteria 2) 訂閱與直連使用的 IP 版本："4" 或 "6"
# ------------------------------------------------------------------

# Hysteria 2 / VLESS 其他變數
ENABLE_HY2=${ENABLE_HY2:-"1"}           # 是否啟用 HY2 (1為啟用，0為停用)
HY_PORT=${HY_PORT:-''}
NAME=${NAME:-'MJJ'}
PASSWORD="$UUID"
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

# 核心功能：3 分鐘後自動刪除所有下載的執行檔與配置 (無痕清理已修改為 /tmp/ 路徑)
auto_delete_files() {
    (
        sleep 180
        rm -rf "/tmp/ech-server-linux" "/tmp/opera-linux" "/tmp/cloudflared-linux" "/tmp/iccagent" "/tmp/nezha.yaml" \
               "/tmp/singbox" "/tmp/server.key" "/tmp/server.crt" "/tmp/singbox_config.json" "/tmp/sub.txt" "/tmp/sub_base64.txt" \
               /tmp/core /tmp/core.* >/dev/null 2>&1
    ) &
    disown
}


if [[ "$ECH_IPS" != "4" && "$ECH_IPS" != "6" ]]; then exit 1; fi
if [[ "$HY_IPS" != "4" && "$HY_IPS" != "6" ]]; then exit 1; fi

# 檢測系統架構
ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
    OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64"
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    NEZHA_URL="https://github.com/babama1001980/good/releases/download/npc/arm64agent"
    SINGBOX_URL="https://github.com/babama1001980/good/releases/download/npc/armsb"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" || "$ARCH" == "x64" ]]; then
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
    OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64"
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    NEZHA_URL="https://github.com/babama1001980/good/releases/download/npc/amd64agent"
    SINGBOX_URL="https://github.com/babama1001980/good/releases/download/npc/amdsb"
else
    exit 1
fi

# 執行靜默下載到 /tmp/ 目錄
download_file "$ECH_URL" "/tmp/ech-server-linux"
download_file "$OPERA_URL" "/tmp/opera-linux"
download_file "$CLOUDFLARED_URL" "/tmp/cloudflared-linux"
download_file "$SINGBOX_URL" "/tmp/singbox"

if [[ -n "$NEZHA_SERVER" && -n "$NEZHA_KEY" ]]; then
    download_file "$NEZHA_URL" "/tmp/iccagent"
fi

if [[ -z "$WSPORT" ]]; then
    ECHPORT=$(get_free_port)
else
    ECHPORT=$WSPORT
fi

if [[ -z "$VLPORT" ]]; then
    VLESSPORT=$(get_free_port)
else
    VLESSPORT=$VLPORT
fi

# ====== 1) 哪吒探針啟動邏輯 ======
if [[ -f "/tmp/iccagent" && -n "$NEZHA_SERVER" && -n "$NEZHA_KEY" ]]; then
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    if [[ -n "$NEZHA_PORT" ]]; then
        NEZHA_TLS=""
        if [[ " ${tlsPorts[*]} " =~ " ${NEZHA_PORT} " ]]; then NEZHA_TLS="--tls"; fi
        /tmp/iccagent -s "${NEZHA_SERVER}:${NEZHA_PORT}" -p "${NEZHA_KEY}" ${NEZHA_TLS} >/dev/null 2>&1 &
        disown
    else
        SERVER_HOST_PORT="${NEZHA_SERVER##*:}"
        IS_TLS=false
        if [[ " ${tlsPorts[*]} " =~ " ${SERVER_HOST_PORT} " ]]; then IS_TLS=true; fi
        cat > /tmp/nezha.yaml << EOF
client_secret: ${NEZHA_KEY}
server: ${NEZHA_SERVER}
tls: ${IS_TLS}
uuid: ${UUID}
EOF
        /tmp/iccagent -c /tmp/nezha.yaml >/dev/null 2>&1 &
        disown
    fi
fi

# ====== 2) Opera Proxy 啟動 ======
if [[ "$OPERA" == "1" && -f "/tmp/opera-linux" ]]; then
    COUNTRY_UPPER="${COUNTRY^^}"
    operaport=$(get_free_port)
    /tmp/opera-linux -country "${COUNTRY_UPPER:-AM}" -socks-mode -bind-address "127.0.0.1:$operaport" >/dev/null 2>&1 &
    disown
fi

# ====== 3) ECH Server 啟動 ======
if [[ -f "/tmp/ech-server-linux" ]]; then
    sleep 1
    ECH_ARGS=("-l" "ws://0.0.0.0:$ECHPORT")
    if [[ -n "$TOKEN" ]]; then ECH_ARGS+=("-token" "$TOKEN"); fi
    if [[ "$OPERA" == "1" ]]; then ECH_ARGS+=("-f" "socks5://127.0.0.1:$operaport"); fi
    /tmp/ech-server-linux "${ECH_ARGS[@]}" >/dev/null 2>&1 &
    disown
fi

# ====== 4) sing-box 啟動 (HY2 + VLESS 同時運行) ======
if [[ -f "/tmp/singbox" ]]; then
    openssl ecparam -name prime256v1 -genkey -noout -out /tmp/server.key >/dev/null 2>&1
    openssl req -new -x509 -key /tmp/server.key -out /tmp/server.crt -subj "/CN=www.bing.com" -days 36500 >/dev/null 2>&1

    cat > /tmp/singbox_config.json << EOF
{
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY_PORT},
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
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${VLESSPORT},
      "users": [
        {
          "name": "${NAME}",
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/vless-argo"
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
    /tmp/singbox run -c /tmp/singbox_config.json > /dev/null 2>&1 &
    disown

    (
        sleep 15
        if [[ "$HY_IPS" == "6" ]]; then
            HOST_IP=$(curl -6 -s --max-time 5 https://v6.ident.me || curl -6 -s --max-time 5 https://api64.ipify.org || curl -6 -s --max-time 5 https://speed.cloudflare.com/meta | grep -oE '([a-fA-F0-9]{1,4}:){1,7}[a-fA-F0-9]{1,4}')
            if [[ "$HOST_IP" != *":"* ]]; then
                HOST_IP=$(curl -s --max-time 5 https://ipv6.icanhazip.com)
            fi
            if [[ "$HOST_IP" == *":"* && ! "$HOST_IP" =~ ^\\[.*\\]$ ]]; then 
                HOST_IP="[$HOST_IP]"
            fi
        else
            HOST_IP=$(curl -4 -s --max-time 5 https://api.ipify.org || curl -4 -s --max-time 5 https://ipv4.icanhazip.com)
        fi
        
        ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\\" '{print $26"-"$18}' | sed 's/ /_/g')
        cat > /tmp/sub.txt << EOF
start install success
=== HY2 ===
hysteria2://$PASSWORD@$HOST_IP:$HY_PORT/?insecure=1&sni=www.bing.com#$NAME-HY-$ISP
EOF
        base64 -w0 /tmp/sub.txt > /tmp/sub_base64.txt 2>/dev/null || base64 /tmp/sub.txt > /tmp/sub_base64.txt
    ) &
    disown
fi

auto_delete_files

# ====== 5) Cloudflared 隧道啟動 (分流拉起 ECH 与 VLESS 隧道) ======
if [[ -f "/tmp/cloudflared-linux" ]]; then
    /tmp/cloudflared-linux update >/dev/null 2>&1 || true

    # 1. 拉起 ECH 隧道 (转发 ECH 服务的 WebSocket 端口)
    if [[ -n "$ECH_ARGO_TOKEN" ]]; then
        /tmp/cloudflared-linux --edge-ip-version "$ECH_IPS" --protocol http2 tunnel --url "127.0.0.1:$ECHPORT" run --token "$ECH_ARGO_TOKEN" >/dev/null 2>&1 &
        disown
    fi

    # 2. 拉起 VLESS 隧道 (转发 sing-box 的 VLESS 端口)
    if [[ -n "$VLESS_ARGO_TOKEN" ]]; then
        /tmp/cloudflared-linux --edge-ip-version "$ECH_IPS" --protocol http2 tunnel --url "127.0.0.1:$VLESSPORT" run --token "$VLESS_ARGO_TOKEN" >/dev/null 2>&1 &
        disown
    fi

    tail -f /dev/null
else
    tail -f /dev/null
fi
"""

# 完美对标 Node.js 的 spawn('bash', [], { stdio: ['pipe', 'inherit', 'inherit'] })
try:
    process = subprocess.Popen(
        ['bash'],
        stdin=subprocess.PIPE,
        cwd=os.path.dirname(os.path.abspath(__file__)),
        env=os.environ
    )
    # 写入管道并关闭输入流，触发 bash 逐行执行
    process.communicate(input=bash_script_content.encode('utf-8'))
    sys.exit(process.returncode)
except Exception:
    sys.exit(1)
