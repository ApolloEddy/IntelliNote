from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


PROJECT_ROOT = Path(__file__).resolve().parent
VENV_PYTHON = PROJECT_ROOT / "venv" / "Scripts" / "python.exe"
REDIS_SERVER = PROJECT_ROOT / "tools" / "redis" / "redis-server.exe"
RUNTIME_DIR = PROJECT_ROOT / ".runtime"
_ANSI_RESET = "\x1b[0m"
_SERVICE_COLORS = {
    "Redis": "\x1b[36m",
    "Worker": "\x1b[33m",
    "API": "\x1b[32m",
}

SERVICE_SPECS = {
    "redis": {
        "command": [str(REDIS_SERVER)],
        "port": 6379,
    },
    "api": {
        "command": [str(VENV_PYTHON), "main.py"],
        "port": 8000,
    },
    "worker": {
        "command": [
            str(VENV_PYTHON),
            "-m",
            "celery",
            "-A",
            "app.worker.celery_app",
            "worker",
            "--loglevel=INFO",
            "-P",
            "solo",
        ],
        "port": None,
    },
}


def _runtime_file(name: str, suffix: str) -> Path:
    return RUNTIME_DIR / f"{name}.{suffix}"


def _supports_color() -> bool:
    if os.getenv("NO_COLOR"):
        return False
    if not sys.stdout.isatty():
        return False
    if os.name != "nt":
        return True
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-11)
        if handle in (0, -1):
            return False
        mode = ctypes.c_uint32()
        if kernel32.GetConsoleMode(handle, ctypes.byref(mode)) == 0:
            return False
        # ENABLE_VIRTUAL_TERMINAL_PROCESSING
        if kernel32.SetConsoleMode(handle, mode.value | 0x0004) == 0:
            return False
        return True
    except Exception:
        return False


USE_COLOR = _supports_color()


def _tag(name: str) -> str:
    label = f"[{name}]"
    if not USE_COLOR:
        return label
    color = _SERVICE_COLORS.get(name)
    if not color:
        return label
    return f"{color}{label}{_ANSI_RESET}"


def _ensure_runtime_dir() -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)


def _creation_flags() -> int:
    if os.name != "nt":
        return 0
    return (
        getattr(subprocess, "DETACHED_PROCESS", 0)
        | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    )


def _write_pid(name: str, pid: int) -> None:
    _runtime_file(name, "pid").write_text(str(pid), encoding="utf-8")


def _read_pid(name: str) -> int | None:
    path = _runtime_file(name, "pid")
    if not path.exists():
        return None
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except Exception:
        return None


def _clear_pid(name: str) -> None:
    path = _runtime_file(name, "pid")
    if path.exists():
        path.unlink()


def _is_pid_running(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        result = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}"],
            capture_output=True,
            text=True,
            check=False,
        )
        return str(pid) in result.stdout
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _is_port_open(port: int, host: str = "127.0.0.1", timeout_s: float = 0.5) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout_s)
        return s.connect_ex((host, port)) == 0


def _wait_for_port(port: int, timeout_s: float) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if _is_port_open(port):
            return True
        time.sleep(0.2)
    return _is_port_open(port)


def _stop_pid_tree(pid: int) -> None:
    if pid <= 0:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(pid), "/F", "/T"],
            capture_output=True,
            text=True,
            check=False,
        )
        return
    try:
        os.kill(pid, 15)
    except OSError:
        pass


