#!/usr/bin/env bash

# 设置工作目录
cd "$(dirname "$0")" || exit 1

# ==================== 用户自定义变量配置 ====================
TUIC_PORT="${TUIC_PORT:-8082}"                                        # TUIC 直连端口（留空或0=不部署）
ARGO_PORT="${ARGO_PORT:-8001}"                                    # 固定隧道回源端口
ARGO_DOMAIN="${ARGO_DOMAIN:-testone.mingfei.de5.net}"                                    # 固定隧道域名
ARGO_AUTH="${ARGO_AUTH:-eyJhIjoiNjgyNWI4YTZjODBhYWQxODlmYWI5ZWEwMDI5YzY2NjgiLCJ0IjoiMDg0MDUxYzctNDE5Yy00MTg1LTlhMTgtNWY2OWE1ZDMxYzg1IiwicyI6Ik16VmpNVGd4TURNdE1HVXpNQzAwTlRVM0xXSmxaakV0WkRjek5XVmhaV05rTkdFMiJ9}"                                        # 固定隧道 Token
ARGO_PROTOCOL="${ARGO_PROTOCOL:-quic}"                            # http2 或 quic
ARGO_CONNECTIONS="${ARGO_CONNECTIONS:-1}"                         # 隧道连接数量
CFIP="${CFIP:-www.teamviewer.com}"                                # 优选域名
CFPORT="${CFPORT:-443}"
FILE_PATH="${FILE_PATH:-.tmp}"
URL_FILE_PATH="${URL_FILE_PATH:-sub.txt}"
# ==========================================================

DIRECT_PORT="${DIRECT_PORT:-${SERVER_PORT:-$TUIC_PORT}}"
mkdir -p "$FILE_PATH"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $* "
}

# 自动生成或读取固定密码与 UUID
uuid_file="$FILE_PATH/uuid.txt"
tuic_pwd_file="$FILE_PATH/tuic_password.txt"
seed="${MACHINE_SEED:-$(hostname 2>/dev/null || echo "fixed-seed")}"

if [ -f "$uuid_file" ]; then
    UUID=$(cat "$uuid_file")
else
    # 优先使用系统自带 UUID，若无则通过 md5 和 Bash 原生截取生成标准 UUID 格式
    if [ -f /proc/sys/kernel/random/uuid ]; then
        UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        hash=$(echo -n "$seed-uuid" | md5sum | awk '{print $1}')
        UUID="${hash:0:8}-${hash:8:4}-4${hash:12:3}-${hash:15:1}a${hash:16:2}-${hash:18:12}"
    fi
    echo "$UUID" > "$uuid_file"
fi
UUID=$(echo "$UUID" | tr '[:upper:]' '[:lower:]')
XHTTP_PATH="/${UUID}-xhttp"

if [ -f "$tuic_pwd_file" ]; then
    TUIC_PASSWORD=$(cat "$tuic_pwd_file")
else
    TUIC_PASSWORD=$(echo -n "$seed-tuic" | sha256sum | awk '{print substr($1,1,32)}')
    echo "$TUIC_PASSWORD" > "$tuic_pwd_file"
fi

# 架构判定
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    SB_ARCH="arm64"
    XRAY_ARCH="arm64-v8a"
    CF_ARCH="arm64"
else
    SB_ARCH="amd64"
    XRAY_ARCH="64"
    CF_ARCH="amd64"
fi

XRAY_VER="25.1.30"
SINGBOX_VER="1.11.4"

singbox_path="$FILE_PATH/sing-box"
xray_path="$FILE_PATH/xray"
cloudflared_path="$FILE_PATH/cloudflared"

singbox_config_path="$FILE_PATH/singbox_config.json"
xray_config_path="$FILE_PATH/xray_config.json"
cert_path="$FILE_PATH/cert.pem"
key_path="$FILE_PATH/private.key"

