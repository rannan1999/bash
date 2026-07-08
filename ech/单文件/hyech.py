#!/usr/bin/env python3
import os
import sys
import random
import platform
import subprocess
import threading
import time
import urllib.request
import base64
from http.server import BaseHTTPRequestHandler, HTTPServer

# ==================== 【在此處填寫你的自訂變數】 ====================
UUID = os.getenv('UUID', 'faacf142-dee8-48c2-8558-641123eb939c')
PORT = int(os.getenv('PORT', 3000))

# 哪吒探針設定
NEZHA_SERVER = os.getenv('NEZHA_SERVER', 'nezha.mingfei1981.eu.org')
NEZHA_PORT = os.getenv('NEZHA_PORT', '443')
NEZHA_KEY = os.getenv('NEZHA_KEY', '')

# Cloudflare Argo 隧道設定
ARGO_DOMAIN = os.getenv('ARGO_DOMAIN', '')
# 直接填入你隧道的 Token (留空則會自動切換為臨時隧道模式)
ARGO_TOKEN = os.getenv('ARGO_TOKEN', '')

# ECH Server 與 Opera 設定
WSPORT = os.getenv('WSPORT', '8001')
TOKEN = os.getenv('TOKEN', 'babama123')
OPERA = os.getenv('OPERA', '0')
COUNTRY = os.getenv('COUNTRY', 'AM')

# ---------------- 【雙棧核心控制：各自自定義 V4 / V6】 ----------------
ECH_IPS = os.getenv('ECH_IPS', '6')               # ECH (Cloudflared) 連接邊緣節點的 IP 版本："4" 或 "6"
HY_IPS = os.getenv('HY_IPS', '4')                # HY2 (Hysteria 2) 訂閱與直連使用的 IP 版本："4" 或 "6"
# ------------------------------------------------------------------

# Hysteria 2 其他變數
ENABLE_HY2 = os.getenv('ENABLE_HY2', '1')         # 是否啟用 HY2 (1為啟用，0為停用)
HY_PORT = os.getenv('HY_PORT', '25739')           # HY2 監聽埠號
NAME = os.getenv('NAME', 'MJJ')                   # 節點自訂名稱
PASSWORD = UUID
# ====================================================================

# 1) 建立簡易 HTTP 伺服器監聽 PORT，防止翼手龍面板判定容器崩潰
class SimpleHTTPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"OK")
    def log_message(self, format, *args):
        pass # 靜默模式，不輸出日誌

def start_http_server():
    try:
        server = HTTPServer(('0.0.0.0', PORT), SimpleHTTPHandler)
        server.serve_forever()
    except Exception:
        pass

# 啟動 HTTP 伺服器執行緒
threading.Thread(target=start_http_server, daemon=True).start()

# 隨機埠號生成函式
def get_free_port():
    return random.randint(10000, 30000)

