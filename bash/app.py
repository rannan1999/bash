import subprocess
import sys
import time

# Binary and config definitions
apps = [
    {
        'name': 'bash',
        'binaryPath': 'bash',
        'args': []
    }
]

# Run binary with keep-alive
def run_process(app):
    while True:
        print(f"[START] Starting {app['name']}...")
        child = subprocess.Popen(
            [app['binaryPath']] + app['args'],
            stdin=sys.stdin,
            stdout=sys.stdout,
            stderr=sys.stderr
        )
        return_code = child.wait()  # Block and wait for process to exit
        print(f"[EXIT] {app['name']} exited with code: {return_code}")
        print(f"[RESTART] Restarting {app['name']}...")
        time.sleep(3)  # Wait 3 seconds before restarting

# Main execution
def main():
    try:
        for app in apps:
            run_process(app)  # Since there's only one app, this enters an infinite loop
    except Exception as err:
        print(f"[ERROR] Startup failed: {err}")
        sys.exit(1)

if __name__ == "__main__":
    main()