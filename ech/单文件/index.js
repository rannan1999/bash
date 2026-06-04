const http = require('http');
const { exec, execSync } = require('child_process');
const fs = require('fs');
const os = require('os');

// ==================== 【在此處填寫你的自訂變數】 ====================
const PORT = process.env.PORT || 3000; // Node 本身的 HTTP 監聽埠

const NEZHA_SERVER = process.env.NEZHA_SERVER || 'nezha.mingfei1981.eu.org';
const NEZHA_PORT = process.env.NEZHA_PORT || '443';
const NEZHA_KEY = process.env.NEZHA_KEY || 'VFib8kpAjZGKJeS5qW';

const ARGO_DOMAIN = process.env.ARGO_DOMAIN || 'nf-nl.mingfei1982.eu.org';
// 直接填入你的 Argo 隧道 Token
const ARGO_TOKEN = process.env.ARGO_TOKEN || 'eyJhIjoiMGYxNTA1MzUwOTRjNDhlZjNmM2ZjZTA2M2E4N2M1N2YiLCJ0IjoiMjRkNGZmZGMtZTc2ZS00MjU0LWI1ODgtYzNiNzIwZjZjZGIwIiwicyI6IllUVmpZV1JpWW1FdE5EYzNOaTAwTkRsaExXRTVOVEF0T0RJME5UTmtNVE00WkRVNSJ9';

const WSPORT = process.env.WSPORT || '10264'; // 主要服務通訊埠
const TOKEN = process.env.TOKEN || 'babama123'; // ECH Server 密鑰
const OPERA = process.env.OPERA || '0';
const IPS = process.env.IPS || '4';
// ====================================================================

// 建立一個基礎的 HTTP 伺服器，防止翼手龍因沒有監聽埠而判定容器崩潰
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('節點常駐管理服務正在運行中...');
});

// 靜默下載函式
function downloadFile(url, dest) {
  try {
    execSync(`curl -sL --fail "${url}" -o "${dest}"`);
    fs.chmodSync(dest, '755');
    console.log(`[Node Wrapper] 成功下載並賦予權限: ${dest}`);
    return true;
  } catch (err) {
    console.error(`[Node Wrapper] 下載失敗: ${url}`);
    return false;
  }
}

