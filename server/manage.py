import subprocess
import sys
import os
import threading
import signal
import time
from queue import Queue, Empty

# Configuration
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
VENV_PYTHON = os.path.join(PROJECT_ROOT, "venv", "Scripts", "python.exe")
VENV_CELERY = os.path.join(PROJECT_ROOT, "venv", "Scripts", "celery.exe")
REDIS_SERVER = os.path.join(PROJECT_ROOT, "tools", "redis", "redis-server.exe")

# Colors for pretty output
COLORS = {
    "Redis": "\033[91m",   # Red
    "Worker": "\033[92m",  # Green
    "API": "\033[94m",     # Blue
    "System": "\033[93m",  # Yellow
    "RESET": "\033[0m"
}

def print_log(name, message):
    """Thread-safe logging with colors"""
    color = COLORS.get(name, COLORS["RESET"])
    try:
        # Decode bytes if necessary
        if isinstance(message, bytes):
            message = message.decode('utf-8', errors='replace')
        message = message.strip()
        if message:
            print(f"{color}[{name}] {message}{COLORS['RESET']}")
    except Exception:
        pass

def stream_reader(process, name):
    """Reads stdout/stderr from a process and prints it"""
    for line in iter(process.stdout.readline, b''):
        print_log(name, line)
    process.stdout.close()

processes = []
should_exit = False

def start_service(name, command, cwd=PROJECT_ROOT):
    """Starts a subprocess"""
    print_log("System", f"Starting {name}...")
    try:
        # shell=False is safer and allows better signal handling on Windows
        proc = subprocess.Popen(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, # Merge stderr into stdout
            shell=False 
        )
        processes.append(proc)
        
        # Start a thread to read logs
        t = threading.Thread(target=stream_reader, args=(proc, name))
        t.daemon = True
        t.start()
        return proc
    except Exception as e:
        print_log("System", f"Failed to start {name}: {e}")
        return None

def main():
    # 1. Start Redis
    start_service("Redis", [REDIS_SERVER])
    time.sleep(1) # Wait for Redis to warm up

    # 2. Start Celery
    # Windows needs -P solo
    start_service("Worker", [
        VENV_CELERY, "-A", "app.worker.celery_app", "worker", 
        "--loglevel=INFO", "-P", "solo"
    ])

    # 3. Start FastAPI
    start_service("API", [VENV_PYTHON, "main.py"])

    print_log("System", "All services started. Press Ctrl+C to stop.")

    try:
        while True:
            time.sleep(1)
            # Check if any process died
            for p in processes:
                if p.poll() is not None:
                    print_log("System", "A service has stopped unexpectedly. Shutting down...")
                    raise KeyboardInterrupt
    except KeyboardInterrupt:
        print_log("System", "Stopping all services...")
        for p in processes:
            # On Windows, terminate() is usually enough. 
            # Ideally we'd send SIGINT but Popen.send_signal(signal.CTRL_C_EVENT) is tricky.
            p.terminate() 
        print_log("System", "Goodbye!")

if __name__ == "__main__":
    main()
