#!/usr/bin/env python3
"""CT-BUG-025/026 regressions. No Docker/network/model. Run as ordinary user."""
import hashlib,json,os,shutil,stat,subprocess,tempfile,threading,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
RESULTS=[]
def rec(name,fn):
    t=time.monotonic()
    try:
        detail=fn();status='PASS'
    except Exception as e:
        detail=f'{type(e).__name__}: {e}';status='FAIL'
    RESULTS.append({'name':name,'status':status,'seconds':round(time.monotonic()-t,4),'detail':detail})
    print(json.dumps(RESULTS[-1]),flush=True)
def run(args,**kw): return subprocess.run(args,capture_output=True,text=True,timeout=5,**kw)
def reject(p): assert p.returncode!=0,(p.stdout,p.stderr)
assert os.geteuid()!=0,'run as ordinary user'
with tempfile.TemporaryDirectory(prefix='ct-log-safety-') as td:
    T=Path(td);B=T/'bundle'
    p=run(['bash','-c','source "$1"; emit_bundle "$2"','test',str(ROOT/'install-cybertiel.sh'),str(B)])
    assert p.returncode==0,p.stderr
    imp=B/'import-debug-log.py'
    source=imp.read_text()
    def ordinary():
        b=T/'ordinary';b.mkdir();project=b/'project';project.mkdir();src=b/'debug.log';raw=b'build-id=abc\nerror=fixture\x00\n';src.write_bytes(raw)
        p=run(['python3',str(imp),str(src),str(project)])
        assert p.returncode==0,(p.stdout,p.stderr)
        files=list((project/'logs').iterdir());assert len(files)==1;assert files[0].read_bytes()==raw
        assert stat.S_IMODE(files[0].stat().st_mode)==0o600
        assert 'sha256='+hashlib.sha256(raw).hexdigest() in p.stdout
        return {'returncode':0,'sha256_bound':True,'mode':'0600'}
    rec('v20_log_import_regular_stable_passes',ordinary)
    def fifo():
        b=T/'fifo';b.mkdir();project=b/'project';project.mkdir();src=b/'debug.fifo';os.mkfifo(src)
        started=time.monotonic()
        try:p=run(['python3',str(imp),str(src),str(project)])
        except subprocess.TimeoutExpired:raise AssertionError('FIFO blocked before rejection')
        elapsed=time.monotonic()-started;reject(p)
        return {'returncode':p.returncode,'seconds':round(elapsed,4),'blocking':False}
    rec('v20_log_import_fifo_rejected_without_block',fifo)
    def symlink():
        b=T/'symlink';b.mkdir();project=b/'project';project.mkdir();real=b/'real.log';real.write_text('x');src=b/'debug.log';src.symlink_to(real)
        p=run(['python3',str(imp),str(src),str(project)]);reject(p);return {'returncode':p.returncode}
    rec('v20_log_import_symlink_rejected',symlink)
    def oversized():
        b=T/'oversized';b.mkdir();project=b/'project';project.mkdir();src=b/'debug.log'
        with src.open('wb') as f:f.truncate(20*1024*1024+1)
        p=run(['python3',str(imp),str(src),str(project)]);reject(p);return {'returncode':p.returncode}
    rec('v20_log_import_oversized_rejected',oversized)
    def concurrent_mutation():
        b=T/'race';b.mkdir();project=b/'project';project.mkdir();src=b/'debug.log';size=20*1024*1024;src.write_bytes(b'A'*size)
        state={'stop':False,'writes':0}
        def writer():
            fd=os.open(src,os.O_WRONLY);bit=0
            try:
                while not state['stop']:
                    os.pwrite(fd,(b'B' if bit else b'A')*(1024*1024),0);os.fsync(fd);bit^=1;state['writes']+=1
            finally:os.close(fd)
        th=threading.Thread(target=writer);th.start();time.sleep(.02)
        try:p=run(['python3',str(imp),str(src),str(project)])
        finally:state['stop']=True;th.join()
        reject(p);assert state['writes']>0;assert not list(project.glob('logs/*'))
        assert 'changed during read' in p.stderr
        return {'returncode':p.returncode,'writer_iterations':state['writes'],'destination_created':False}
    rec('v20_log_import_concurrent_mutation_rejected',concurrent_mutation)
    def contracts():
        required=['os.O_NONBLOCK','os.O_NOFOLLOW','os.O_CLOEXEC','end=os.fstat(fd)','named=os.lstat(sys.argv[1])','_identity(st)!=_identity(end)','_identity(named)!=_identity(st)']
        assert all(x in source for x in required)
        return {'contracts':required}
    rec('v20_log_import_nonblocking_and_identity_contracts_present',contracts)
    def same_size_static():
        # A stable same-sized regular file must not be rejected just because size alone is unchanged.
        b=T/'same-size';b.mkdir();project=b/'project';project.mkdir();src=b/'debug.log';src.write_bytes(b'Q'*4096)
        p=run(['python3',str(imp),str(src),str(project)]);assert p.returncode==0,(p.stdout,p.stderr)
        return {'returncode':0,'stable_regular_file':True}
    rec('v20_log_import_stable_same_size_not_false_rejected',same_size_static)
report={'schema':'cybertiel-log-import-safety-tests/v1','installer_release':'2026-10-06.v25-r3','pass':sum(r['status']=='PASS' for r in RESULTS),'fail':sum(r['status']=='FAIL' for r in RESULTS),'results':RESULTS}
(ROOT/'LOG_IMPORT_SAFETY_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(1 if report['fail'] else 0)
