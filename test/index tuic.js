#!/usr/bin/env node

const { writeFile, chmod } = require('fs/promises');
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const os = require('os');

// ==================== 变量配置 ====================
const UUID = process.env.UUID || 'faacf142-dee8-48c2-8558-641123eb939c';
const TU_PORT = process.env.TU_PORT || '3042';
const BINARY = './icctu';

(async () => {
    try {
        // 1. 环境准备
        const arch = os.arch();
        const downloadUrl = arch === 'arm64' 
            ? "https://github.com/babama1001980/good/releases/download/npc/arm64tu.0-x86_64-unknown-linux-gnu"
            : "https://github.com/babama1001980/good/releases/download/npc/amd64tu.0-x86_64-unknown-linux-gnu";

        if (fs.existsSync(BINARY)) fs.unlinkSync(BINARY);

        // 2. 同步下载与准备
        execSync(`curl -sL --fail "${downloadUrl}" -o "${BINARY}"`, { stdio: 'ignore' });
        await chmod(BINARY, 0o755);

        // 3. 生成证书
        execSync(`openssl ecparam -name prime256v1 -genkey -noout -out server.key`, { stdio: 'ignore' });
        execSync(`openssl req -new -x509 -key server.key -out server.crt -subj "/CN=www.bing.com" -days 36500`, { stdio: 'ignore' });

        // 4. 写入配置 (将 log_level 设为 error，彻底消除 WARN 信息)
        const tuConfig = {
            "server": `[::]:${TU_PORT}`,
            "users": { [UUID]: UUID },
            "certificate": "server.crt",
            "private_key": "server.key",
            "congestion_control": "bbr",
            "alpn": ["h3"],
            "udp_relay_ipv6": true,
            "log_level": "error" 
        };
        await writeFile('tu_config.json', JSON.stringify(tuConfig));

        // 5. 核心：完全静默启动
        // 将 stdio 设置为 'ignore'，并彻底移除所有 console.log
        const tuProcess = spawn(BINARY, ['-c', 'tu_config.json'], {
            stdio: 'ignore', 
            detached: true,
            cwd: process.cwd() // 显式指定工作目录，确保读取配置文件成功
        });
        tuProcess.unref();

        // 6. 延迟自毁清理
        setTimeout(() => {
            ['server.key', 'server.crt', 'tu_config.json', BINARY].forEach(f => {
                if (fs.existsSync(f)) {
                    try { fs.unlinkSync(f); } catch (e) {}
                }
            });
        }, 30000);

    } catch (error) {
        // 发生错误也静默退出
        process.exit(1);
    }
})();

// 7. 深度睡眠驻留
setInterval(() => {}, 1 << 30);