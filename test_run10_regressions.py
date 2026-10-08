#!/usr/bin/env python3
"""Run10 regression: project import must preserve and verify hardlink topology (CT-BUG-033)."""
import json, os, shlex, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
LAUNCH=(ROOT/'generated-config/cybertiel-launcher').read_text()
A=LAUNCH.index('# CT_PROJECT_IMPORT_FUNCTION_BEGIN'); B=LAUNCH.index('# CT_PROJECT_IMPORT_FUNCTION_END')
FUNC=LAUNCH[A:B]
RESULTS=[]
def rec(name,fn):
    t=time.monotonic()
    try: detail=fn(); status='PASS'
    except Exception as e: detail=f'{type(e).__name__}: {e}'; status='FAIL'
    row={'name':name,'status':status,'seconds':round(time.monotonic()-t,4),'detail':detail}; RESULTS.append(row); print(json.dumps(row),flush=True)
def run_import(data,src,timeout=20):
    script=f"set -Eeuo pipefail\nDATA={shlex.quote(str(data))}\n{FUNC}\nproject_import {shlex.quote(str(src))}\n"
    return subprocess.run(['bash'],input=script,text=True,capture_output=True,timeout=timeout)
assert os.geteuid()==0,'run as root'
with tempfile.TemporaryDirectory(prefix='ct-run10-') as td:
    T=Path(td)
    def contract():
        before=FUNC.split('# Detect an operator/editor/source update',1)[0]
        verify=FUNC.split('# Detect an operator/editor/source update',1)[1].split('pipe_rc=',1)[0]
        assert 'rsync -rltogpH ' in before
        assert 'rsync -rcnptH ' in verify
        return {'copy_preserves_hardlinks':True,'verifier_checks_hardlinks':True}
    rec('v25_copy_and_verifier_enable_hardlink_topology',contract)

    def preserve():
        src=T/'preserve-src'; data=T/'preserve-data'; src.mkdir(); data.mkdir(); (data/'project').mkdir()
        (src/'a.cpp').write_text('int value = 42;\n'); os.link(src/'a.cpp',src/'b.cpp')
        assert os.stat(src/'a.cpp').st_ino==os.stat(src/'b.cpp').st_ino
        p=run_import(data,src); assert p.returncode==0,(p.stdout,p.stderr)
        a=data/'project/a.cpp'; b=data/'project/b.cpp'
        sa,sb=os.stat(a),os.stat(b)
        assert sa.st_ino==sb.st_ino,(sa.st_ino,sb.st_ino)
        assert sa.st_nlink>=2 and sb.st_nlink>=2
        return {'rc':0,'same_inode':True,'nlink':sa.st_nlink}
    rec('v25_import_preserves_in_tree_hardlink_identity',preserve)

    def topology_race_rejected():
        # Reproduce the verifier's relevant property directly: source hardlinked, staging same bytes but split inodes.
        src=T/'race-src'; stage=T/'race-stage'; src.mkdir(); stage.mkdir()
        (src/'a').write_bytes(b'same\n'); os.link(src/'a',src/'b')
        (stage/'a').write_bytes(b'same\n'); (stage/'b').write_bytes(b'same\n')
        p=subprocess.run(['rsync','-rcnptH','--delete','--itemize-changes','--out-format=%i %n',
                          "--chmod=Du+rwx,Dgo-rwx,Fu+rw,Fgo-rwx,ugo-s",'--links','--no-devices','--no-specials','--',str(src)+'/',str(stage)+'/' ],
                         text=True,capture_output=True,timeout=10)
        assert p.returncode==0,(p.stdout,p.stderr)
        assert p.stdout.strip(), 'hardlink topology mismatch was invisible'
        assert 'b' in p.stdout or 'a' in p.stdout
        return {'rc':0,'difference_visible':True,'itemized':p.stdout.strip()[:200]}
    rec('v25_verifier_detects_split_hardlink_topology',topology_race_rejected)

report={'schema':'cybertiel-run10-regressions/v1','installer_release':'2026-10-06.v25-r3','passed':sum(x['status']=='PASS' for x in RESULTS),'failed':sum(x['status']=='FAIL' for x in RESULTS),'results':RESULTS}
(ROOT/'RUN10_REGRESSION_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(1 if report['failed'] else 0)