# 获取公网IP
get_public_ip() {
    if [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "www.visa.co.jp" ]; then
        echo "$SERVER_IP"
        return
    }
    local ip=""
    ip=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s --max-time 3 https://ipv4.icanhazip.com 2>/dev/null)
    [ -z "$ip" ] && ip="127.0.0.1"
    echo "$ip"
}

# 清理残留进程
pkill -9 -f sing-box 2>/dev/null || true
pkill -9 -f xray 2>/dev/null || true
pkill -9 -f cloudflared 2>/dev/null || true

global_links=()

enable_direct=false
if [ -n "$DIRECT_PORT" ] && [ "$DIRECT_PORT" != "0" ]; then
    enable_direct=true
fi

enable_argo_fixed=false
if [ -n "$ARGO_PORT" ] && [ "$ARGO_PORT" != "0" ] && [ -n "$ARGO_DOMAIN" ] && [ ${#ARGO_AUTH} -gt 30 ]; then
    enable_argo_fixed=true
fi

if [ "$enable_direct" = false ] && [ "$enable_argo_fixed" = false ]; then
    log "[退出] 缺失必要变量，放弃所有部署。"
    exit 0
fi

# ==================== 1. 部署与启动 Sing-box (TUIC) ====================
if [ "$enable_direct" = true ]; then
    if [ ! -f "$singbox_path" ]; then
        log "正在下载 Sing-box v${SINGBOX_VER}..."
        sb_url="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VER}/sing-box-${SINGBOX_VER}-linux-${SB_ARCH}.tar.gz"
        curl -L -o "$FILE_PATH/singbox.tar.gz" "$sb_url"
        tar -xzf "$FILE_PATH/singbox.tar.gz" -C "$FILE_PATH" --wildcards "*/sing-box" --strip-components=1 2>/dev/null || \
        tar -xzf "$FILE_PATH/singbox.tar.gz" -C "$FILE_PATH" sing-box 2>/dev/null
        extracted="$FILE_PATH/sing-box"
        [ -f "$extracted" ] && mv "$extracted" "$singbox_path"
        rm -f "$FILE_PATH/singbox.tar.gz"
    fi
    chmod +x "$singbox_path"

    # 生成自签证书
    if [ ! -f "$key_path" ] || [ ! -f "$cert_path" ]; then
        openssl ecparam -genkey -name prime256v1 -out "$key_path" 2>/dev/null && \
        openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=bing.com" 2>/dev/null
        chmod 600 "$key_path"
    fi

    # 写入 Sing-box 配置文件
    cat > "$singbox_config_path" <<EOF
{
  "log": { "level": "panic" },
  "dns": {
    "servers": [{ "tag": "local-sys-dns", "address": "local", "detour": "direct" }],
    "strategy": "prefer_ipv4",
    "independent_cache": true,
    "cache_capacity": 4096
  },
  "inbounds": [
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": $DIRECT_PORT,
      "users": [{ "uuid": "$UUID", "password": "$TUIC_PASSWORD" }],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$cert_path",
        "key_path": "$key_path"
      }
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct", "udp_fragment": true }],
  "route": { "auto_detect_interface": true, "final": "direct" }
}
EOF

    log "[初始化] 启动 Sing-box TUIC，监听端口: $DIRECT_PORT"
    
    # 后台保活循环运行 Sing-box
    (
        while true; do
            "$singbox_path" run -c "$singbox_config_path" >/dev/null 2>&1
            sleep 3
        done
    ) &

    PUBLIC_IP=$(get_public_ip)
    direct_tuic="tuic://$UUID:$TUIC_PASSWORD@$PUBLIC_IP:$DIRECT_PORT?sni=www.bing.com&alpn=h3&congestion_control=bbr&allowInsecure=1#TUIC_easyshare"
    global_links+=("$direct_tuic")
fi

# ==================== 2. 部署与启动 Xray (Argo 回源) ====================
if [ "$enable_argo_fixed" = true ]; then
    if [ ! -f "$xray_path" ]; then
        log "正在下载 Xray-core v${XRAY_VER}..."
        xray_url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VER}/Xray-linux-${XRAY_ARCH}.zip"
        curl -L -o "$FILE_PATH/xray.zip" "$xray_url"
        python3 -c "import zipfile; zipfile.ZipFile('$FILE_PATH/xray.zip').extract('xray', '$FILE_PATH')" 2>/dev/null || \
        python -c "import zipfile; zipfile.ZipFile('$FILE_PATH/xray.zip').extract('xray', '$FILE_PATH')" 2>/dev/null
        rm -f "$FILE_PATH/xray.zip"
    fi
    chmod +x "$xray_path"

    # 写入 Xray 配置文件
    cat > "$xray_config_path" <<EOF
{
  "log": { "loglevel": "none" },
  "inbounds": [
    {
      "port": $ARGO_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [{ "id": "$UUID" }], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "$XHTTP_PATH", "mode": "auto", "scMaxConcurrentStreams": 16 }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF

    log "[初始化] 启动 Xray 回源，监听端口: $ARGO_PORT"
    
    # 后台保活循环运行 Xray
    (
        while true; do
            "$xray_path" run -c "$xray_config_path" >/dev/null 2>&1
            sleep 3
        done
    ) &

    # ==================== 3. 部署与启动 Cloudflared ====================
    if [ ! -f "$cloudflared_path" ]; then
        log "正在下载 Cloudflared..."
        cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
        curl -L -o "$cloudflared_path" "$cf_url"
    fi
    chmod +x "$cloudflared_path"

    log "[Argo] 启动固定隧道..."
    
    # 后台保活运行 Cloudflared 并实时检测并提取连接节点国家代码
    (
        while true; do
            "$cloudflared_path" tunnel --no-autoupdate --retries 5 --grace-period 1s \
                --protocol "$(echo "$ARGO_PROTOCOL" | tr '[:upper:]' '[:lower:]')" \
                --ha-connections "$ARGO_CONNECTIONS" run --token "$ARGO_AUTH" 2>&1 | while read -r line; do
                clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')
                if echo "$clean_line" | grep -qEi "connIndex=|Registered tunnel connection"; then
                    echo "[Cloudflare CDN] $clean_line"
                fi
            done
            sleep 3
        done
    ) &

    argo_link_h2="vless://$UUID@$CFIP:$CFPORT?encryption=none&security=tls&alpn=h2&sni=$ARGO_DOMAIN&fp=chrome&type=xhttp&mode=auto&host=$ARGO_DOMAIN&path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$XHTTP_PATH'))" 2>/dev/null || echo "$XHTTP_PATH")#h2_argo_easyshare"
    argo_link_h3="vless://$UUID@$CFIP:$CFPORT?encryption=none&security=tls&alpn=h3&sni=$ARGO_DOMAIN&fp=chrome&type=xhttp&mode=auto&host=$ARGO_DOMAIN&path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$XHTTP_PATH'))" 2>/dev/null || echo "$XHTTP_PATH")#h3_argo_easyshare"
    
    global_links+=("$argo_link_h2")
    global_links+=("$argo_link_h3")
fi

# 生成最终 Base64 订阅链接文件
if [ ${#global_links[@]} -gt 0 ]; then
    joined_links=""
    for link in "${global_links[@]}"; do
        if [ -z "$joined_links" ]; then
            joined_links="$link"
        else
            joined_links="$joined_links\r\n"
        fi
    done
    
    base64_sub=$(echo -en "$joined_links" | base64 | tr -d '\n')
    console_formatted="====================== Base64 订阅/链接 ======================\n${base64_sub}\n=============================================================="
    
    echo -e "\n$console_formatted\n"
    echo -e "$console_formatted" > "$URL_FILE_PATH"
    log "[链接] Base64 订阅已写入文件: $URL_FILE_PATH"
fi

# 保持主进程不退出以便接收终止信号
trap 'log "收到停止信号，正在退出..."; pkill -9 -f sing-box; pkill -9 -f xray; pkill -9 -f cloudflared; exit 0' SIGINT SIGTERM

while true; do
    sleep 3600
done