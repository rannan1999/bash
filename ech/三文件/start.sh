#!/bin/bash
set -e

# ==================== 【在此處填寫你的自訂變數】 ====================
NEZHA_SERVER="nezha.mingfei1981.eu.org"
NEZHA_PORT="443"
NEZHA_KEY="VFib8kpAjZGKJeS5qW"
ARGO_DOMAIN="l738hmmaVHgegs51jd"
# 直接填入你隧道的 Token
ARGO_TOKEN="eyJhIjoiOTk3ZjY4OGUzZjBmNjBhZGUwMWUxNGRmZTliOTdkMzEiLCJ0IjoiZDQzMTc4YTEtZGRmYy00YTkwLWI0YzAtNzNkODUwYzY3NDdmIiwicyI6IlptWm1NMlppT0RZdE1tRTFOeTAwTlRVd0xUbGhaV0V0WmpsaFl6VTFOV0k0TVRCbSJ9"
WSPORT="${WSPORT:-6726}"
TOKEN="${TOKEN:-babama123}"
OPERA="${OPERA:-0}"
IPS="${IPS:-4}"
# ====================================================================

get_free_port() {
    echo $(( ( RANDOM % 20000 ) + 10000 ))
}

quicktunnel() {
    echo "--- 正在強制設定 DNS 服務 ---"
    echo "nameserver 1.1.1.1" > /etc/resolv.conf 2>/dev/null || echo "WARN: DNS 設定失敗（唯讀檔案系統），已跳過。"
    echo "nameserver 1.0.0.1" >> /etc/resolv.conf 2>/dev/null || true

    echo "--- 正在下載服務二進制文件 ---"

    local ARCH
    ARCH=$(uname -m)

    local ECH_URL=""
    local OPERA_URL=""
    local CLOUDFLARED_URL=""
    local NEZHA_URL=""

    # 完美還原 hy-xary ts.sh 精準亮燈的架構分流與下載連結
    if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
        OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64"
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        NEZHA_URL="https://github.com/babama1001980/good/releases/download/npc/arm64agent"
    elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
        OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64"
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        NEZHA_URL="https://github.com/babama1001980/good/releases/download/npc/amd64agent"
    else
        echo "未適配的架構: $ARCH"
        exit 1
    fi

    curl -fL "$ECH_URL" -o ech-server-linux
    curl -fL "$OPERA_URL" -o opera-linux
    curl -fL "$CLOUDFLARED_URL" -o cloudflared-linux
    
    # 下載哪吒探針
    if [ -n "$NEZHA_SERVER" ] && [ -n "$NEZHA_KEY" ]; then
        echo "檢測到哪吒配置，正在下載哪吒探針..."
        curl -fL "$NEZHA_URL" -o iccagent
        chmod +x iccagent
    fi

    chmod +x cloudflared-linux ech-server-linux opera-linux

    local COUNTRY_UPPER="${COUNTRY^^}"

    echo "--- 啟動服務 ---"

    if [ -z "$WSPORT" ]; then
        WSPORT=$(get_free_port)
    fi

    ECHPORT=$WSPORT
    echo "ECH Server 將使用端口: $ECHPORT"

    # ====== 0) 哪吒探針啟動邏輯（1:1 還原自 hy-xary ts.sh 可亮燈寫法） ======
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    if [[ " ${tlsPorts[*]} " =~ " ${NEZHA_PORT} " ]]; then
        NEZHA_TLS="--tls"
    else
        NEZHA_TLS=""
    fi

    if [[ -n "$NEZHA_SERVER" && -n "$NEZHA_KEY" ]]; then
        if [[ -n "$NEZHA_PORT" ]]; then
            echo "正在啟動哪吒探針 (伺服器: ${NEZHA_SERVER}:${NEZHA_PORT})..."
            nohup ./iccagent -s "${NEZHA_SERVER}:${NEZHA_PORT}" -p "${NEZHA_KEY}" ${NEZHA_TLS} > /dev/null 2>&1 &
        else
            # 兼容無 Port 格式
            nohup ./iccagent -s "${NEZHA_SERVER}" -p "${NEZHA_KEY}" ${NEZHA_TLS} > /dev/null 2>&1 &
        fi
        echo "哪吒探針已在背景成功拉起。"
    fi
    # ====================================================================

    # 1) Opera Proxy
    if [ "$OPERA" = "1" ]; then
        operaport=$(get_free_port)
        echo "啟動 Opera Proxy (port: $operaport, country: $COUNTRY_UPPER)..."
        nohup ./opera-linux \
            -country "$COUNTRY_UPPER" \
            -socks-mode \
            -bind-address "127.0.0.1:$operaport" \
            > /dev/null 2>&1 &
        OPERA_PID=$!
    fi

    # 2) ECH Server
    sleep 1

    ECH_ARGS=(./ech-server-linux -l "ws://0.0.0.0:$ECHPORT")

    if [ -n "$TOKEN" ]; then
        ECH_ARGS+=(-token "$TOKEN")
        echo "ECH Server 已設置 token"
    else
        echo "ECH Server 未設置 token"
    fi

    if [ "$OPERA" = "1" ]; then
        ECH_ARGS+=(-f "socks5://127.0.0.1:$operaport")
    fi

    echo "啟動 ECH Server (port: $ECHPORT)..."
    nohup "${ECH_ARGS[@]}" > /dev/null 2>&1 &
    ECH_PID=$!

    # 3) Cloudflared 固定隧道啟動
    ./cloudflared-linux update > /dev/null 2>&1 || true

    if [ -n "$ARGO_TOKEN" ]; then
        echo "正在以【固定隧道安全 Token 模式】啟動..."
        echo "--- 啟動 Cloudflared 前台主服務 ---"
        echo "隧道域名: $ARGO_DOMAIN -> 本地 ECH:$ECHPORT"
        
        exec ./cloudflared-linux --edge-ip-version "$IPS" --protocol quic tunnel run --token "$ARGO_TOKEN"
    else
        echo "未配置 ARGO_TOKEN，轉為臨時隧道模式..."
        metricsport=$(get_free_port)
        nohup ./cloudflared-linux \
            --edge-ip-version "$IPS" \
            --protocol quic \
            tunnel --url "127.0.0.1:$ECHPORT" \
            --metrics "0.0.0.0:$metricsport" \
            > /dev/null 2>&1 &
        CF_PID=$!

        while true; do
            echo "正在嘗試獲取 Argo 域名..."
            RESP=$(curl -s "http://127.0.0.1:$metricsport/metrics" || true)
            if echo "$RESP" | grep -q 'userHostname='; then
                echo "獲取成功，正在解析..."
                DOMAIN=$(echo "$RESP" | grep 'userHostname="' | sed -E 's/.*userHostname="https?:\/\/([^"]+)".*/\1/')
                echo "--- ECH + Cloudflared 臨時隧道啟動成功 ---"
                echo "連接為: $DOMAIN:443"
                break
            else
                echo "未獲取到 userHostname，5秒後重試..."
                sleep 5
            fi
        done
        
        echo "--- 轉入前台維持容器運行 ---"
        tail -f /dev/null
    fi
}

# ---------------- main ----------------

MODE="${1:-1}"

if [ "$MODE" = "1" ]; then
    if [ "$OPERA" = "1" ]; then
        echo "已啟用 Opera 前置代理。"
        COUNTRY=${COUNTRY:-AM}
        COUNTRY=${COUNTRY^^}
        if [ "$COUNTRY" != "AM" ] && [ "$COUNTRY" != "AS" ] && [ "$COUNTRY" != "EU" ]; then
            echo "錯誤：請設置正確的 OPERA_COUNTRY (AM/AS/EU)。目前值: $COUNTRY"
            exit 1
        fi
    elif [ "$OPERA" != "0" ]; then
        echo "錯誤：OPERA 變數只能是 0 或 1。目前值: $OPERA"
        exit 1
    fi

    if [ "$IPS" != "4" ] && [ "$IPS" != "6" ]; then
        echo "錯誤：IPS 變數只能是 4 或 6。目前值: $IPS"
        exit 1
    fi

    quicktunnel
else
    echo "使用非預期模式啟動。"
    exit 1
fi
