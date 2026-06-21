import os
import sys
import json
import time
import platform
import threading
import subprocess

# 配置变量
UUID = os.environ.get('UUID', 'faacf142-dee8-48c2-8558-641123eb939c')
HY_PORT = os.environ.get('HY_PORT', '6012')
BINARY_NAME = 'icchy'

# 1. 架构检测
machine = platform.machine().lower()
arch = 'amd64' if 'x86_64' in machine or 'amd64' in machine else 'arm64'
download_url = f"https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.5/hysteria-linux-{arch}"

try:
    # 2. 内存优化下载 (使用 DEVNULL 确保完全静默)
    curl = subprocess.Popen(
        ['curl', '-sL', download_url, '-o', BINARY_NAME],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    curl.wait()

    if os.path.exists(BINARY_NAME):
        # 赋予执行权限
        os.chmod(BINARY_NAME, 0o755)

        # 生成证书与密钥
        subprocess.run(
            ['openssl', 'ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'server.key'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        subprocess.run(
            ['openssl', 'req', '-new', '-x509', '-key', 'server.key', '-out', 'server.crt', '-subj', '/CN=www.bing.com', '-days', '36500'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

        # 写入配置文件
        config = {
            "listen": f":{HY_PORT}",
            "tls": {"cert": "server.crt", "key": "server.key"},
            "auth": {"type": "password", "password": UUID},
            "quic": {"maxIdleTimeout": "30s"}
        }
        with open('hy_config.json', 'w') as f:
            json.dump(config, f)

        # 3. 启动服务 (静默运行)
        subprocess.Popen(
            [f"./{BINARY_NAME}", 'server', '-c', 'hy_config.json'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        # 4. 60秒自毁清理
        def cleanup():
            files_to_remove = ['server.key', 'server.crt', 'hy_config.json', BINARY_NAME]
            for file in files_to_remove:
                if os.path.exists(file):
                    try:
                        os.remove(file)
                    except Exception:
                        pass

        timer = threading.Timer(60.0, cleanup)
        timer.start()

except Exception:
    pass

# 5. 核心：防止 Python 进程退出
while True:
    time.sleep(3600)