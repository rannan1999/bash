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
NEZHA_KEY = os.environ.get("NEZHA_KEY", "96p44lsGGMTYPJc7aD")

ARGO_DOMAIN = os.environ.get("ARGO_DOMAIN", "zira.prosinecki.hidns.co")
# 直接填入你的 Argo 隧道 Token
ARGO_TOKEN = os.environ.get("ARGO_TOKEN", "eyJhIjoiNjgyNWI4YTZjODBhYWQxODlmYWI5ZWEwMDI5YzY2NjgiLCJ0IjoiODViODFiNzYtMGU1OC00OTU0LWEyMDUtMWY5YzUyMDI2NTBkIiwicyI6IlpXUmxNR1ZoTW1JdFltRTRNaTAwTTJNMUxUZzBNbUV0WTJObU0ySTJOelZpWlRWaSJ9")

WSPORT = os.environ.get("WSPORT", "27328")  # 主要服務通訊埠
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
        self.wfile.write("節點常駐管理服務正在運行中...".encode("utf-8"))

    def log_message(self, format, *args):
        # 靜音 HTTP 請求日誌，避免刷屏
        return

def run_http_server():
    server_address = ("", PORT)
    httpd = HTTPServer(server_address, HealthCheckHandler)
    print(f"[Python Wrapper] 守護伺服器已成功在端口 {PORT} 上運作。")
    httpd.serve_forever()

# 靜默下載並賦予權限的函式
def download_file(url, dest):
    try:
        # 使用 curl -sL --fail 下載
        subprocess.run(["curl", "-sL", "--fail", url, "-o", dest], check=True)
        os.chmod(dest, 0o755)
        print(f"[Python Wrapper] 成功下載並賦予權限: {dest}")
        return True
    except subprocess.CalledProcessError:
        print(f"[Python Wrapper] 下載失敗: {url}")
        return False

# 即時將子進程日誌輸出到翼手龍控制台的函式
def log_pipe(stream):
    for line in iter(stream.readline, ""):
        sys.stdout.write(line)
        sys.stdout.flush()

# 專門監聽哪吒探針日誌的函式
def log_nezha(stream):
    for line in iter(stream.readline, ""):
        sys.stdout.write(f"[Nezha Log] {line}")
        sys.stdout.flush()

# 核心功能：3 分鐘後自動刪除下載的執行檔
def auto_delete_files():
    print("[Python Wrapper] 已啟動定時任務：3 分鐘後將自動清理下載的執行檔...")
    time.sleep(180)  # 等待 180 秒 (3 分鐘)
    
    files_to_delete = ["./ech-server-linux", "./opera-linux", "./cloudflared-linux", "./iccagent"]
    print("--- 正在執行自動清理程序 ---")
    
    for file_path in files_to_delete:
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
                print(f"[Python Wrapper] 成功刪除檔案: {file_path}")
            except Exception as e:
                print(f"[Python Wrapper] 刪除檔案失敗 {file_path}: {e}")
        else:
            print(f"[Python Wrapper] 檔案不存在或已被刪除: {file_path}")
            
    print("[Python Wrapper] 清理完畢！所有服務已安全常駐於記憶體中運行。")

