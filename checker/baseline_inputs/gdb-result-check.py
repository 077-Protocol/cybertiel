#!/usr/bin/env python3
"""Classify only observed ptrace denials as limited capability."""
import re
import sys
from pathlib import Path

def classify(rc, text):
    if rc == 0 and re.search(r"\$1 = 42(?:\s|$)", text):
        return "CT_GDB_RUNTIME_OK"
    if rc not in (124, 137, 143) and re.search(r"ptrace[^\n]*(?:Operation not permitted|Permission denied)|Could not trace the inferior process", text, re.I):
        return "CT_GDB_RUNTIME_SANDBOX_BLOCKED"
    raise ValueError("GDB failed without evidence of a sandbox ptrace denial")

if __name__ == "__main__":
    try:
        print(classify(int(sys.argv[1]), Path(sys.argv[2]).read_text(errors="replace")))
    except (ValueError, OSError, IndexError) as exc:
        raise SystemExit(str(exc))
