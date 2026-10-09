#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
unset PYTHONPATH PYTHONHOME PYTHONSTARTUP BASH_ENV ENV
[[ -x /usr/bin/python3 ]] || { echo 'Python3 ontbreekt. Geen wijzigingen uitgevoerd.' >&2; exit 2; }
HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec /usr/bin/python3 -I - "$HERE" "$@" <<'CYBERTIEL_SETUP_PY'
#!/usr/bin/env python3
"""Install-and-diagnose coordinator. Does not loop blindly or bypass a failed gate.
Run only on the intended server. All mutations require explicit --install.
The installer/checker are staged from SHA-256-verified bytes in a private directory.
"""
import argparse, hashlib, json, os, signal, stat, subprocess, sys, tempfile
from pathlib import Path

# Replaced when the final scripts are frozen; regenerated wrapper embeds this file.
PINS = {'install-cybertiel.sh': 'df7d5acfcf595eee7c979b44e7aededac8cd107dc771c8ee18489d1a9578b4f7', 'check-cybertiel-server.sh': 'baea056d4d1cdc292bd1e758e3ab9d8141d0d93a8b7a6c7273fc155b4da01bb6'}
ENV = {'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','HOME':'/root','LANG':'C.UTF-8',
       'TERM':os.environ.get('TERM','xterm-256color')}
MAX_SCRIPT = 4 * 1024 * 1024
EXPECTED_CHECKER = 'CT-CHECK-2.9.2'
CHECK_STATUSES = ('PASS','FAIL','WARN','UNTESTED','NOT_APPLICABLE')



def checked_bytes(path, digest):
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC)
    try:
        s=os.fstat(fd)
        if not stat.S_ISREG(s.st_mode) or s.st_nlink!=1 or s.st_size>MAX_SCRIPT:
            raise ValueError('Script is geen gewoon enkelvoudig bestand of te groot.')
        data=b''
        while len(data)<=MAX_SCRIPT:
            block=os.read(fd,min(65536,MAX_SCRIPT+1-len(data)))
            if not block:break
            data+=block
        e=os.fstat(fd)
        if (s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)!=(e.st_dev,e.st_ino,e.st_size,e.st_mtime_ns,e.st_ctime_ns):
            raise ValueError('Script veranderde tijdens het lezen.')
        if len(data)>MAX_SCRIPT or hashlib.sha256(data).hexdigest()!=digest:
            raise ValueError('Script-hash wijkt af; geen uitvoering.')
        return data
    finally:os.close(fd)


def stage(source, dest, pins):
    # Read/verify ALL scripts before any is executed. Copy those exact bytes,
    # not the original pathname after a separate check.
    blobs={name:checked_bytes(source/name,digest) for name,digest in pins.items()}
    result={}
    for name,data in blobs.items():
        if Path(name).name!=name:raise ValueError('Ongeldige scriptnaam.')
        target=dest/name
        fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
        result[name]=target
    return result


class _ForwardedSignal(Exception):
    def __init__(self, signum):
        super().__init__(signum);self.signum=signum


def run_command(argv, logfile=None):
    out=open(logfile,'xb',buffering=0) if logfile else None
    if out:os.chmod(logfile,0o600)
    old_handlers={}
    def forwarded(signum, frame):
        raise _ForwardedSignal(signum)
    p=None
    try:
        # The child is its own process group, so coordinator termination must not
        # orphan an installer that keeps mutating the host after setup has exited.
        for sig in (signal.SIGTERM,signal.SIGHUP):
            old_handlers[sig]=signal.signal(sig,forwarded)
        p=subprocess.Popen(argv,env=ENV,stdout=out,stderr=subprocess.STDOUT if out else None,start_new_session=True)
        try:
            return p.wait()
        except KeyboardInterrupt:
            received=signal.SIGINT
        except _ForwardedSignal as exc:
            received=exc.signum
        # Ignore repeat HUP/TERM while the owned group is being reaped.
        for sig in old_handlers:signal.signal(sig,signal.SIG_IGN)
        try:os.killpg(p.pid,signal.SIGTERM)
        except ProcessLookupError:pass
        try:p.wait(timeout=15)
        except subprocess.TimeoutExpired:
            try:os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError:pass
            p.wait()
        return 128+received
    finally:
        for sig,handler in old_handlers.items():signal.signal(sig,handler)
        if out:out.close()


