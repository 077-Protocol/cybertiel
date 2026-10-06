#!/usr/bin/env python3
"""Independent post-agent verifier. Run only in the constrained check container."""
import hashlib
import json
from pathlib import Path
import stat
import struct
import subprocess
import sys

source = Path("/workspace/src/math.cpp")
header = Path("/workspace/include/math.hpp")
debuglog = Path("/workspace/debug.log")
workspace=Path("/workspace")
for directory in [workspace, workspace/"src", workspace/"include"]:
    if directory.is_symlink() or not directory.is_dir():
        raise SystemExit("FAIL: unsafe workspace directory")
expected_files={"debug.log", "include/math.hpp", "src/math.cpp"}
found=set()
for path in workspace.rglob("*"):
    if path.is_symlink(): raise SystemExit("FAIL: symlink in smoke workspace")
    if path.is_dir():
        if path.relative_to(workspace).as_posix() not in {"src","include"}:
            raise SystemExit("FAIL: unexpected smoke directory")
        continue
    if not stat.S_ISREG(path.lstat().st_mode): raise SystemExit("FAIL: special file in smoke")
    found.add(path.relative_to(workspace).as_posix())
if found != expected_files: raise SystemExit("FAIL: smoke input file set changed")
for path,label,max_size in [(source,"math.cpp",65536),(header,"math.hpp",65536),(debuglog,"debug.log",1048576)]:
    if path.stat().st_size > max_size: raise SystemExit(f"FAIL: unexpected {label} size")
for path,original in [(header,"expected-math.hpp"),(debuglog,"expected-debug.log")]:
    if path.read_bytes() != (Path("/checks")/original).read_bytes():
        raise SystemExit("FAIL: immutable smoke input changed: "+path.name)
if source.read_bytes() == Path("/checks/original-math.cpp").read_bytes():
    raise SystemExit("FAIL: source did not change")
def run(args, timeout=120):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if p.returncode:
        print(p.stdout[-8000:], file=sys.stderr)
        print(p.stderr[-8000:], file=sys.stderr)
        raise SystemExit(f"FAIL: {args[0]} exited {p.returncode}")
    return p.stdout

common=["-std=c++17","-O0","-I/workspace/include","/workspace/src/math.cpp","/checks/accept.cpp"]
run(["g++",*common,"-o","/tmp/ct-accept"])
out=run(["/tmp/ct-accept"], timeout=15)
if out.strip() != "CT_NATIVE_ACCEPTANCE_OK":
    raise SystemExit("FAIL: unexpected native test output")
exe=Path("/artifacts/installation-check.exe")
run(["x86_64-w64-mingw32-g++-posix",*common,"-static","-o",str(exe)])
with exe.open("rb") as f:
    dos=f.read(64)
    if len(dos)!=64 or dos[:2]!=b"MZ":
        raise SystemExit("FAIL: not a PE executable")
    offset=struct.unpack_from("<I",dos,0x3c)[0]
    f.seek(offset); header_bytes=f.read(6)
    if header_bytes[:4]!=b"PE\0\0" or header_bytes[4:]!=b"\x64\x86":
        raise SystemExit("FAIL: not Windows x86_64 PE")
result={
    "status":"PASS",
    "debug_log_driven_multifile_fixture":True,
    "native_acceptance_cases":4,
    "windows_exe_built":True,
    "windows_exe_executed":False,
    "exe_sha256":hashlib.sha256(exe.read_bytes()).hexdigest(),
    "source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
    "header_sha256":hashlib.sha256(header.read_bytes()).hexdigest(),
    "debug_log_sha256":hashlib.sha256(debuglog.read_bytes()).hexdigest()
}
Path("/artifacts/check-result.json").write_text(json.dumps(result,indent=2)+"\n")
print(json.dumps(result))