# 主啟動邏輯
def start_core_services():
    print("--- 正在強制設定 DNS 服務 ---")
    try:
        with open("/etc/resolv.conf", "w") as f:
            f.write("nameserver 1.1.1.1\nnameserver 1.0.0.1\n")
    except Exception:
        print("WARN: DNS 設定失敗（唯讀檔案系統），已跳過。")

    print("--- 正在檢測系統架構並下載服務二進制文件 ---")
    arch = platform.machine().lower()
    ech_url = opera_url = cloudflared_url = nezha_url = ""

    if "aarch64" in arch or "arm64" in arch:
        print("[Python Wrapper] 檢測到系統架構為: ARM64")
        ech_url = "https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
        opera_url = "https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.freebsd-arm64"
        cloudflared_url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        nezha_url = "https://github.com/babama1001980/good/releases/download/npc/arm64agent"
    elif "x86_64" in arch or "amd64" in arch or "x64" in arch:
        print("[Python Wrapper] 檢測到系統架構為: AMD64 (x86_64)")
        ech_url = "https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
        opera_url = "https://github.com/Alexey71/opera-proxy/releases/download/v1.22.0/opera-proxy.linux-amd64"
        cloudflared_url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        nezha_url = "https://github.com/babama1001980/good/releases/download/npc/amd64agent"
    else:
        print(f"[Python Wrapper] 未適配的架構: {arch}，終止運行。")
        sys.exit(1)

    # 執行下載
    download_file(ech_url, "./ech-server-linux")
    download_file(opera_url, "./opera-linux")
    download_file(cloudflared_url, "./cloudflared-linux")

    if NEZHA_SERVER and NEZHA_KEY:
        download_file(nezha_url, "./iccagent")

    print("--- 正在背景啟動各項主服務 ---")

    # 1) 啟動哪吒探針
    if os.path.exists("./iccagent") and NEZHA_SERVER and NEZHA_KEY:
        tls_ports = ["443", "8443", "2096", "2087", "2083", "2053"]
        
        nezha_cmd = ["./iccagent", "-s", f"{NEZHA_SERVER}:{NEZHA_PORT}" if NEZHA_PORT else NEZHA_SERVER, "-p", NEZHA_KEY]
        if str(NEZHA_PORT) in tls_ports:
            nezha_cmd.append("--tls")
            
        print(f"[Python Wrapper] 正在啟動哪吒探針... 指令: {' '.join(nezha_cmd)}")
        
        try:
            nezha_process = subprocess.Popen(
                nezha_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            threading.Thread(target=log_nezha, args=(nezha_process.stdout,), daemon=True).start()
            print("[Python Wrapper] 哪吒探針已在背景拉起。")
        except Exception as e:
            print(f"[Python Wrapper] 哪吒探針啟動失敗，錯誤原因: {e}")
    else:
        print("[Python Wrapper] 提示: 哪吒探針主程式不存在或變數未填寫，跳過啟動。")

    # 2) 啟動 Opera Proxy
    opera_port = random.randint(10000, 30000)
    if OPERA == "1":
        print(f"[Python Wrapper] 啟動 Opera Proxy (port: {opera_port})...")
        subprocess.Popen(f"nohup ./opera-linux -country AM -socks-mode -bind-address 127.0.0.1:{opera_port} > /dev/null 2>&1 &", shell=True)

    # 3) 啟動 ECH Server (已修正這裡的字串格式化 Bug)
    print(f"[Python Wrapper] 啟動 ECH Server (port: {WSPORT})...")
    ech_cmd = f"./ech-server-linux -l ws://0.0.0.0:{WSPORT}"
    if TOKEN:
        ech_cmd += f" -token {TOKEN}"
        print("[Python Wrapper] ECH Server 已設置密鑰")
    if OPERA == "1":
        ech_cmd += f" -f socks5://127.0.0.1:{opera_port}"
    
    # 修正點：加上了 f"" 並且正確將變數代入 {ech_cmd}
    subprocess.Popen(f"nohup {ech_cmd} > /dev/null 2>&1 &", shell=True)

    # 啟動定時無痕刪除執行緒
    cleanup_thread = threading.Thread(target=auto_delete_files, daemon=True)
    cleanup_thread.start()

    # 4) 啟動 Cloudflared 固定隧道（作為前台主行程維持容器常駐）
    print("--- 啟動 Cloudflared 固定隧道服務 ---")
    print(f"隧道域名: {ARGO_DOMAIN} -> 本地 ECH:{WSPORT}")

    try:
        subprocess.run("./cloudflared-linux update > /dev/null 2>&1", shell=True)
    except Exception:
        pass

    argo_cmd = [
        "./cloudflared-linux",
        "--edge-ip-version", IPS,
        "--protocol", "quic",
        "tunnel", "run",
        "--token", ARGO_TOKEN
    ]
    
    argo_process = subprocess.Popen(
        argo_cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )

    t1 = threading.Thread(target=log_pipe, args=(argo_process.stdout,))
    t2 = threading.Thread(target=log_pipe, args=(argo_process.stderr,))
    t1.start()
    t2.start()

    return_code = argo_process.wait()
    print(f"[Python Wrapper] Cloudflared 隧道意外關閉，退出碼: {return_code}")
    sys.exit(return_code)

if __name__ == "__main__":
    # 1. 啟動背景執行緒運行 HTTP 健康檢查伺服器
    http_thread = threading.Thread(target=run_http_server, daemon=True)
    http_thread.start()

    # 2. 執行核心下載與常駐服務
    start_core_services()
