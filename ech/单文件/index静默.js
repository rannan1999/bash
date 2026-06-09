const os = require('os');
const fs = require('fs');
const http = require('http');
const { spawn, execSync } = require('child_process');

// ==================== 【在此處填寫你的自訂變數】 ====================
const PORT = parseInt(process.env.PORT || '3000', 10);

const NEZHA_SERVER = process.env.NEZHA_SERVER || "nezha.mingfei1981.eu.org";
const NEZHA_PORT = process.env.NEZHA_PORT || "443";
const NEZHA_KEY = process.env.NEZHA_KEY || "96p44lsGGMTYPJc7aD";

const ARGO_DOMAIN = process.env.ARGO_DOMAIN || "zira.prosinecki.hidns.co";
// 直接填入你的 Argo 隧道 Token
const ARGO_TOKEN = process.env.ARGO_TOKEN || "eyJhIjoiNjgyNWI4YTZjODBhYWQxODlmYWI5ZWEwMDI5YzY2NjgiLCJ0IjoiODViODFiNzYtMGU1OC00OTU0LWEyMDUtMWY5YzUyMDI2NTBkIiwicyI6IlpXUmxNR1ZoTW1JdFltRTRNaTAwTTJNMUxUZzBNbUV0WTJObU0ySTJOelZpWlRWaSJ9";

const WSPORT = process.env.WSPORT || "27328";
const TOKEN = process.env.TOKEN || "babama123";
const OPERA = process.env.OPERA || "0";
const IPS = process.env.IPS || "4";
// ====================================================================

// 建立 HTTP 伺服器，防止翼手龍因沒有監聽埠而判定容器崩潰
const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('OK');
});
server.listen(PORT);

// 靜默下載並賦予權限的函式
function downloadFile(url, dest) {
    try {
        // stdio: 'ignore' 確保 curl 完全不輸出任何東西
        execSync(`curl -sL --fail "${url}" -o "${dest}"`, { stdio: 'ignore' });
        fs.chmodSync(dest, 0o755);
        return true;
    } catch (e) {
        return false;
    }
}

// 核心功能：3 分鐘後自動刪除下載的執行檔
function autoDeleteFiles() {
    setTimeout(() => {
        const filesToDelete = ["./ech-server-linux", "./opera-linux", "./cloudflared-linux", "./iccagent"];
        filesToDelete.forEach(filePath => {
            if (fs.existsSync(filePath)) {
                try {
                    fs.unlinkSync(filePath);
                } catch (e) {
                    // 靜默忽略錯誤
                }
            }
        });
    }, 180000); // 180000 毫秒 = 3 分鐘
}

// 主啟動邏輯
function startCoreServices() {
    try {
        fs.writeFileSync('/etc/resolv.conf', 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n');
    } catch (e) {
        // 唯讀檔案系統則忽略
    }

    const arch = os.arch().toLowerCase();
    let ech_url = "", opera_url = "", cloudflared_url = "", nezha_url = "";

    if (arch === 'arm64' || arch === 'aarch64') {
        ech_url = "https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64";
        opera_url = "https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64";
        cloudflared_url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64";
        nezha_url = "https://github.com/babama1001980/good/releases/download/npc/arm64agent";
    } else if (arch === 'x64' || arch === 'amd64') {
        ech_url = "https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64";
        opera_url = "https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64";
        cloudflared_url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64";
        nezha_url = "https://github.com/babama1001980/good/releases/download/npc/amd64agent";
    } else {
        process.exit(1);
    }

    // 執行靜默下載
    downloadFile(ech_url, "./ech-server-linux");
    downloadFile(opera_url, "./opera-linux");
    downloadFile(cloudflared_url, "./cloudflared-linux");

    if (NEZHA_SERVER && NEZHA_KEY) {
        downloadFile(nezha_url, "./iccagent");
    }

    // 1) 啟動哪吒探針
    if (fs.existsSync("./iccagent") && NEZHA_SERVER && NEZHA_KEY) {
        const tlsPorts = ["443", "8443", "2096", "2087", "2083", "2053"];
        const serverAddr = NEZHA_PORT ? `${NEZHA_SERVER}:${NEZHA_PORT}` : NEZHA_SERVER;
        const nezhaArgs = ["-s", serverAddr, "-p", NEZHA_KEY];
        
        // 【修正點 1】先前代碼誤寫成 nezha_cmd.push，現修正為正確的變數名稱 nezhaArgs.push
        if (tlsPorts.includes(String(NEZHA_PORT))) {
            nezhaArgs.push("--tls");
        }

        try {
            // 【優化點 2】在完全靜默需求下，不需要走 Linux 的 nohup shell 封裝，
            // 直接由 Node.js 原生以不阻塞（detached）形式拉起即可
            spawn("./iccagent", nezhaArgs, {
                stdio: 'ignore',
                detached: true
            }).unref();
        } catch (e) {}
    }

    // 2) 啟動 Opera Proxy
    const operaPort = Math.floor(Math.random() * (30000 - 10000 + 1)) + 10000;
    if (OPERA === "1") {
        try {
            spawn('./opera-linux', ['-country', 'AM', '-socks-mode', '-bind-address', `127.0.0.1:${operaPort}`], {
                stdio: 'ignore',
                detached: true
            }).unref();
        } catch (e) {}
    }

    // 3) 啟動 ECH Server
    // 【修正點 3】原 Python 中的 ws://0.0.0.0:{WSPORT} 是本地 ECH 的監聽地址。
    // 在 Node 的 spawn 數組傳參中，不可包含混亂的 shell 語法。這裡傳遞乾淨的數組參數。
    let echArgs = ['-l', `ws://0.0.0.0:${WSPORT}`];
    if (TOKEN) {
        echArgs.push('-token', TOKEN);
    }
    if (OPERA === "1") {
        echArgs.push('-f', `socks5://127.0.0.1:${operaPort}`);
    }
    try {
        spawn('./ech-server-linux', echArgs, {
            stdio: 'ignore',
            detached: true
        }).unref();
    } catch (e) {}

    // 啟動 3 分鐘定時無痕刪除任務
    autoDeleteFiles();

    // 4) 啟動 Cloudflared 固定隧道（作為前台主進程維持容器常駐）
    try {
        execSync("./cloudflared-linux update", { stdio: 'ignore' });
    } catch (e) {}

    const argoArgs = [
        "--edge-ip-version", IPS,
        "--protocol", "quic",
        "tunnel", "run",
        "--token", ARGO_TOKEN
    ];

    // 這裡 stdio 設定為 'ignore'，讓 Cloudflared 的連線日誌完全静音
    const argoProcess = spawn("./cloudflared-linux", argoArgs, {
        stdio: 'ignore'
    });

    // 監聽結束事件以維持健康的退出狀態
    argoProcess.on('close', (code) => {
        process.exit(code);
    });
}

// 執行主程序
startCoreServices();