#!/usr/bin/env python3
"""Check installed config still matches the observed target smoke. Not live qualification."""
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

BINDINGS={
 "pi_sri_manifest_sha256":"locks/pi-sri-manifest.json",
 "pi_derived_install_lock_sha256":"locks/pi-derived-install-package-lock.json",
 "runtime_config_sha256":"runtime.env",
 "agent_models_sha256":"config/models.json",
 "agent_settings_sha256":"config/settings.json",
 "agent_policy_sha256":"bundle/agent-policy.md",
 "agent_bash_timeout_extension_sha256":"bundle/bash-timeout.ts",
 "agent_entrypoint_sha256":"bundle/agent-entrypoint.py",
 "agent_settings_checker_sha256":"bundle/pi-settings-check.mjs",
}
def read_regular(path):
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
    try:
        st=os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size>4*1024*1024: raise ValueError("unsafe READY input")
        with os.fdopen(os.dup(fd),"rb") as f: return f.read(4*1024*1024+1)
    finally: os.close(fd)

def check(base,release):
    base=Path(base)
    d=json.loads(read_regular(base/"READY.json"))
    if d.get("status")!="INSTALLATION_SMOKE_PASS" or d.get("installer_id")!=release:
        raise ValueError("missing/wrong-release target acceptance")
    for key,rel in BINDINGS.items():
        if hashlib.sha256(read_regular(base/rel)).hexdigest()!=d.get(key):
            raise ValueError("config changed since installation smoke: "+rel)
    return {"status":"MATCH","meaning":"config matches previous target smoke, not current project correctness"}
if __name__=="__main__":
    try: check(sys.argv[1],sys.argv[2])
    except (OSError,ValueError,TypeError,KeyError,IndexError) as e:
        raise SystemExit("START GEWEIGERD: "+str(e)+". Herhaal de controle met dezelfde installer; verwijder de gate niet.")
