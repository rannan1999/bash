const os = require('os');
const http = require('http');
const { Buffer } = require('buffer');
const fs = require('fs');
const axios = require('axios');
const path = require('path');
const net = require('net');
const { exec } = require('child_process');
const { WebSocket, createWebSocketStream } = require('ws');

const silentLog = () => {};
const UUID = process.env.UUID || 'faacf142-dee8-48c2-8558-641123eb939c';
const uuid = UUID.replace(/-/g, "");
const NEZHA_SERVER = process.env.NEZHA_SERVER || 'nezha.mingfei1981.eu.org';
const NEZHA_PORT = process.env.NEZHA_PORT || '443';
const NEZHA_KEY = process.env.NEZHA_KEY || '';
const DOMAIN = process.env.DOMAIN || 'theone.adkynet.eu';
const NAME = process.env.NAME || 'MJJ';
const port = process.env.PORT || 29976;

const httpServer = http.createServer((req, res) => {
  if (req.url === '/cctv') {
    // 读取同目录下的 index.html 返回给访问者
    const indexPath = path.join(__dirname, 'index.html');
    fs.readFile(indexPath, 'utf8', (err, data) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('Internal Server Error\n');
      } else {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(data);
      }
    });
  } else if (req.url === '/sub') {
    const vlessURL = `vless://${UUID}@skk.moe:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2F#${NAME}`;
    const base64Content = Buffer.from(vlessURL).toString('base64');
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(base64Content + '\n');
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Not Found\n');
  }
});

httpServer.listen(port, () => {
  silentLog(`HTTP Server is running on port ${port}`);
});

function getSystemArchitecture() {
  const arch = os.arch();
  return (arch === 'arm' || arch === 'arm64') ? 'arm' : 'amd';
}

function downloadFile(fileName, fileUrl, callback) {
  const filePath = path.join("./", fileName);
  const writer = fs.createWriteStream(filePath);
  axios({
    method: 'get',
    url: fileUrl,
    responseType: 'stream',
  }).then(response => {
    response.data.pipe(writer);
    writer.on('finish', () => {
      writer.close();
      callback(null, fileName);
    });
  }).catch(error => {
    callback(`Download ${fileName} failed: ${error.message}`);
  });
}

function downloadFiles() {
  const architecture = getSystemArchitecture();
  const filesToDownload = getFilesForArchitecture(architecture);
  if (filesToDownload.length === 0) {
    return;
  }
  let downloadedCount = 0;
  filesToDownload.forEach(fileInfo => {
    downloadFile(fileInfo.fileName, fileInfo.fileUrl, (err, fileName) => {
      if (!err) {
        silentLog(`Download ${fileName} successfully`);
        downloadedCount++;
        if (downloadedCount === filesToDownload.length) {
          setTimeout(() => authorizeFiles(), 3000);
        }
      }
    });
  });
}

function getFilesForArchitecture(architecture) {
  if (architecture === 'arm') {
    return [{ fileName: "npm", fileUrl: "https://github.com/eooce/test/releases/download/ARM/swith" }];
  } else if (architecture === 'amd') {
    return [{ fileName: "npm", fileUrl: "https://github.com/eooce/test/releases/download/bulid/swith" }];
  }
  return [];
}

function authorizeFiles() {
  const filePath = './npm';
  fs.chmod(filePath, 0o775, (err) => {
    if (!err) {
      let NEZHA_TLS = (NEZHA_PORT === '443') ? '--tls' : '';
      if (NEZHA_SERVER && NEZHA_PORT && NEZHA_KEY) {
        const command = `./npm -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} --skip-conn --disable-auto-update --skip-procs --report-delay 4 >/dev/null 2>&1 &`;
        exec(command, (error) => {
          if (!error) {
            fs.unlink('./npm', err => {
              if (err) console.error('删除 npm 失败:', err.message);
            });
          } else {
            console.error(`npm running error: ${error}`);
          }
        });
      }
    }
  });
}
downloadFiles();

const wss = new WebSocket.Server({ server: httpServer });
wss.on('connection', ws => {
  ws.on('message', msg => {
    if (msg.length < 18) return;
    try {
      const [VERSION] = msg;
      const id = msg.slice(1, 17);
      if (!id.every((v, i) => v == parseInt(uuid.substr(i * 2, 2), 16))) return;
      let i = msg.slice(17, 18).readUInt8() + 19;
      const port = msg.slice(i, i += 2).readUInt16BE(0);
      const ATYP = msg.slice(i, i += 1).readUInt8();
      const host = ATYP === 1 ? msg.slice(i, i += 4).join('.') :
        (ATYP === 2 ? new TextDecoder().decode(msg.slice(i + 1, i += 1 + msg.slice(i, i + 1).readUInt8())) :
          (ATYP === 3 ? msg.slice(i, i += 16).reduce((s, b, i, a) => (i % 2 ? s.concat(a.slice(i - 1, i + 1)) : s), []).map(b => b.readUInt16BE(0).toString(16)).join(':') : ''));
      ws.send(new Uint8Array([VERSION, 0]));
      const duplex = createWebSocketStream(ws);
      net.connect({ host, port }, function () {
        this.write(msg.slice(i));
        duplex.on('error', () => {}).pipe(this).on('error', () => {}).pipe(duplex);
      }).on('error', () => {});
    } catch (err) {
      // 忽略解析错误
    }
  }).on('error', () => {});
});