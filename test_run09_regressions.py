#!/usr/bin/env python3
"""Run09 regression: CT-BUG-032 unsafe source symlinks must fail closed, not disappear silently."""
import json, os, shlex, stat, subprocess, tempfile, time
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
    row={'name':name,'status':status,'seconds':round(time.monotonic()-t,4),'detail':detail};RESULTS.append(row);print(json.dumps(row),flush=True)
def run_import(data,src,timeout=10):
    script=f"set -Eeuo pipefail\nDATA={shlex.quote(str(data))}\n{FUNC}\nproject_import {shlex.quote(str(src))}\n"
    return subprocess.run(['bash'],input=script,text=True,capture_output=True,timeout=timeout)
assert os.geteuid()==0,'run as root'
with tempfile.TemporaryDirectory(prefix='ct-run09-') as td:
    T=Path(td)
    def contract():
        copy=FUNC.split('# Detect an operator/editor/source update',1)[0]
        verify=FUNC.split('# Detect an operator/editor/source update',1)[1]
        assert '--links --safe-links --no-devices --no-specials' in copy
        # Verification must see links the safe copy intentionally skipped.
        assert '--links --safe-links --no-devices --no-specials' not in verify.split('pipe_rc=',1)[0]
        assert '--links --no-devices --no-specials' in verify.split('pipe_rc=',1)[0]
        return {'copy_safe_links':True,'verify_safe_links':False}
    rec('v24_verifier_does_not_hide_skipped_unsafe_symlink',contract)

    def unsafe_rejected():
        src=T/'unsafe-src'; data=T/'unsafe-data'; src.mkdir();data.mkdir();(data/'project').mkdir()
        (T/'outside.txt').write_text('outside\n')
        (src/'main.cpp').write_text('int main(){}\n')
        (src/'escape').symlink_to('../outside.txt')
        p=run_import(data,src)
        assert p.returncode!=0,(p.stdout,p.stderr)
        assert not any((data/'project').iterdir()),'incomplete tree published despite unsafe symlink'
        assert not list(data.glob('.project-import.*')) and not list(data.glob('.project-verify.*'))
        return {'rc':p.returncode,'canonical_empty':True,'unsafe_symlink_published':False}
    rec('v24_unsafe_source_symlink_rejected_atomically',unsafe_rejected)

    def safe_preserved():
        src=T/'safe-src';data=T/'safe-data';src.mkdir();data.mkdir();(data/'project').mkdir()
        (src/'target.txt').write_text('ok\n');(src/'sub').mkdir();(src/'sub/link').symlink_to('../target.txt')
        p=run_import(data,src);assert p.returncode==0,(p.stdout,p.stderr)
        link=data/'project/sub/link'
        assert link.is_symlink() and os.readlink(link)=='../target.txt'
        assert (link.parent/os.readlink(link)).resolve().read_text()=='ok\n'
        return {'rc':0,'safe_relative_symlink_preserved':True,'target':os.readlink(link)}
    rec('v24_safe_internal_symlink_preserved',safe_preserved)

report={'schema':'cybertiel-run09-regressions/v1','installer_release':'2026-10-06.v25','passed':sum(x['status']=='PASS' for x in RESULTS),'failed':sum(x['status']=='FAIL' for x in RESULTS),'results':RESULTS}
(ROOT/'RUN09_REGRESSION_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(1 if report['failed'] else 0)