def locate_checker_report(dest):
    """Return exactly one safely read checker report plus its parsed object/hash."""
    found=[]
    for child in dest.iterdir():
        if not child.name.startswith('cybertiel-check-'):continue
        try:
            ds=os.lstat(child)
            if not stat.S_ISDIR(ds.st_mode) or ds.st_uid!=0 or stat.S_IMODE(ds.st_mode)!=0o700:continue
            report=child/'report.json'
            fd=os.open(report,os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC)
            try:
                st=os.fstat(fd)
                if not stat.S_ISREG(st.st_mode) or st.st_uid!=0 or st.st_nlink!=1 or stat.S_IMODE(st.st_mode)&0o022 or st.st_size<2 or st.st_size>16*1024*1024:continue
                raw=b''
                while len(raw)<=16*1024*1024:
                    b=os.read(fd,min(65536,16*1024*1024+1-len(raw)))
                    if not b:break
                    raw+=b
                end=os.fstat(fd)
                if len(raw)>16*1024*1024:continue
                if (st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns,st.st_ctime_ns)!=(end.st_dev,end.st_ino,end.st_size,end.st_mtime_ns,end.st_ctime_ns):continue
                obj=json.loads(raw)
                if not isinstance(obj,dict) or obj.get('schema')!='cybertiel-diagnostic/v1':continue
            finally:os.close(fd)
            found.append((report,obj,hashlib.sha256(raw).hexdigest()))
        except (OSError,ValueError,TypeError,json.JSONDecodeError,UnicodeError):
            continue
    return found[0] if len(found)==1 else (None,None,None)


def validate_checker_semantics(obj, expected_runtime):
    """Fail closed on report/exit contradictions instead of trusting an exit code alone."""
    if not isinstance(obj,dict):return 'missing report object'
    if obj.get('checker')!=EXPECTED_CHECKER:return 'unexpected checker identity'
    checks=obj.get('checks');counts=obj.get('counts');status=obj.get('status')
    if not isinstance(checks,list) or not isinstance(counts,dict):return 'missing checks/counts'
    seen=set();calc={k:0 for k in CHECK_STATUSES}
    for row in checks:
        if not isinstance(row,dict):return 'non-object check row'
        rid=row.get('id');st=row.get('status')
        if not isinstance(rid,str) or not rid or rid in seen:return 'invalid/duplicate check id'
        if st not in calc:return 'invalid check status'
        seen.add(rid);calc[st]+=1
    for key,val in counts.items():
        if key not in calc or type(val) is not int or val<0:return 'invalid counts'
    normalized={k:int(counts.get(k,0)) for k in CHECK_STATUSES}
    if normalized!=calc:return 'counts do not match checks'
    expected_status='ISSUES_FOUND' if calc['FAIL'] else ('INCOMPLETE' if calc['UNTESTED'] else 'CHECKED_NOT_PROJECT_QUALIFIED')
    if status!=expected_status:return 'overall status contradicts checks'
    if obj.get('runtime_opt_in') is not expected_runtime or obj.get('full_model_hash_opt_in') is not expected_runtime:
        return 'runtime/hash opt-in evidence contradicts invocation'
    if obj.get('downloads_or_package_changes') is not False or obj.get('user_project_executed') is not False or obj.get('secrets_or_project_log_contents_included') is not False:
        return 'checker safety declarations missing/contradictory'
    return None


def checker_expected_exit(obj):
    counts=obj['counts']
    return 1 if int(counts.get('FAIL',0)) else 2 if int(counts.get('UNTESTED',0)) else 0

def outcome(mode, irc, crc, report_state):
    if report_state=='missing':
        return ('INSTALL_FAILED_CHECKER_REPORT_MISSING' if mode=='install' and irc!=0 else 'CHECK_FAILED_NO_VALID_REPORT'),1
    if report_state!='valid':
        return ('INSTALL_FAILED_CHECKER_REPORT_CONTRADICTION' if mode=='install' and irc!=0 else 'CHECKER_REPORT_CONTRADICTION'),1
    if mode=='install' and irc!=0:return 'INSTALL_FAILED_REPORT_AVAILABLE',1
    if crc==1:return 'POSTCHECK_ISSUES_FOUND',1
    if crc==2:return ('INSTALL_SMOKE_PASSED_WITH_UNTESTED_ITEMS' if mode=='install' else 'CHECK_INCOMPLETE'),2
    if crc!=0:return 'CHECK_FAILED_TO_COMPLETE',1
    return ('INSTALL_SMOKE_AND_CHECK_PASS_NOT_PROJECT_QUALIFICATION' if mode=='install' else 'CHECK_PASS_NOT_PROJECT_QUALIFICATION'),0