// 主啟動邏輯
function startCoreServices() {
  console.log('--- 正在強制設定 DNS 服務 ---');
  try {
    fs.writeFileSync('/etc/resolv.conf', 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n');
  } catch (e) {
    console.log('WARN: DNS 設定失敗（唯讀檔案系統），已跳過。');
  }

  console.log('--- 正在檢測系統架構並下載服務二進制文件 ---');
  const arch = os.arch(); // 獲取當前核心架構
  let echUrl = '', operaUrl = '', cloudflaredUrl = '', nezhaUrl = '';

  // 1:1 還原 Shell 腳本中經過驗證的精準亮燈架構分流
  if (arch === 'arm64' || arch === 'aarch64') {
    console.log('[Node Wrapper] 檢測到系統架構為: ARM64');
    echUrl = 'https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64';
    operaUrl = 'https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64';
    cloudflaredUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64';
    nezhaUrl = 'https://github.com/babama1001980/good/releases/download/npc/arm64agent';
  } else if (arch === 'x64' || arch === 'amd64') {
    console.log('[Node Wrapper] 檢測到系統架構為: AMD64 (x86_64)');
    echUrl = 'https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64';
    operaUrl = 'https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64';
    cloudflaredUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64';
    nezhaUrl = 'https://github.com/babama1001980/good/releases/download/npc/amd64agent';
  } else {
    console.error(`[Node Wrapper] 未適配的架構: ${arch}，終止運行。`);
    process.exit(1);
  }

  // 執行下載
  downloadFile(echUrl, './ech-server-linux');
  downloadFile(operaUrl, './opera-linux');
  downloadFile(cloudflaredUrl, './cloudflared-linux');

  if (NEZHA_SERVER && NEZHA_KEY) {
    downloadFile(nezhaUrl, './iccagent');
  }

  console.log('--- 正在背景啟動各項主服務 ---');

  // 1) 啟動哪吒探針 (帶有 TLS 埠自動校驗邏輯)
  if (fs.existsSync('./iccagent') && NEZHA_SERVER && NEZHA_KEY) {
    const tlsPorts = ['443', '8443', '2096', '2087', '2083', '2053'];
    const nezhaTls = tlsPorts.includes(NEZHA_PORT.toString()) ? '--tls' : '';
    
    console.log(`[Node Wrapper] 正在啟動哪吒探針 (伺服器: ${NEZHA_SERVER}:${NEZHA_PORT})...`);
    
    let nezhaCmd = `./iccagent -s "${NEZHA_SERVER}:${NEZHA_PORT}" -p "${NEZHA_KEY}" ${nezhaTls}`;
    if (!NEZHA_PORT) {
      nezhaCmd = `./iccagent -s "${NEZHA_SERVER}" -p "${NEZHA_KEY}" ${nezhaTls}`;
    }

    // 使用 nohup 格式在背景執行
    exec(`nohup ${nezhaCmd} > /dev/null 2>&1 &`);
    console.log('[Node Wrapper] 哪吒探針已在背景拉起。');
  }

  // 2) 啟動 Opera Proxy
  let operaPort = Math.floor(Math.random() * 20000) + 10000;
  if (OPERA === '1') {
    console.log(`[Node Wrapper] 啟動 Opera Proxy (port: ${operaPort})...`);
    exec(`nohup ./opera-linux -country "AM" -socks-mode -bind-address "127.0.0.1:${operaPort}" > /dev/null 2>&1 &`);
  }

  // 3) 啟動 ECH Server
  console.log(`[Node Wrapper] 啟動 ECH Server (port: ${WSPORT})...`);
  let echCmd = `./ech-server-linux -l "ws://0.0.0.0:${WSPORT}"`;
  if (TOKEN) {
    echCmd += ` -token "${TOKEN}"`;
    console.log('[Node Wrapper] ECH Server 已設置密鑰');
  }
  if (OPERA === '1') {
    echCmd += ` -f "socks5://127.0.0.1:${operaPort}"`;
  }
  exec(`nohup ${echCmd} > /dev/null 2>&1 &`);

  // 4) 啟動 Cloudflared 固定隧道（作為前台主行程，輸出日誌並維持容器不退出）
  console.log('--- 啟動 Cloudflared 固定隧道服務 ---');
  console.log(`隧道域名: ${ARGO_DOMAIN} -> 本地 ECH:${WSPORT}`);

  // 先嘗試自動更新（比照原腳本）
  try { execSync('./cloudflared-linux update > /dev/null 2>&1'); } catch(e){}

  const argoCmd = `./cloudflared-linux --edge-ip-version "${IPS}" --protocol quic tunnel run --token "${ARGO_TOKEN}"`;
  
  const argoProcess = exec(argoCmd);

  // 將 Cloudflared 的日誌即時管線輸出到翼手龍的主控制台上
  argoProcess.stdout.on('data', (data) => process.stdout.write(data));
  argoProcess.stderr.on('data', (data) => process.stderr.write(data));

  argoProcess.on('close', (code) => {
    console.log(`[Node Wrapper] Cloudflared 隧道意外關閉，退出碼: ${code}`);
    process.exit(code);
  });
}

// 啟動 Node HTTP 監聽，隨後調用核心組件
server.listen(PORT, () => {
  console.log(`[Node Wrapper] 守護伺服器已成功在端口 ${PORT} 上運作。`);
  startCoreServices();
});

// 處理程序結束訊號，優雅清理
process.on('SIGINT', () => {
  server.close(() => {
    process.exit(0);
  });
});