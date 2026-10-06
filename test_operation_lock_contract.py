#!/usr/bin/env python3
import json, os, re, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
INSTALLER=(ROOT/'install-cybertiel.sh').read_text()
results=[]
def check(name, ok, detail=''):
    results.append({'id':name,'status':'PASS' if ok else 'FAIL','detail':detail})

def main():
    # Exact generated launcher contract: import-log must acquire operation lock before ingress/exec.
    with tempfile.TemporaryDirectory() as td:
        b=Path(td)/'bundle';b.mkdir()
        p=subprocess.run(['bash','-c','source "$1"; emit_bundle "$2"','t',str(ROOT/'install-cybertiel.sh'),str(b)],capture_output=True,text=True)
        check('emit_bundle',p.returncode==0,p.stderr[-300:])
        launcher=(b/'cybertiel-launcher').read_text() if p.returncode==0 else ''
        m=re.search(r'if \[\[ "\$\{1:-\}" == import-log \]\]; then(?P<body>.*?)\nfi',launcher,re.S)
        body=m.group('body') if m else ''
        seq=['/run/cybertiel/operation.lock','flock -n 9','/run/cybertiel/log-ingress.lock','flock -n 8','import-debug-log.py']
        pos=[body.find(x) for x in seq]
        check('import_log_exact_lock_order',bool(m) and all(x>=0 for x in pos) and pos==sorted(pos),{'positions':pos})
        check('import_log_operation_lock_is_nonblocking','flock -n 9' in body)
        check('import_log_does_not_bypass_operation_lock','exec python3' in body and body.find('flock -n 9')<body.find('exec python3'))
        check('import_log_rejects_orphan_running_agent','refuse_running_agent' in body and body.find('refuse_running_agent')<body.find('exec python3'))
        main_after=re.search(r'flock -n 9 \|\|.*?\n(?P<body>.*?)if \[\[ "\$\{1:-\}" == import \]\]; then(?P<import>.*?)\nfi',launcher,re.S)
        full=launcher
        imp_start=full.find('if [[ "${1:-}" == import ]]; then')
        guard_pos=full.rfind('refuse_running_agent',0,imp_start)
        func_start=full.find('# CT_PROJECT_IMPORT_FUNCTION_BEGIN')
        func_end=full.find('# CT_PROJECT_IMPORT_FUNCTION_END')
        call_pos=full.find('project_import "$2"',imp_start)
        rsync_pos=full.find('rsync -rltog',func_start,func_end if func_end>=0 else len(full))
        okay_import=(imp_start>=0 and guard_pos>=0 and guard_pos<func_start<func_end<imp_start and call_pos>imp_start and rsync_pos>func_start)
        check('project_import_rejects_orphan_running_agent',okay_import,{'guard':guard_pos,'function':func_start,'rsync':rsync_pos,'import':imp_start,'call':call_pos})

    # Behavioral falsification: old ingress-only contract can enter while an agent holds operation.lock;
    # corrected contract cannot. No project files or privileged runtime paths are touched.
    with tempfile.TemporaryDirectory() as td:
        td=Path(td);op=td/'operation.lock';ing=td/'log-ingress.lock';ready=td/'ready'
        holder=subprocess.Popen(['bash','-c',f'exec 9>"{op}"; flock 9; : >"{ready}"; sleep 10'])
        try:
            for _ in range(100):
                if ready.exists():break
                time.sleep(.02)
            old=subprocess.run(['bash','-c',f'exec 8>"{ing}"; flock -n 8'])
            new=subprocess.run(['bash','-c',f'exec 9>"{op}"; flock -n 9'])
            check('old_contract_reproduction',old.returncode==0,{'rc':old.returncode,'meaning':'ingress-only importer enters while operation lock is held'})
            check('fixed_contract_exclusion',new.returncode!=0,{'rc':new.returncode,'meaning':'importer is excluded while operation lock is held'})
        finally:
            holder.terminate()
            try:holder.wait(timeout=2)
            except subprocess.TimeoutExpired:holder.kill();holder.wait()
    failed=sum(x['status']=='FAIL' for x in results)
    out={'passed':len(results)-failed,'failed':failed,'tests':results,'scope':'exact generated launcher + local flock concurrency; not target-server runtime'}
    (ROOT/'OPERATION_LOCK_TEST_REPORT.json').write_text(json.dumps(out,indent=2)+"\n")
    print(json.dumps(out,indent=2))
    raise SystemExit(1 if failed else 0)
if __name__=='__main__':main()
