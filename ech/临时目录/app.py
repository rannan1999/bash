import os
import sys
import platform
import subprocess
import threading
import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

# ==================== 【在此處填寫你的自訂變數】 ====================
PORT = int(os.environ.get("PORT", 3000))  # Python 本身的 HTTP 監聽埠

NEZHA_SERVER = os.environ.get("NEZHA_SERVER", "nezha.mingfei1981.eu.org")
NEZHA_PORT = os.environ.get("NEZHA_PORT", "443")
NEZHA_KEY = os.environ.get("NEZHA_KEY", "")

ARGO_DOMAIN = os.environ.get("ARGO_DOMAIN", "")
# 直接填入你的 Argo 隧道 Token
ARGO_TOKEN = os.environ.get("ARGO_TOKEN", "")

WSPORT = os.environ.get("WSPORT", "8001")  # 主要服務通訊埠
TOKEN = os.environ.get("TOKEN", "babama123")  # ECH Server 密鑰
OPERA = os.environ.get("OPERA", "0")
IPS = os.environ.get("IPS", "4")
# ====================================================================

# 建立一個基礎的 HTTP 伺服器，防止翼手龍因沒有監聽埠而判定容器崩潰
class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write("OK".encode("utf-8"))

    def log_message(self, format, *args):
        # 靜音 HTTP 請求日誌
        return

def run_http_server():
    server_address = ("", PORT)
    httpd = HTTPServer(server_address, HealthCheckHandler)
    httpd.serve_forever()

# 靜默下載並賦予權限的函式
def download_file(url, dest):
    try:
        # 重新導向輸出至 DEVNULL 實現完全靜默
        subprocess.run(["curl", "-sL", "--fail", url, "-o", dest], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        os.chmod(dest, 0o755)
        return True
    except Exception:
        return False

# 核心功能：3 分鐘後自動刪除下載的執行檔（已修改为 /tmp/ 路径）
def auto_delete_files():
    time.sleep(180)  # 等待 180 秒 (3 分鐘)
    files_to_delete = ["/tmp/ech-server-linux", "/tmp/opera-linux", "/tmp/cloudflared-linux", "/tmp/iccagent"]
    for file_path in files_to_delete:
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception:
                pass

# 主啟動邏輯
def start_core_services():
    try:
        with open("/etc/resolv.conf", "w") as f:
            f.write("nameserver 1.1.1.1\nnameserver 1.0.0.1\n")
    except Exception:
        pass

    arch = platform.machine().lower()
    ech_url = opera_url = cloudflared_url = nezha_url = ""

    if "aarch64" in arch or "arm64" in arch:
        ech_url = "https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
        opera_url = "https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64"
        cloudflared_url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        nezha_url = "https://github.com/babama1001980/good/releases/download/npc/arm64agent"
    elif "x86_64" in arch or "amd64" in arch or "x64" in arch:
        ech_url = "https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
        opera_url = "https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64"
        cloudflared_url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        nezha_url = "https://github.com/babama1001980/good/releases/download/npc/amd64agent"
    else:
        sys.exit(1)

    # 執行下載到 /tmp/ 目录
    download_file(ech_url, "/tmp/ech-server-linux")
    download_file(opera_url, "/tmp/opera-linux")
    download_file(cloudflared_url, "/tmp/cloudflared-linux")

    if NEZHA_SERVER and NEZHA_KEY:
        download_file(nezha_url, "/tmp/iccagent")

    # 1) 啟動哪吒探針
    if os.path.exists("/tmp/iccagent") and NEZHA_SERVER and NEZHA_KEY:
        tls_ports = ["443", "8443", "2096", "2087", "2083", "2053"]
        nezha_cmd = ["/tmp/iccagent", "-s", f"{NEZHA_SERVER}:{NEZHA_PORT}" if NEZHA_PORT else NEZHA_SERVER, "-p", NEZHA_KEY]
        if str(NEZHA_PORT) in tls_ports:
            nezha_cmd.append("--tls")
            
        try:
            subprocess.Popen(
                nezha_cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        except Exception:
            pass

    # 2) 啟動 Opera Proxy
    opera_port = random.randint(10000, 30000)
    if OPERA == "1":
        subprocess.Popen(f"nohup /tmp/opera-linux -country AM -socks-mode -bind-address 127.0.0.1:{opera_port} > /dev/null 2>&1 &", shell=True)

    # 3) 啟動 ECH Server
    ech_cmd = f"/tmp/ech-server-linux -l ws://0.0.0.0:{WSPORT}"
    if TOKEN:
        ech_cmd += f" -token {TOKEN}"
    if OPERA == "1":
        ech_cmd += f" -f socks5://127.0.0.1:{opera_port}"
    subprocess.Popen(f"nohup {ech_cmd} > /dev/null 2>&1 &", shell=True)

    # 啟動定時無痕刪除執行緒
    cleanup_thread = threading.Thread(target=auto_delete_files, daemon=True)
    cleanup_thread.start()

    # 4) 啟動 Cloudflared 固定隧道
    try:
        subprocess.run("/tmp/cloudflared-linux update > /dev/null 2>&1", shell=True)
    except Exception:
        pass

    argo_cmd = [
        "/tmp/cloudflared-linux",
        "--edge-ip-version", IPS,
        "--protocol", "quic",
        "tunnel", "run",
        "--token", ARGO_TOKEN
    ]
    
    argo_process = subprocess.Popen(
        argo_cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    # 保持主行程阻塞以維持容器運行
    return_code = argo_process.wait()
    sys.exit(return_code)

if __name__ == "__main__":
    # 1. 啟動背景執行緒運行 HTTP 健康檢查伺服器
    http_thread = threading.Thread(target=run_http_server, daemon=True)
    http_thread.start()

    # 2. 執行核心下載與常駐服務
    start_core_services()