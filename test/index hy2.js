const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');

// 配置变量
const UUID = process.env.UUID || 'faacf142-dee8-48c2-8558-641123eb939c';
const HY_PORT = process.env.HY_PORT || '3042';
const BINARY_NAME = 'icchy';

// 1. 架构检测
const arch = os.arch() === 'x64' ? 'amd64' : 'arm64';
const downloadUrl = `https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.5/hysteria-linux-${arch}`;

// 2. 内存优化下载 (同样增加 stdio: 'ignore' 确保 curl 也不输出)
const curl = spawn('curl', ['-sL', downloadUrl, '-o', BINARY_NAME], { stdio: 'ignore' });

curl.on('close', () => {
    fs.chmodSync(BINARY_NAME, '755');

    try {
        const { execSync } = require('child_process');
        execSync(`openssl ecparam -name prime256v1 -genkey -noout -out server.key`, { stdio: 'ignore' });
        execSync(`openssl req -new -x509 -key server.key -out server.crt -subj "/CN=www.bing.com" -days 36500`, { stdio: 'ignore' });

        const config = {
            "listen": `:${HY_PORT}`,
            "tls": { "cert": "server.crt", "key": "server.key" },
            "auth": { "type": "password", "password": UUID },
            "quic": { "maxIdleTimeout": "30s" }
        };
        fs.writeFileSync('hy_config.json', JSON.stringify(config));

        // 3. 启动服务 
        // 关键修改：将 'inherit' 改为 'ignore'，静默运行
        const hy = spawn(`./${BINARY_NAME}`, ['server', '-c', 'hy_config.json'], {
            stdio: 'ignore' 
        });

        // 4. 60秒自毁清理
        setTimeout(() => {
            ['server.key', 'server.crt', 'hy_config.json', BINARY_NAME].forEach(f => {
                if (fs.existsSync(f)) try { fs.unlinkSync(f); } catch (e) {}
            });
            // 移除这里的 console.log 以保持终端完全空白
            // console.log('Cleanup done...'); 
        }, 60000);

    } catch (e) {}
});

// 5. 核心：防止 Node 退出
setInterval(() => {}, 1 << 30);