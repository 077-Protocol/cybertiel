#!/usr/bin/env python3
"""Start each Pi process from fresh settings, while keeping templates immutable.
Writable settings locks are required by Pi 1.0.x. No previous session/config is
imported. This is NOT an in-process sandbox against code running as the same UID.
"""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

TEMPLATES = Path("/opt/cybertiel/pi-config")
HOME = Path("/home/node")
CHECKER = "/opt/cybertiel/pi-settings-check.mjs"

def read_template(name):
    fd = os.open(TEMPLATES / name, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > 1048576:
            raise ValueError("invalid template type/size")
        with os.fdopen(os.dup(fd), "rb") as f:
            raw = f.read(1048577)
        if len(raw) > 1048576:
            raise ValueError("oversized template")
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError("template must be an object")
        return raw
    finally:
        os.close(fd)

def prepare():
    if os.geteuid() == 0:
        raise ValueError("agent must run non-root")
    os.umask(0o077)
    for directory in (TEMPLATES, HOME):
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("unsafe template/HOME directory")
    if os.access(TEMPLATES, os.W_OK):
        raise ValueError("baseline config is writable; refusing startup")
    home_stat = HOME.stat()
    if home_stat.st_uid != os.geteuid() or stat.S_IMODE(home_stat.st_mode) & 0o077:
        raise ValueError("HOME must be private and owned by agent UID")
    runtime = Path(tempfile.mkdtemp(prefix=".pi-run.", dir=HOME))
    for name in ("models.json", "settings.json"):
        raw = read_template(name)
        fd = os.open(runtime / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(raw)
    os.environ["HOME"] = str(HOME)
    os.environ["PI_CODING_AGENT_DIR"] = str(runtime)
    os.environ["PI_CODING_AGENT_SESSION_DIR"] = "/sessions"
    os.environ["PI_OFFLINE"] = "1"
    p = subprocess.run(["node", CHECKER], capture_output=True, text=True, timeout=90)
    if p.returncode:
        # Do not print model API-key/config bytes on a failed startup.
        raise ValueError("Pi settings SDK check failed; no agent started: " + p.stderr[-2000:])
    result = json.loads(p.stdout)
    if result.get("status") != "PASS":
        raise ValueError("missing Pi settings acceptance")
    return result

def main():
    result = prepare()
    if sys.argv[1:] == ["--ct-runtime-check"]:
        status = Path("/proc/self/status").read_text()
        sec = next((line.split(":", 1)[1].strip() for line in status.splitlines() if line.startswith("Seccomp:")), "MISSING")
        armor = Path("/proc/self/attr/current").read_text().strip()
        if sec != "2" or armor != "docker-default (enforce)":
            raise ValueError("runtime sandbox profile not confirmed")
        print("CT_AGENT_SECCOMP_MODE=" + sec)
        print("CT_AGENT_APPARMOR_PROFILE=" + armor)
        print("CT_PI_SETTINGS_RUNTIME_OK")
        print("CT_PI_CONFIG_ISOLATION_OK")
        print(json.dumps(result, sort_keys=True))
        return
    os.execvp("pi", ["pi", *sys.argv[1:]])

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, subprocess.SubprocessError) as exc:
        print("CT_AGENT_STARTUP_FAILED: " + str(exc), file=sys.stderr)
        raise SystemExit(72)
