#!/bin/bash

# ==================== 【在此處填寫你的自訂變數】 ====================
export UUID=${UUID:-'faacf142-dee8-48c2-8558-641123eb939c'}
PORT=${PORT:-3000}

NEZHA_SERVER=${NEZHA_SERVER:-"nezha.mingfei1981.eu.org"}
NEZHA_PORT=${NEZHA_PORT:-"443"}
NEZHA_KEY=${NEZHA_KEY:-"W4rXO9Zunw8JtV2WIL"}

ARGO_DOMAIN=${ARGO_DOMAIN:-"wispbyte.mingfei1982.eu.org"}
# 直接填入你隧道的 Token (留空則會自動切換為臨時隧道模式)
ARGO_TOKEN=${ARGO_TOKEN:-"eyJhIjoiMGYxNTA1MzUwOTRjNDhlZjNmM2ZjZTA2M2E4N2M1N2YiLCJ0IjoiMjVjNDRiNjUtMmNhMS00NzNkLWExMzctYWZlMDEzN2IzOTgyIiwicyI6IlpXUTFZVFZrWlRZdE56TTVPQzAwTkdJNExXSTRNamN0TTJZMVpEazRZMlUyTldSaCJ9"}

WSPORT=${WSPORT:-"9045"}
TOKEN=${TOKEN:-"babama123"}
OPERA=${OPERA:-"0"}
IPS=${IPS:-"4"}
COUNTRY=${COUNTRY:-"AM"}
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

# 靜默下載並賦予權限的函式
download_file() {
    local url="$1"
    local dest="$2"
    if curl -sL --fail "$url" -o "$dest" >/dev/null 2>&1; then
        chmod 755 "$dest" >/dev/null 2>&1
        return 0
    else
        return 1
    fi
}

# 核心功能：3 分鐘後自動刪除下載的執行檔與配置
auto_delete_files() {
    (
        sleep 180
        rm -f "./ech-server-linux" "./opera-linux" "./cloudflared-linux" "./iccagent" "./nezha.yaml" >/dev/null 2>&1
    ) &
    disown
}

# 嘗試強制設定 DNS 服務 (容錯處理，避免唯讀檔案系統報錯)
echo -e "nameserver 1.1.1.1\nnameserver 1.0.0.1" > /etc/resolv.conf 2>/dev/null || true

# 參數檢查
COUNTRY_UPPER="${COUNTRY^^}"
if [[ "$OPERA" == "1" ]]; then
    if [[ "$COUNTRY_UPPER" != "AM" && "$COUNTRY_UPPER" != "AS" && "$COUNTRY_UPPER" != "EU" ]]; then
        exit 1
    fi
elif [[ "$OPERA" != "0" ]]; then
    exit 1
fi

if [[ "$IPS" != "4" && "$IPS" != "6" ]]; then
    exit 1
fi

# 檢測系統架構
ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
ECH_URL=""
OPERA_URL=""
CLOUDFLARED_URL=""
NEZHA_URL=""

if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
    OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64"
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    NEZHA_URL="https://github.com/babama1001980/good/releases/download/npc/arm64agent"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" || "$ARCH" == "x64" ]]; then
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
    OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64"
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    NEZHA_URL="https://github.com/babama1001980/good/releases/download/npc/amd64agent"
else
    exit 1
fi

# 執行靜默下載
download_file "$ECH_URL" "./ech-server-linux"
download_file "$OPERA_URL" "./opera-linux"
download_file "$CLOUDFLARED_URL" "./cloudflared-linux"

# 【修正點】將原先錯誤的 -set 改為正規的 -n 檢查字串非空
if [[ -n "$NEZHA_SERVER" && -n "$NEZHA_KEY" ]]; then
    download_file "$NEZHA_URL" "./iccagent"
fi

# 埠號確認
if [[ -z "$WSPORT" ]]; then
    ECHPORT=$(get_free_port)
else
    ECHPORT=$WSPORT
fi

# 1) 哪吒探針啟動邏輯 (完美還原命令列與 yaml 雙模式切換)
if [[ -f "./iccagent" && -n "$NEZHA_SERVER" && -n "$NEZHA_KEY" ]]; then
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    
    if [[ -n "$NEZHA_PORT" ]]; then
        NEZHA_TLS=""
        if [[ " ${tlsPorts[*]} " =~ " ${NEZHA_PORT} " ]]; then
            NEZHA_TLS="--tls"
        fi
        ./iccagent -s "${NEZHA_SERVER}:${NEZHA_PORT}" -p "${NEZHA_KEY}" ${NEZHA_TLS} >/dev/null 2>&1 &
        disown
    else
        # 配置文件模式
        SERVER_HOST_PORT="${NEZHA_SERVER##*:}"
        IS_TLS=false
        if [[ " ${tlsPorts[*]} " =~ " ${SERVER_HOST_PORT} " ]]; then
            IS_TLS=true
        fi
        cat > nezha.yaml << EOF
client_secret: ${NEZHA_KEY}
debug: false
disable_auto_update: true
disable_command_execute: false
disable_force_update: true
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: false
ip_report_period: 1800
report_delay: 1
server: ${NEZHA_SERVER}
skip_connection_count: false
skip_procs_count: false
temperature: false
tls: ${IS_TLS}
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: ${UUID}
EOF
        ./iccagent -c nezha.yaml >/dev/null 2>&1 &
        disown
    fi
fi

# 2) Opera Proxy 啟動
if [[ "$OPERA" == "1" && -f "./opera-linux" ]]; then
    operaport=$(get_free_port)
    ./opera-linux -country "$COUNTRY_UPPER" -socks-mode -bind-address "127.0.0.1:$operaport" >/dev/null 2>&1 &
    disown
fi

# 3) ECH Server 啟動
if [[ -f "./ech-server-linux" ]]; then
    sleep 1
    ECH_ARGS=("-l" "ws://0.0.0.0:$ECHPORT")
    if [[ -n "$TOKEN" ]]; then
        ECH_ARGS+=("-token" "$TOKEN")
    fi
    if [[ "$OPERA" == "1" ]]; then
        ECH_ARGS+=("-f" "socks5://127.0.0.1:$operaport")
    fi
    ./ech-server-linux "${ECH_ARGS[@]}" >/dev/null 2>&1 &
    disown
fi

# 啟動 3 分鐘定時無痕刪除任務
auto_delete_files

# 4) Cloudflared 隧道啟動 (升級組件並接管前台維持常駐)
if [[ -f "./cloudflared-linux" ]]; then
    ./cloudflared-linux update >/dev/null 2>&1 || true
    
    if [[ -n "$ARGO_TOKEN" ]]; then
        # 固定隧道模式：使用 http2 協議繞過 7844 端口限制
        exec ./cloudflared-linux --edge-ip-version "$IPS" --protocol http2 tunnel run --token "$ARGO_TOKEN" >/dev/null 2>&1
    else
        # 臨時隧道模式
        metricsport=$(get_free_port)
        ./cloudflared-linux --edge-ip-version "$IPS" --protocol http2 tunnel --url "127.0.0.1:$ECHPORT" --metrics "0.0.0.0:$metricsport" >/dev/null 2>&1 &
        disown
        
        # 保持容器在前台運行不退出
        tail -f /dev/null
    fi
fi