def drive(mode, paths, dest, startup, smoke, jobs, runner=run_command):
    irc=None
    if mode=='install':
        args=['/usr/bin/bash',str(paths['install-cybertiel.sh']),'--install','--accept-official-q8',
              '--startup-timeout',str(startup),'--smoke-timeout',str(smoke),'--build-jobs',str(jobs)]
        irc=runner(args,None)
    args=['/usr/bin/bash',str(paths['check-cybertiel-server.sh']),
          '--installer',str(paths['install-cybertiel.sh']),'--output-parent',str(dest)]
    if mode=='install' and irc==0:args+=['--deep-model-hash','--runtime']
    crc=runner(args,dest/'checker-output.txt')
    checker_report,checker_obj,checker_sha=locate_checker_report(dest)
    expected_runtime=(mode=='install' and irc==0)
    if checker_report is None:
        report_state='missing';semantic_error='checker report ontbreekt/onveilig/niet uniek'
    else:
        semantic_error=validate_checker_semantics(checker_obj,expected_runtime)
        if semantic_error is None and checker_expected_exit(checker_obj)!=crc:
            semantic_error='checker exitcode contradicts report counts'
        report_state='valid' if semantic_error is None else 'contradiction'
    status,rc=outcome(mode,irc,crc,report_state)
    result={'schema':'cybertiel-setup/v1','installer_release':'2026-10-06.v25-r3','package_revision':'2026-10-06.v25-r3.2',
        'status':status,'installer_exit_code':irc,'checker_exit_code':crc,
        'checker_report_verified':report_state=='valid',
        'checker_report':str(checker_report) if checker_report is not None else None,
        'checker_report_sha256':checker_sha,'checker_report_status':checker_obj.get('status') if isinstance(checker_obj,dict) else None,
        'checker_report_semantic_error':semantic_error,
        'automatic_retry':False,'project_correctness_proven':False,'directory':str(dest),
        'note':'Exitcode en checker-report moeten inhoudelijk overeenkomen. Exitcode 2 betekent ongeteste onderdelen, niet automatisch een installatiefout.'}
    tmp=dest/'setup-result.json.tmp'
    with open(tmp,'x',encoding='utf8') as f:json.dump(result,f,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
    os.chmod(tmp,0o600);os.replace(tmp,dest/'setup-result.json')
    fd=os.open(dest,os.O_DIRECTORY|os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)
    return result,rc


def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv)
    if not argv:raise ValueError('Interne scriptdirectory ontbreekt.')
    source=Path(argv.pop(0)).absolute()
    ap=argparse.ArgumentParser(description='CyberTiel v25 installatie gevolgd door onafhankelijke servercontrole.')
    g=ap.add_mutually_exclusive_group();g.add_argument('--install',action='store_true');g.add_argument('--check',action='store_true');g.add_argument('--plan',action='store_true')
    ap.add_argument('--accept-official-q8',action='store_true')
    ap.add_argument('--startup-timeout',type=int,default=7200);ap.add_argument('--smoke-timeout',type=int,default=14400);ap.add_argument('--build-jobs',type=int,default=4)
    a=ap.parse_args(argv)
    if not 60<=a.startup_timeout<=7200 or not 60<=a.smoke_timeout<=14400 or not 1<=a.build_jobs<=16:ap.error('Timeout/jobs buiten ondersteund bereik.')
    if not a.install and not a.check:
        print('PLAN: verifieer v25-r3 installer + checker2.9; installeer alleen met --install --accept-official-q8; voer daarna checker uit. Geen wijzigingen uitgevoerd.\nGebruik op de bedoelde Ubuntu-server: sudo bash setup-cybertiel.sh --install --accept-official-q8');return 0
    if a.install and not a.accept_official_q8:ap.error('Expliciet --accept-official-q8 nodig; dit is Q8, geen BF16.')
    if sys.platform!='linux' or os.geteuid()!=0:ap.error('Voer installatie/controle op de Linux-server uit met sudo, niet op de Mac.')
    os.umask(0o077)
    dest=Path(tempfile.mkdtemp(prefix='cybertiel-setup-',dir='/var/tmp'));dest.chmod(0o700)
    print('Privaat installatie-/controlerapport: '+str(dest),flush=True)
    paths=stage(source,dest,PINS)
    result,rc=drive('install' if a.install else 'check',paths,dest,a.startup_timeout,a.smoke_timeout,a.build_jobs)
    print('\nSTATUS: '+result['status'])
    print('Samenvatting: '+str(dest/'setup-result.json'))
    print('Checker-uitvoer: '+str(dest/'checker-output.txt'))
    log=dest/'checker-output.txt'
    if log.is_file():print(log.read_text(errors='replace')[-16000:])
    print('Geen project- of Windows-runtimegarantie. Bij een fout: stuur het rapport; omzeil geen gates.')
    return rc


if __name__=='__main__':
    try:raise SystemExit(main())
    except (ValueError,OSError) as exc:
        print('SETUP GESTOPT: '+str(exc),file=sys.stderr);raise SystemExit(1)

CYBERTIEL_SETUP_PY
