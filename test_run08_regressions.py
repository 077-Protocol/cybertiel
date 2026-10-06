#!/usr/bin/env python3
"""Run08 regressions: stop/checker coordination + project metadata generation integrity."""
import fcntl, json, os, pathlib, shlex, stat, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
LAUNCH=(ROOT/'generated-config/cybertiel-launcher').read_text()
RESULTS=[]

def rec(name,fn):
    t=time.monotonic()
    try:
        d=fn(); st='PASS'
    except Exception as e:
        d=f'{type(e).__name__}: {e}'; st='FAIL'
    row={'name':name,'status':st,'seconds':round(time.monotonic()-t,4),'detail':d}
    RESULTS.append(row); print(json.dumps(row),flush=True)

def launcher_fixture(td):
    td=Path(td); base=td/'opt/cybertiel'; data=td/'srv/cybertiel'; binp=td/'bin'
    base.mkdir(parents=True);data.mkdir(parents=True);binp.mkdir()
    (base/'runtime.env').write_text("LLAMA_IMAGE=sha256:"+'a'*64+"\nAGENT_IMAGE=sha256:"+'b'*64+"\n")
    (base/'runtime.env').chmod(0o600)
    log=td/'docker.log';log.write_text('')
    docker=binp/'docker'
    docker.write_text(r'''#!/usr/bin/env bash
printf '%q ' "$@" >> "$CT_DOCKER_LOG"; printf '\n' >> "$CT_DOCKER_LOG"
if [[ "$1" == inspect && "$2" == -f ]]; then printf '%s\n' '2026-10-06.v25'; exit 0; fi
if [[ "$1" == stop ]]; then exit 0; fi
if [[ "$1" == container && "$2" == inspect ]]; then exit 1; fi
exit 0
''')
    docker.chmod(0o755)
    s=LAUNCH.replace('export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',f'export PATH={binp}:/usr/bin:/bin')
    s=s.replace('BASE=/opt/cybertiel',f'BASE={base}').replace('DATA=/srv/cybertiel',f'DATA={data}')
    lp=td/'launcher';lp.write_text(s);lp.chmod(0o755)
    return lp,base,log

def stop_contract():
    block=LAUNCH[LAUNCH.index('    stop)'):LAUNCH.index('esac',LAUNCH.index('    stop)'))]
    assert 'acquire_base_coordination_lock' in block
    assert block.index('acquire_base_coordination_lock') < block.index('docker stop')
    return {'base_lock_before_stop':True}
rec('v24_stop_requires_persistent_coordination_lock',stop_contract)

def stop_blocked():
    with tempfile.TemporaryDirectory(prefix='ct-v23-stop-') as td:
        lp,base,log=launcher_fixture(td)
        fd=os.open(base,os.O_RDONLY|os.O_DIRECTORY); fcntl.flock(fd,fcntl.LOCK_SH|fcntl.LOCK_NB)
        env=os.environ.copy();env['CT_DOCKER_LOG']=str(log)
        p=subprocess.run([str(lp),'stop'],capture_output=True,text=True,env=env,timeout=5)
        os.close(fd)
        text=log.read_text()
        assert p.returncode!=0,(p.stdout,p.stderr,text)
        assert 'stop -t' not in text,text
        return {'rc':p.returncode,'docker_stop_called':False}
rec('v24_checker_shared_lock_blocks_stop_mutation',stop_blocked)

def stop_positive():
    with tempfile.TemporaryDirectory(prefix='ct-v23-stop-ok-') as td:
        lp,base,log=launcher_fixture(td)
        env=os.environ.copy();env['CT_DOCKER_LOG']=str(log)
        p=subprocess.run([str(lp),'stop'],capture_output=True,text=True,env=env,timeout=5)
        text=log.read_text()
        assert p.returncode==0,(p.stdout,p.stderr,text)
        assert text.count('stop -t 20')==2,text
        return {'rc':0,'stopped_managed_containers':2}
rec('v24_stop_still_works_when_coordination_is_free',stop_positive)