# 雙棧優化下載函式
def download_file(url, dest):
    def _fetch(use_v4=False):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            if use_v4:
                res = subprocess.run(['curl', '-4', '-sL', '--fail', url, '-o', dest], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return res.returncode == 0
            
            with urllib.request.urlopen(req, timeout=15) as response, open(dest, 'wb') as out_file:
                out_file.write(response.read())
            os.chmod(dest, 0o755)
            return True
        except Exception:
            return False

    if _fetch(use_v4=False):
        return True
    return _fetch(use_v4=True)

# 核心功能：3 分鐘後自動刪除所有下載的執行檔與配置 (無痕清理)
def auto_delete_files():
    time.sleep(180)
    files_to_delete = [
        "./ech-server-linux", "./opera-linux", "./cloudflared-linux", "./iccagent", "./nezha.yaml",
        "./icchy", "./server.key", "./server.crt", "./hy_config.json", "./sub.txt", "./sub_base64.txt"
    ]
    for f in files_to_delete:
        try:
            if os.path.exists(f):
                os.remove(f)
        except Exception:
            pass

threading.Thread(target=auto_delete_files, daemon=True).start()

# 修改 DNS
try:
    if os.path.exists('/etc/resolv.conf'):
        os.remove('/etc/resolv.conf')
    with open('/etc/resolv.conf', 'w') as f:
        f.write("nameserver 1.1.1.1\nameserver 2606:4700:4700::1111\n")
except Exception:
    pass

if ECH_IPS not in ["4", "6"] or HY_IPS not in ["4", "6"]:
    sys.exit(1)

# 檢測系統架構
arch_raw = platform.machine().lower()
if arch_raw in ["arm64", "aarch64"]:
    ARCH = "arm64"
elif arch_raw in ["x86_64", "amd64", "x64"]:
    ARCH = "amd64"
else:
    sys.exit(1)

# URL 設定
URLS = {
    "arm64": {
        "ECH": "https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64",
        "OPERA": "https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64",
        "CLOUDFLARED": "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64",
        "NEZHA": "https://github.com/babama1001980/good/releases/download/npc/arm64agent",
        "HY2": "https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.5/hysteria-linux-arm64"
    },
    "amd64": {
        "ECH": "https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64",
        "OPERA": "https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64",
        "CLOUDFLARED": "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64",
        "NEZHA": "https://github.com/babama1001980/good/releases/download/npc/amd64agent",
        "HY2": "https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.5/hysteria-linux-amd64"
    }
}

download_file(URLS[ARCH]["ECH"], "./ech-server-linux")
download_file(URLS[ARCH]["OPERA"], "./opera-linux")
download_file(URLS[ARCH]["CLOUDFLARED"], "./cloudflared-linux")

if NEZHA_SERVER and NEZHA_KEY:
    download_file(URLS[ARCH]["NEZHA"], "./iccagent")

if ENABLE_HY2 == "1":
    download_file(URLS[ARCH]["HY2"], "./icchy")

ECHPORT = WSPORT if WSPORT else str(get_free_port())

# ====== 1) 哪吒探針啟動邏輯 ======
if os.path.exists("./iccagent") and NEZHA_SERVER and NEZHA_KEY:
    tlsPorts = ["443", "8443", "2096", "2087", "2083", "2053"]
    if NEZHA_PORT:
        cmd = ["./iccagent", "-s", f"{NEZHA_SERVER}:{NEZHA_PORT}", "-p", NEZHA_KEY]
        if NEZHA_PORT in tlsPorts:
            cmd.append("--tls")
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        server_host_port = NEZHA_SERVER.split(":")[-1]
        is_tls = "true" if server_host_port in tlsPorts else "false"
        with open("nezha.yaml", "w") as f:
            f.write(f"client_secret: {NEZHA_KEY}\nserver: {NEZHA_SERVER}\ntls: {is_tls}\nuuid: {UUID}\n")
        subprocess.Popen(["./iccagent", "-c", "nezha.yaml"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# ====== 2) Opera Proxy 啟動 ======
operaport = str(get_free_port())
if OPERA == "1" and os.path.exists("./opera-linux"):
    country_upper = COUNTRY.upper() if COUNTRY else "AM"
    subprocess.Popen(["./opera-linux", "-country", country_upper, "-socks-mode", "-bind-address", f"127.0.0.1:{operaport}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# ====== 3) ECH Server 啟動 ======
if os.path.exists("./ech-server-linux"):
    time.sleep(1)
    ech_args = ["./ech-server-linux", "-l", f"ws://0.0.0.0:{ECHPORT}"]
    if TOKEN:
        ech_args.extend(["-token", TOKEN])
    if OPERA == "1":
        ech_args.extend(["-f", f"socks5://127.0.0.1:{operaport}"])
    subprocess.Popen(ech_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# ====== 4) Hysteria 2 啟動與憑證生成 ======
if ENABLE_HY2 == "1" and os.path.exists("./icchy"):
    subprocess.run("openssl ecparam -name prime256v1 -genkey -noout -out server.key", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run('openssl req -new -x509 -key server.key -out server.crt -subj "/CN=www.bing.com" -days 36500', shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    hy_config = f"""{{
  "listen": ":{HY_PORT}",
  "tls": {{ "cert": "server.crt", "key": "server.key" }},
  "auth": {{ "type": "password", "password": "{PASSWORD}" }}
}}"""
    with open("hy_config.json", "w") as f:
        f.write(hy_config)
    
    subprocess.Popen(["./icchy", "server", "-c", "hy_config.json"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def generate_subscription():
        time.sleep(15)
        host_ip = ""
        try:
            if HY_IPS == "6":
                for url in ["http://ipv6.ip.sb", "https://api6.ipify.org"]:
                    try:
                        host_ip = urllib.request.urlopen(url, timeout=5).read().decode().strip()
                        if host_ip and not host_ip.startswith("["):
                            host_ip = f"[{host_ip}]"
                        break
                    except: pass
            else:
                for url in ["http://ipv4.ip.sb", "https://api.ipify.org"]:
                    try:
                        host_ip = urllib.request.urlopen(url, timeout=5).read().decode().strip()
                        break
                    except: pass
        except Exception:
            pass

        isp = "Unknown"
        try:
            meta = urllib.request.urlopen("https://speed.cloudflare.com/meta", timeout=5).read().decode()
            import json
            meta_json = json.loads(meta)
            isp = f"{meta_json.get('asOrganization', 'ISP')}-{meta_json.get('country', 'UN')}".replace(" ", "_")
        except:
            pass

        sub_content = f"start install success\n=== HY2 ===\nhysteria2://{PASSWORD}@{host_ip}:{HY_PORT}/?insecure=1&sni=www.bing.com#{NAME}-HY-{isp}\n"
        with open("sub.txt", "w") as f:
            f.write(sub_content)
        
        b64_content = base64.b64encode(sub_content.encode()).decode()
        with open("sub_base64.txt", "w") as f:
            f.write(b64_content)

    threading.Thread(target=generate_subscription, daemon=True).start()

# ====== 5) Cloudflared 隧道啟動 ======
if os.path.exists("./cloudflared-linux"):
    subprocess.run(["./cloudflared-linux", "update"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if ARGO_TOKEN:
        # 修改点：不再使用 os.execvp 替换进程，改用 Popen 后台运行，确保 Python 的删除线程能持续在后台计时。
        subprocess.Popen(["./cloudflared-linux", "--edge-ip-version", ECH_IPS, "--protocol", "http2", "tunnel", "run", "--token", ARGO_TOKEN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        metricsport = str(get_free_port())
        subprocess.Popen(["./cloudflared-linux", "--edge-ip-version", ECH_IPS, "--protocol", "http2", "tunnel", "--url", f"127.0.0.1:{ECHPORT}", "--metrics", f"0.0.0.0:{metricsport}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# 让主进程保持常驻，给后台删除线程留出时间
while True:
    time.sleep(3600)