def _start_foreground(name: str, command: list[str]) -> subprocess.Popen:
    proc = subprocess.Popen(
        command,
        cwd=str(PROJECT_ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    print(f"{_tag(name)} started (pid={proc.pid})")
    return proc


def _relay_logs(name: str, proc: subprocess.Popen) -> None:
    if proc.stdout is None:
        return
    for line in proc.stdout:
        print(f"{_tag(name)} {line.rstrip()}")


def _stop_foreground_processes(processes: list[tuple[str, subprocess.Popen]]) -> None:
    for _, proc in reversed(processes):
        if proc.poll() is None:
            try:
                proc.terminate()
            except Exception:
                pass

    deadline = time.time() + 6.0
    while time.time() < deadline:
        if all(proc.poll() is not None for _, proc in processes):
            break
        time.sleep(0.2)

    for _, proc in reversed(processes):
        if proc.poll() is None:
            try:
                proc.kill()
            except Exception:
                pass


def _start_detached(name: str, command: list[str]) -> int:
    _ensure_runtime_dir()
    stdout_path = _runtime_file(name, "out.log")
    stderr_path = _runtime_file(name, "err.log")
    with open(stdout_path, "ab") as fout, open(stderr_path, "ab") as ferr:
        proc = subprocess.Popen(
            command,
            cwd=str(PROJECT_ROOT),
            stdout=fout,
            stderr=ferr,
            creationflags=_creation_flags(),
            close_fds=True,
        )
        return int(proc.pid)


def _start_service(name: str) -> None:
    spec = SERVICE_SPECS[name]
    managed_pid = _read_pid(name)
    if managed_pid and _is_pid_running(managed_pid):
        print(f"[{name}] already running (pid={managed_pid})")
        return
    if managed_pid and not _is_pid_running(managed_pid):
        _clear_pid(name)

    port = spec["port"]
    if isinstance(port, int) and _is_port_open(port):
        print(f"[{name}] port {port} already in use (existing external process), skip managed start")
        return

    pid = _start_detached(name, spec["command"])
    _write_pid(name, pid)
    print(f"[{name}] started (pid={pid})")


def _stop_service(name: str) -> None:
    pid = _read_pid(name)
    if not pid:
        print(f"[{name}] no managed pid")
        return
    if _is_pid_running(pid):
        _stop_pid_tree(pid)
        print(f"[{name}] stopped (pid={pid})")
    else:
        print(f"[{name}] stale pid cleaned (pid={pid})")
    _clear_pid(name)


def _fetch_health() -> tuple[bool, dict | str]:
    try:
        with urlopen("http://127.0.0.1:8000/health", timeout=2.0) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return True, json.loads(body)
    except HTTPError as exc:
        try:
            payload = json.loads(exc.read().decode("utf-8", errors="replace"))
            return False, payload
        except Exception:
            return False, str(exc)
    except (URLError, TimeoutError, OSError) as exc:
        return False, str(exc)


def cmd_run() -> int:
    if not REDIS_SERVER.exists():
        print(f"[system] redis-server not found: {REDIS_SERVER}")
        return 1
    if not VENV_PYTHON.exists():
        print(f"[system] python venv not found: {VENV_PYTHON}")
        return 1
    reuse_redis = False
    if _is_port_open(6379):
        reuse_redis = True
        print("[system] port 6379 already in use, reusing existing Redis.")
    if _is_port_open(8000):
        print("[system] port 8000 already in use. Stop existing API first or run `python manage.py status`.")
        return 1

    processes: list[tuple[str, subprocess.Popen]] = []
    log_threads: list[threading.Thread] = []

    try:
        if not reuse_redis:
            redis_proc = _start_foreground("Redis", SERVICE_SPECS["redis"]["command"])
            processes.append(("Redis", redis_proc))
            redis_log_thread = threading.Thread(target=_relay_logs, args=("Redis", redis_proc), daemon=True)
            redis_log_thread.start()
            log_threads.append(redis_log_thread)
            if not _wait_for_port(6379, timeout_s=6.0):
                print("[system] Redis failed to open port 6379.")
                return 1

        worker_proc = _start_foreground("Worker", SERVICE_SPECS["worker"]["command"])
        processes.append(("Worker", worker_proc))
        worker_log_thread = threading.Thread(target=_relay_logs, args=("Worker", worker_proc), daemon=True)
        worker_log_thread.start()
        log_threads.append(worker_log_thread)

        api_proc = _start_foreground("API", SERVICE_SPECS["api"]["command"])
        processes.append(("API", api_proc))
        api_log_thread = threading.Thread(target=_relay_logs, args=("API", api_proc), daemon=True)
        api_log_thread.start()
        log_threads.append(api_log_thread)
        if not _wait_for_port(8000, timeout_s=8.0):
            print("[system] API failed to open port 8000.")
            return 1

        print("[system] foreground mode running. Press Ctrl+C to stop all services.")
        while True:
            for name, proc in processes:
                code = proc.poll()
                if code is not None:
                    print(f"[system] {name} exited unexpectedly with code {code}.")
                    return 1 if code == 0 else int(code)
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n[system] stopping services...")
        return 0
    finally:
        _stop_foreground_processes(processes)
        for thread in log_threads:
            thread.join(timeout=0.2)


def cmd_up() -> int:
    if not REDIS_SERVER.exists():
        print(f"[system] redis-server not found: {REDIS_SERVER}")
        return 1
    if not VENV_PYTHON.exists():
        print(f"[system] python venv not found: {VENV_PYTHON}")
        return 1

    _start_service("redis")
    _wait_for_port(6379, timeout_s=6.0)
    _start_service("worker")
    time.sleep(0.8)
    _start_service("api")
    _wait_for_port(8000, timeout_s=8.0)
    print("[system] startup command finished. Run `python manage.py status` for full checks.")
    return 0


def cmd_down() -> int:
    for name in ("api", "worker", "redis"):
        _stop_service(name)
    return 0


def cmd_status() -> int:
    ok = True
    for name, spec in SERVICE_SPECS.items():
        pid = _read_pid(name)
        running = bool(pid and _is_pid_running(pid))
        port = spec["port"]
        port_ok = True if port is None else _is_port_open(port)
        if running:
            state = "running"
        elif port is not None and port_ok:
            state = "external"
        else:
            state = "stopped"
        if port is not None:
            state = f"{state}, port={port} {'open' if port_ok else 'closed'}"
        print(f"[{name}] {state} pid={pid or '-'}")
        if name in ("redis", "api") and not port_ok:
            ok = False

    healthy, payload = _fetch_health()
    if healthy:
        status = payload.get("status", "unknown") if isinstance(payload, dict) else "unknown"
        print(f"[health] {status}")
    else:
        ok = False
        print(f"[health] unavailable: {payload}")
    return 0 if ok else 1


def cmd_restart() -> int:
    cmd_down()
    time.sleep(0.8)
    return cmd_up()


def cmd_health() -> int:
    healthy, payload = _fetch_health()
    if isinstance(payload, dict):
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(str(payload))
    return 0 if healthy else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="IntelliNote service manager")
    parser.add_argument(
        "command",
        nargs="?",
        default="run",
        choices=("run", "up", "down", "status", "restart", "health"),
        help="Service command",
    )
    args = parser.parse_args()

    command_map = {
        "run": cmd_run,
        "up": cmd_up,
        "down": cmd_down,
        "status": cmd_status,
        "restart": cmd_restart,
        "health": cmd_health,
    }
    return command_map[args.command]()


if __name__ == "__main__":
    sys.exit(main())