# Extract actual project_import function from generated launcher.
a=LAUNCH.index('# CT_PROJECT_IMPORT_FUNCTION_BEGIN'); b=LAUNCH.index('# CT_PROJECT_IMPORT_FUNCTION_END')
FUNC=LAUNCH[a:b]

def project_contract():
    for x in ["rsync -rltogp", "rsync -rcnpt", "--chmod='Du+rwx,Dgo-rwx,Fu+rw,Fgo-rwx,ugo-s'"]:
        assert x in FUNC,x
    return {'copy_preserves_normalized_owner_execute':True,'verification_checks_perms_and_mtime':True}
rec('v24_project_metadata_contract',project_contract)

def mode_race():
    with tempfile.TemporaryDirectory(prefix='ct-v23-mode-race-') as td:
        t=Path(td); src=t/'src'; data=t/'data'; bind=t/'bin';src.mkdir();data.mkdir();(data/'project').mkdir();bind.mkdir()
        modefile=src/'build.sh'; modefile.write_text('#!/bin/sh\necho ok\n'); modefile.chmod(0o755)
        (src/'main.cpp').write_text('int main(){return 0;}\n')
        count=t/'count';count.write_text('0')
        wrapper=bind/'rsync'
        wrapper.write_text(r'''#!/usr/bin/env bash
n=$(cat "$CT_COUNT"); n=$((n+1)); printf '%s' "$n" > "$CT_COUNT"
/usr/bin/rsync "$@"; rc=$?
if [[ $rc -eq 0 && $n -eq 1 ]]; then chmod 0644 -- "$CT_MODEFILE"; fi
exit "$rc"
''');wrapper.chmod(0o755)
        script=f"set -Eeuo pipefail\nDATA={shlex.quote(str(data))}\n{FUNC}\nproject_import {shlex.quote(str(src))}\n"
        env=os.environ.copy(); env['PATH']=f'{bind}:/usr/bin:/bin';env['CT_COUNT']=str(count);env['CT_MODEFILE']=str(modefile)
        p=subprocess.run(['bash'],input=script,text=True,capture_output=True,env=env,timeout=10)
        assert p.returncode!=0,(p.stdout,p.stderr)
        assert not any((data/'project').iterdir()),'mode-drift generation was published'
        assert modefile.stat().st_mode & stat.S_IXUSR == 0
        return {'rc':p.returncode,'canonical_empty':True,'mode_change_rejected':True}
rec('v24_project_owner_execute_race_rejected',mode_race)

def stable_modes():
    with tempfile.TemporaryDirectory(prefix='ct-v23-modes-') as td:
        t=Path(td);src=t/'src';data=t/'data';src.mkdir();data.mkdir();(data/'project').mkdir()
        x=src/'run.sh';x.write_text('#!/bin/sh\nexit 0\n');x.chmod(0o0555)
        y=src/'readme.txt';y.write_text('x\n');y.chmod(0o0444)
        script=f"set -Eeuo pipefail\nDATA={shlex.quote(str(data))}\n{FUNC}\nproject_import {shlex.quote(str(src))}\n"
        p=subprocess.run(['bash'],input=script,text=True,capture_output=True,timeout=10)
        assert p.returncode==0,(p.stdout,p.stderr)
        dx=data/'project/run.sh';dy=data/'project/readme.txt'
        assert stat.S_IMODE(dx.stat().st_mode)==0o700,oct(stat.S_IMODE(dx.stat().st_mode))
        assert stat.S_IMODE(dy.stat().st_mode)==0o600,oct(stat.S_IMODE(dy.stat().st_mode))
        assert dx.stat().st_uid==1000 and dy.stat().st_uid==1000
        return {'executable_mode':'0700','nonexec_mode':'0600','owner':1000}
rec('v24_project_import_normalizes_editable_private_modes',stable_modes)

report={'schema':'cybertiel-run08-regressions/v1','installer_release':'2026-10-06.v25','passed':sum(r['status']=='PASS' for r in RESULTS),'failed':sum(r['status']=='FAIL' for r in RESULTS),'results':RESULTS}
(ROOT/'RUN08_REGRESSION_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(1 if report['failed'] else 0)
