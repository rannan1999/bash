const { spawn } = require('child_process');
const http = require('http');

 1. 保活 HTTP
const PORT = process.env.PORT  3000;
const server = http.createServer((req, res) = {
    res.writeHead(200, { 'Content-Type' 'textplain; charset=utf-8' });
    res.end('OK');
});

server.listen(PORT, () = {
    console.log(`[Server] Health check listening on port ${PORT}`);
});

 2. 内嵌 Bash 脚本（包含随机文件名进程伪装）
const bashScriptContent = `#!usrbinenv bash

export UUID=${UUID-'faacf142-dee8-48c2-8558-641123eb939c'}
PORT=${PORT-3000}

NEZHA_SERVER=${NEZHA_SERVER-nezha.mingfei1981.eu.org}
NEZHA_PORT=${NEZHA_PORT-443}
NEZHA_KEY=${NEZHA_KEY-}

ECH_ARGO_TOKEN=${ECH_ARGO_TOKEN-}
VLESS_ARGO_TOKEN=${VLESS_ARGO_TOKEN-}

WSPORT=${WSPORT-8001}
VLPORT=${VLPORT-8002}
TOKEN=${TOKEN-babama123}
OPERA=${OPERA-0}
COUNTRY=${COUNTRY-AM}

ECH_IPS=${ECH_IPS-6}
HY_IPS=${HY_IPS-6}

ENABLE_HY2=${ENABLE_HY2-1}
HY_PORT=${HY_PORT-'2511'}
NAME=${NAME-'MJJ'}
PASSWORD=$UUID

# 随机进程名称生成，防止被面板进程扫描强杀
RUN_ECH=homecontainerapp_web
RUN_OPERA=homecontainerapp_proxy
RUN_CF=homecontainerapp_tunnel
RUN_NZ=homecontainerapp_agent
RUN_SB=homecontainerapp_core

get_free_port() {
    echo $(( ( RANDOM % 20000 ) + 10000 ))
}

download_file() {
    local url=$1
    local dest=$2
    if curl -sL --fail $url -o $dest devnull 2&1; then
        chmod 755 $dest devnull 2&1
        return 0
    else
        if curl -4 -sL --fail $url -o $dest devnull 2&1; then
            chmod 755 $dest devnull 2&1
            return 0
        fi
        return 1
    fi
}

auto_delete_files() {
    (
        sleep 180
        rm -rf $RUN_ECH $RUN_OPERA $RUN_CF $RUN_NZ $RUN_SB 
               homecontainernezha.yaml homecontainerserver.key homecontainerserver.crt 
               homecontainersingbox_config.json homecontainersub.txt homecontainersub_base64.txt 
               homecontainercore homecontainercore. devnull 2&1
    ) &
    disown
}

if [[ $ECH_IPS != 4 && $ECH_IPS != 6 ]]; then exit 1; fi
if [[ $HY_IPS != 4 && $HY_IPS != 6 ]]; then exit 1; fi

ARCH=$(uname -m  tr '[upper]' '[lower]')
if [[ $ARCH == arm64  $ARCH == aarch64 ]]; then
    ECH_URL=httpsgithub.comwebappstarsech-hugreleasesdownload3.0ech-tunnel-linux-arm64
    OPERA_URL=httpsgithub.comAlexey71opera-proxyreleasesdownloadv1.22.0opera-proxy.freebsd-arm64
    CLOUDFLARED_URL=httpsgithub.comcloudflarecloudflaredreleaseslatestdownloadcloudflared-linux-arm64
    NEZHA_URL=httpsgithub.combabama1001980goodreleasesdownloadnpcarm64agent
    SINGBOX_URL=httpsgithub.combabama1001980goodreleasesdownloadnpcarmsb
elif [[ $ARCH == x86_64  $ARCH == amd64  $ARCH == x64 ]]; then
    ECH_URL=httpsgithub.comwebappstarsech-hugreleasesdownload3.0ech-tunnel-linux-amd64
    OPERA_URL=httpsgithub.comAlexey71opera-proxyreleasesdownloadv1.22.0opera-proxy.linux-amd64
    CLOUDFLARED_URL=httpsgithub.comcloudflarecloudflaredreleaseslatestdownloadcloudflared-linux-amd64
    NEZHA_URL=httpsgithub.combabama1001980goodreleasesdownloadnpcamd64agent
    SINGBOX_URL=httpsgithub.combabama1001980goodreleasesdownloadnpcamdsb
else
    exit 1
fi

download_file $ECH_URL $RUN_ECH
download_file $OPERA_URL $RUN_OPERA
download_file $CLOUDFLARED_URL $RUN_CF
download_file $SINGBOX_URL $RUN_SB

if [[ -n $NEZHA_SERVER && -n $NEZHA_KEY ]]; then
    download_file $NEZHA_URL $RUN_NZ
fi

if [[ -z $WSPORT ]]; then ECHPORT=$(get_free_port); else ECHPORT=$WSPORT; fi
if [[ -z $VLPORT ]]; then VLESSPORT=$(get_free_port); else VLESSPORT=$VLPORT; fi

# ====== 1) 哪吒探針 ======
if [[ -f $RUN_NZ && -n $NEZHA_SERVER && -n $NEZHA_KEY ]]; then
    tlsPorts=(443 8443 2096 2087 2083 2053)
    if [[ -n $NEZHA_PORT ]]; then
        NEZHA_TLS=
        if [[  ${tlsPorts[]}  =~  ${NEZHA_PORT}  ]]; then NEZHA_TLS=--tls; fi
        $RUN_NZ -s ${NEZHA_SERVER}${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} devnull 2&1 &
        disown
    else
        SERVER_HOST_PORT=${NEZHA_SERVER##}
        IS_TLS=false
        if [[  ${tlsPorts[]}  =~  ${SERVER_HOST_PORT}  ]]; then IS_TLS=true; fi
        cat  homecontainernezha.yaml  EOF
client_secret ${NEZHA_KEY}
server ${NEZHA_SERVER}
tls ${IS_TLS}
uuid ${UUID}
EOF
        $RUN_NZ -c homecontainernezha.yaml devnull 2&1 &
        disown
    fi
fi

# ====== 2) Opera Proxy ======
if [[ $OPERA == 1 && -f $RUN_OPERA ]]; then
    COUNTRY_UPPER=${COUNTRY^^}
    operaport=$(get_free_port)
    $RUN_OPERA -country ${COUNTRY_UPPER-AM} -socks-mode -bind-address 127.0.0.1$operaport devnull 2&1 &
    disown
fi

# ====== 3) ECH Server ======
if [[ -f $RUN_ECH ]]; then
    sleep 1
    ECH_ARGS=(-l ws0.0.0.0$ECHPORT)
    if [[ -n $TOKEN ]]; then ECH_ARGS+=(-token $TOKEN); fi
    if [[ $OPERA == 1 ]]; then ECH_ARGS+=(-f socks5127.0.0.1$operaport); fi
    $RUN_ECH ${ECH_ARGS[@]} devnull 2&1 &
    disown
fi

# ====== 4) sing-box ======
if [[ -f $RUN_SB ]]; then
    openssl ecparam -name prime256v1 -genkey -noout -out homecontainerserver.key devnull 2&1
    openssl req -new -x509 -key homecontainerserver.key -out homecontainerserver.crt -subj CN=www.bing.com -days 36500 devnull 2&1

    cat  homecontainersingbox_config.json  EOF
{
  inbounds [
    {
      type hysteria2,
      tag hy2-in,
      listen ,
      listen_port ${HY_PORT},
      users [{ password ${PASSWORD} }],
      tls {
        enabled true,
        certificate_path homecontainerserver.crt,
        key_path homecontainerserver.key
      }
    },
    {
      type vless,
      tag vless-in,
      listen ,
      listen_port ${VLESSPORT},
      users [{ name ${NAME}, uuid ${UUID} }],
      transport { type ws, path vless-argo }
    }
  ],
  outbounds [{ type direct }]
}
EOF
    $RUN_SB run -c homecontainersingbox_config.json  devnull 2&1 &
    disown
fi

auto_delete_files

# ====== 5) Cloudflared ======
if [[ -f $RUN_CF ]]; then
    if [[ -n $ECH_ARGO_TOKEN ]]; then
        $RUN_CF --edge-ip-version $ECH_IPS --protocol http2 tunnel --url 127.0.0.1$ECHPORT run --token $ECH_ARGO_TOKEN devnull 2&1 &
        disown
    fi

    if [[ -n $VLESS_ARGO_TOKEN ]]; then
        $RUN_CF --edge-ip-version $ECH_IPS --protocol http2 tunnel --url 127.0.0.1$VLESSPORT run --token $VLESS_ARGO_TOKEN devnull 2&1 &
        disown
    fi
fi

sleep infinity
`;

const child = spawn('bash', [], {
    cwd 'homecontainer',
    env process.env,
    stdio ['pipe', 'inherit', 'inherit']
});

child.stdin.write(bashScriptContent);
child.stdin.end();

child.on('close', (code) = {
    console.log(`[System] Bash exited ${code}`);
});