#!/usr/bin/env python3
"""CT-BUG-027/028 regressions for the exact emitted project_import() function. Root, no Docker/network/model."""
import json, os, shlex, shutil, signal, stat, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
RESULTS=[]

def rec(name,fn):
    t=time.monotonic()
    try:
        detail=fn(); status='PASS'
    except Exception as e:
        detail=f'{type(e).__name__}: {e}'; status='FAIL'
    row={'name':name,'status':status,'seconds':round(time.monotonic()-t,4),'detail':detail}
    RESULTS.append(row); print(json.dumps(row),flush=True)

def extract_function():
    text=(ROOT/'generated-config/cybertiel-launcher').read_text()
    a=text.index('# CT_PROJECT_IMPORT_FUNCTION_BEGIN')
    b=text.index('# CT_PROJECT_IMPORT_FUNCTION_END')
    block=text[a:b]
    assert block.count('project_import() (')==1
    return block

FUNC=extract_function()

def script_for(data,src):
    return f"set -Eeuo pipefail\nDATA={shlex.quote(str(data))}\n{FUNC}\nproject_import {shlex.quote(str(src))}\n"

def run_import(data,src,timeout=20):
    return subprocess.run(['bash'],input=script_for(data,src),text=True,capture_output=True,timeout=timeout)

def empty(path): return not any(path.iterdir())

assert os.geteuid()==0,'run as root'
with tempfile.TemporaryDirectory(prefix='ct-project-import-') as td:
    T=Path(td)
    def stable():
        src=T/'stable-src'; data=T/'stable-data'; src.mkdir(); data.mkdir(); (data/'project').mkdir()
        (src/'main.cpp').write_text('int main(){return 0;}\n'); (src/'sub').mkdir(); (src/'sub'/'x.txt').write_text('x\n')
        p=run_import(data,src); assert p.returncode==0,(p.stdout,p.stderr)
        dst=data/'project'; assert (dst/'main.cpp').read_text()==(src/'main.cpp').read_text(); assert (dst/'sub'/'x.txt').read_text()=='x\n'
        assert dst.stat().st_uid==1000 and stat.S_IMODE(dst.stat().st_mode)==0o750
        assert not list(data.glob('.project-import.*')) and not list(data.glob('.project-verify.*'))
        return {'rc':0,'published_tree_owner':1000,'mode':'0750','staging_left':False}
    rec('v24_project_import_stable_atomic_publish',stable)

    def interrupted_retry():
        src=T/'interrupt-src'; data=T/'interrupt-data'; src.mkdir(); data.mkdir(); target=data/'project'; target.mkdir()
        (src/'000-marker.txt').write_text('before\n')
        big=src/'zzz-large.bin'; big.touch(); os.truncate(big,1024*1024*1024)
        with big.open('r+b') as f: f.write(b'A'); f.seek(-1,2); f.write(b'A')
        p=subprocess.Popen(['bash'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
        p.stdin.write(script_for(data,src)); p.stdin.close()
        staged=None
        for _ in range(1500):
            candidates=list(data.glob('.project-import.*'))
            if candidates and any(c.iterdir() for c in candidates): staged=candidates[0]; break
            if p.poll() is not None: break
            time.sleep(.002)
        assert staged is not None,'transfer finished before interruption probe'
        os.killpg(p.pid,signal.SIGKILL); p.wait(timeout=5)
        assert empty(target),'canonical project became non-empty after killed staging import'
        stale=list(data.glob('.project-import.*')); assert stale,'SIGKILL did not leave the intended stale-stage fixture'
        # Retry must reclaim only the private root staging area and publish cleanly.
        big.unlink(); (src/'small.txt').write_text('retry\n')
        q=run_import(data,src); assert q.returncode==0,(q.stdout,q.stderr)
        assert (data/'project'/'small.txt').read_text()=='retry\n','retry output missing/wrong'
        assert not list(data.glob('.project-import.*')) and not list(data.glob('.project-verify.*')),'stale staging/verify remains after retry'
        return {'killed_rc':p.returncode,'canonical_empty_after_kill':True,'retry_rc':q.returncode,'stale_reclaimed':True}
    rec('v24_project_import_interruption_keeps_canonical_empty_and_retryable',interrupted_retry)

    def source_race():
        src=T/'race-src'; prep=T/'race-prep'; data=T/'race-data'
        src.mkdir(); prep.mkdir(); data.mkdir(); target=data/'project'; target.mkdir()
        size=512*1024*1024
        old=src/'000-large.bin'; new=prep/'000-large.bin.B'
        for p in (old,new): p.touch(); os.truncate(p,size)
        with old.open('r+b') as f: f.write(b'A'); f.seek(-1,2); f.write(b'A')
        with new.open('r+b') as f: f.write(b'B'); f.seek(-1,2); f.write(b'B')
        (src/'zzz-generation.txt').write_text('A\n')
        p=subprocess.Popen(['bash'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
        p.stdin.write(script_for(data,src)); p.stdin.close()
        copying=False
        for _ in range(2000):
            stages=list(data.glob('.project-import.*'))
            if stages and any(stages[0].glob('*000-large.bin*')): copying=True; break
            if p.poll() is not None: break
            time.sleep(.002)
        assert copying,'could not place source mutation during copy'
        os.replace(new,old)
        tmp=src/'zzz-generation.txt.new'; tmp.write_text('B\n'); os.replace(tmp,src/'zzz-generation.txt')
        rc=p.wait(timeout=30); out=p.stdout.read(); err=p.stderr.read()
        assert rc!=0,(out,err)
        assert empty(target),'mixed generation was published'
        assert 'veranderde tijdens import' in err or 'verificatie mislukte' in err,(out,err)
        assert not list(data.glob('.project-import.*')) and not list(data.glob('.project-verify.*'))
        return {'rc':rc,'mixed_generation_published':False,'staging_cleaned':True}
    rec('v24_project_import_source_generation_race_rejected',source_race)

    def contracts():
        required=['.project-import.XXXXXXXX','rsync -rcnptH --delete --itemize-changes',"--out-format='%i'",'pipe_rc=("${PIPESTATUS[@]}")','mv -T -- "$staging" "$DATA/project"','rm -rf --one-file-system']
        assert all(x in FUNC for x in required),[x for x in required if x not in FUNC]
        # Direct destination rsync from the old implementation must be absent from the function.
        assert '"$src/" "$DATA/project/"' not in FUNC
        return {'contracts':required,'direct_copy_to_canonical':False}
    rec('v24_project_import_staging_verification_contracts_present',contracts)

report={'schema':'cybertiel-project-import-safety-tests/v1','installer_release':'2026-10-06.v25','passed':sum(r['status']=='PASS' for r in RESULTS),'failed':sum(r['status']=='FAIL' for r in RESULTS),'results':RESULTS}
(ROOT/'PROJECT_IMPORT_SAFETY_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(1 if report['failed'] else 0)
