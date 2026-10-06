#!/usr/bin/env bash
# Read-only host check. No downloads, packages, services, disk changes or secrets.
set -Eeuo pipefail
if [[ "$(uname -s)" != Linux ]]; then
    echo 'Voer dit op de Linux-server uit, niet op je Mac.' >&2; exit 2
fi
command -v python3 >/dev/null || { echo 'Python3 ontbreekt; nog niets installeren, stuur deze melding terug.' >&2; exit 2; }
python3 - <<'PY'
import json,os,platform,shutil
from pathlib import Path
release={}
for line in Path('/etc/os-release').read_text().splitlines():
    if '=' in line:
        k,v=line.split('=',1);release[k]=v.strip('"')
cpu=Path('/proc/cpuinfo').read_text()
models=[l.split(':',1)[1].strip() for l in cpu.splitlines() if l.startswith('model name')]
flags=next((l.split(':',1)[1].split() for l in cpu.splitlines() if l.startswith('flags')),[])
mem=next(int(l.split()[1])*1024 for l in Path('/proc/meminfo').read_text().splitlines() if l.startswith('MemTotal:'))
def free(p):
    q=Path(p)
    while not q.exists():q=q.parent
    return round(shutil.disk_usage(q).free/2**30,2)
fail=[]
if release.get('ID')!='ubuntu' or release.get('VERSION_ID')!='24.04':fail.append('Ubuntu 24.04 LTS vereist')
if platform.machine()!='x86_64':fail.append('Linux x86_64 vereist, niet ARM64')
if 'avx2' not in flags:fail.append('AVX2 niet zichtbaar')
if mem < 110*2**30:fail.append('Minder dan 110 GiB RAM zichtbaar')
if free('/srv')<90:fail.append('Minder dan 90 GiB vrij voor /srv')
if free('/')<5:fail.append('Minder dan 5 GiB vrij op /')
warn=[]
if not any('E5-2620 v4' in m for m in models):warn.append('CPU-naam wijkt af van de besproken E5-2620 v4; hardware bevestigen')
if Path('/var/run/reboot-required').exists():warn.append('Herstart vereist vóór installatie')
if Path('/opt/cybertiel').exists():warn.append('Bestaande /opt/cybertiel gevonden; geen automatische cross-version migratie')
out={'preflight':'BLOCKED' if fail else 'BASIS_PASS_NOT_INSTALLATION_PROOF',
     'os':release.get('PRETTY_NAME'),'architecture':platform.machine(),'kernel':platform.release(),
     'cpu_model':models[0] if models else 'unknown','logical_cpu_count':os.cpu_count(),
     'avx2': 'avx2' in flags,'ram_gib':round(mem/2**30,2),
     'free_srv_gib':free('/srv'),'free_root_gib':free('/'),
     'failures':fail,'warnings':warn,
     'not_proven':['DIMM type','actual Docker data disk free space','AppArmor/seccomp/network enforcement','model speed/262k RAM','Windows build compatibility']}
print(json.dumps(out,indent=2,ensure_ascii=False))
raise SystemExit(bool(fail))
PY
