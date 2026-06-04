const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const scriptPath = path.join(__dirname, 'start.sh');

// 檢查 start.sh 是否存在
if (!fs.existsSync(scriptPath)) {
    console.error(`[Node Wrapper] 錯誤: 找不到 ${scriptPath}，請確認該檔案已上傳至根目錄。`);
    process.exit(1);
}

console.log('[Node Wrapper] 正在初始化環境並賦予 start.sh 執行權限...');

try {
    // 賦予 start.sh 執行權限 (相當於 chmod +x)
    fs.chmodSync(scriptPath, '755');
} catch (err) {
    console.warn(`[Node Wrapper] 警告: 賦予執行權限時發生錯誤 (可能為唯讀檔案系統): ${err.message}`);
}

console.log('[Node Wrapper] 正在啟動啟動腳本 start.sh...');

// 執行 start.sh 腳本
// 翼手龍的 Node 實例通常可以直接執行 bash 腳本
const child = spawn('bash', [scriptPath], {
    cwd: __dirname,
    env: process.env,
    stdio: 'inherit' // 直接將子進程的 stdout/stderr 導向到翼手龍控制台
});

// 監聽結束事件
child.on('close', (code) => {
    console.log(`[Node Wrapper] start.sh 進程已退出，退出碼: ${code}`);
    process.exit(code);
});

child.on('error', (err) => {
    console.error(`[Node Wrapper] 執行 start.sh 時發生致命錯誤:`, err);
    process.exit(1);
});