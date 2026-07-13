#!/bin/bash

# ==================== 【在此處填寫你的自訂變數】 ====================
PORT=${PORT:-3000}

ARGO_DOMAIN=${ARGO_DOMAIN:-""}
# 直接填入你隧道的 Token (留空則會自動切換為臨時隧道模式)
ARGO_TOKEN=${ARGO_TOKEN:-""}

WSPORT=${WSPORT:-"8001"}
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

# 核心功能：3 分鐘後自動刪除下載的執行檔與配置 (無痕清理已修改為 /tmp/ 路徑)
auto_delete_files() {
    (
        sleep 180
        rm -f "/tmp/ech-server-linux" "/tmp/opera-linux" "/tmp/cloudflared-linux" >/dev/null 2>&1
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

if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
    OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64"
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" || "$ARCH" == "x64" ]]; then
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
    OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64"
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
else
    exit 1
fi

# 執行靜默下載到 /tmp/ 目錄
download_file "$ECH_URL" "/tmp/ech-server-linux"
download_file "$OPERA_URL" "/tmp/opera-linux"
download_file "$CLOUDFLARED_URL" "/tmp/cloudflared-linux"

# 埠號確認
if [[ -z "$WSPORT" ]]; then
    ECHPORT=$(get_free_port)
else
    ECHPORT=$WSPORT
fi

# 1) Opera Proxy 啟動
if [[ "$OPERA" == "1" && -f "/tmp/opera-linux" ]]; then
    operaport=$(get_free_port)
    /tmp/opera-linux -country "$COUNTRY_UPPER" -socks-mode -bind-address "127.0.0.1:$operaport" >/dev/null 2>&1 &
    disown
fi

# 2) ECH Server 啟動
if [[ -f "/tmp/ech-server-linux" ]]; then
    sleep 1
    ECH_ARGS=("-l" "ws://0.0.0.0:$ECHPORT")
    if [[ -n "$TOKEN" ]]; then
        ECH_ARGS+=("-token" "$TOKEN")
    fi
    if [[ "$OPERA" == "1" ]]; then
        ECH_ARGS+=("-f" "socks5://127.0.0.1:$operaport")
    fi
    /tmp/ech-server-linux "${ECH_ARGS[@]}" >/dev/null 2>&1 &
    disown
fi

# 啟動 3 分鐘定時無痕刪除任務
auto_delete_files

# 3) Cloudflared 隧道啟動 (升級組件並接管前台維持常駐)
if [[ -f "/tmp/cloudflared-linux" ]]; then
    /tmp/cloudflared-linux update >/dev/null 2>&1 || true
    
    if [[ -n "$ARGO_TOKEN" ]]; then
        # 固定隧道模式：使用 http2 協議繞過 7844 端口限制
        exec /tmp/cloudflared-linux --edge-ip-version "$IPS" --protocol http2 tunnel run --token "$ARGO_TOKEN" >/dev/null 2>&1
    else
        # 臨時隧道模式
        metricsport=$(get_free_port)
        /tmp/cloudflared-linux --edge-ip-version "$IPS" --protocol http2 tunnel --url "127.0.0.1:$ECHPORT" --metrics "0.0.0.0:$metricsport" >/dev/null 2>&1 &
        disown
        
        # 保持容器在前台運行不退出
        tail -f /dev/null
    fi
fi