#!/usr/bin/env bash

# ==================== 【在此處填寫你的自訂變數】 ====================
NEZHA_SERVER="nezha.mingfei1981.eu.org"
NEZHA_PORT="443"
NEZHA_KEY=""
ARGO_DOMAIN=""
# 直接填入你隧道的 Token
ARGO_TOKEN=""
WSPORT="${WSPORT:-20678}"
TOKEN="${TOKEN:-babama123}"
OPERA="${OPERA:-0}"
IPS="${IPS:-4}"
# ====================================================================

get_free_port() {
    echo $(( ( RANDOM % 20000 ) + 10000 ))
}

quicktunnel() {
    echo "--- 正在設定 DNS 服務 ---"
    echo "nameserver 1.1.1.1" > /etc/resolv.conf 2>/dev/null || true
    echo "nameserver 1.0.0.1" >> /etc/resolv.conf 2>/dev/null || true

    echo "--- 正在為本地二進制文件賦予執行權限 ---"
    chmod +x ech-server-linux cloudflared-linux opera-linux iccagent 2>/dev/null || true

    echo "--- 正在啟動背景守護服務 ---"

    if [ -z "$WSPORT" ]; then
        WSPORT=$(get_free_port)
    fi
    ECHPORT=$WSPORT

    # ====== 1) 哪吒探針啟動邏輯 ======
    if [ -f "./iccagent" ] && [ -n "$NEZHA_SERVER" ] && [ -n "$NEZHA_KEY" ]; then
        tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
        if [[ " ${tlsPorts[*]} " =~ " ${NEZHA_PORT} " ]]; then
            NEZHA_TLS="--tls"
        else
            NEZHA_TLS=""
        fi

        echo "正在啟動哪吒探針..."
        if [ -n "$NEZHA_PORT" ]; then
            nohup ./iccagent -s "${NEZHA_SERVER}:${NEZHA_PORT}" -p "${NEZHA_KEY}" ${NEZHA_TLS} > /dev/null 2>&1 &
        else
            nohup ./iccagent -s "${NEZHA_SERVER}" -p "${NEZHA_KEY}" ${NEZHA_TLS} > /dev/null 2>&1 &
        fi
        echo "哪吒探針已在背景成功拉起。"
    fi

    # ====== 2) Opera Proxy 啟動 ======
    if [ -f "./opera-linux" ] && [ "$OPERA" = "1" ]; then
        local COUNTRY_UPPER="${COUNTRY^^}"
        operaport=$(get_free_port)
        echo "啟動 Opera Proxy (port: $operaport)..."
        nohup ./opera-linux -country "${COUNTRY_UPPER:-AM}" -socks-mode -bind-address "127.0.0.1:$operaport" > /dev/null 2>&1 &
    fi

    # ====== 3) ECH Server 啟動 ======
    if [ -f "./ech-server-linux" ]; then
        ECH_ARGS=(./ech-server-linux -l "ws://0.0.0.0:$ECHPORT")
        if [ -n "$TOKEN" ]; then ECH_ARGS+=(-token "$TOKEN"); fi
        if [ "$OPERA" = "1" ] && [ -f "./opera-linux" ]; then ECH_ARGS+=(-f "socks5://127.0.0.1:$operaport"); fi
        nohup "${ECH_ARGS[@]}" > /dev/null 2>&1 &
        echo "ECH Server 已在背景啟動。"
    fi

    # ====== 4) Cloudflared 隧道啟動 ======
    if [ -f "./cloudflared-linux" ] && [ -n "$ARGO_TOKEN" ]; then
        echo "正在以【固定隧道安全 Token 模式】啟動..."
        echo "隧道域名: $ARGO_DOMAIN -> 本地 ECH:$ECHPORT"
        
        # 讓 Cloudflared 在前台運行，用於接收日誌並維持翼手龍容器常駐
        exec ./cloudflared-linux --edge-ip-version "$IPS" --protocol quic tunnel run --token "$ARGO_TOKEN"
    else
        echo "警告: 未偵測到有效的 ARGO_TOKEN，轉入阻塞常駐模式。"
        tail -f /dev/null
    fi
}

# ---------------- main ----------------
MODE="${1:-1}"
if [ "$MODE" = "1" ]; then
    quicktunnel
else
    echo "使用非預期模式啟動。"
    exit 1
fi
