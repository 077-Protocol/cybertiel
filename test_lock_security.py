#!/usr/bin/env python3
"""Regression tests for CT-BUG-020. Synthetic filesystem only; no CyberTiel install."""
import json, os, pathlib, shutil, stat, subprocess, tempfile
R=pathlib.Path(__file__).resolve().parent
rows=[]
def check(name, fn):
    try: detail=fn(); status='PASS'
    except Exception as exc: detail=f'{type(exc).__name__}: {exc}'; status='FAIL'
    rows.append({'id':name,'status':status,'detail':detail if isinstance(detail,(str,int,float,bool,list,dict,type(None))) else str(detail)})
    print(json.dumps(rows[-1]),flush=True)
def need(x,msg='predicate false'):
    if not x: raise AssertionError(msg)
installer=(R/'install-cybertiel.sh').read_text()
launcher=(R/'generated-config/cybertiel-launcher').read_text()
checker=(R/'checker/check_cybertiel.py').read_text()
check('installer_no_world_writable_lock_path',lambda:need('/run/lock/cybertiel-' not in installer))
check('launcher_no_world_writable_lock_path',lambda:need('/run/lock/cybertiel-' not in launcher))
check('installer_private_runtime_dir_contract',lambda:need('install -d -o root -g root -m 0700 -- "$dir"' in installer and '/run/cybertiel/operation.lock' in installer))
check('launcher_private_runtime_dir_contract',lambda:need('install -d -o root -g root -m 0700 -- "$dir"' in launcher and '/run/cybertiel/operation.lock' in launcher and '/run/cybertiel/log-ingress.lock' in launcher))
check('checker_current_lock_path',lambda:need("Path('/run/cybertiel/operation.lock')" in checker))
check('checker_v17_compat_lock_path',lambda:need("Path('/run/lock/cybertiel-operation.lock')" in checker))

def old_symlink_clobber_is_real():
    with tempfile.TemporaryDirectory(prefix='ct-lock-old-') as td:
        root=pathlib.Path(td); world=root/'lock'; world.mkdir(); world.chmod(0o1777)
        victim=root/'victim'; victim.write_text('DO NOT TRUNCATE\n'); victim.chmod(0o644)
        link=world/'cybertiel-operation.lock'
        # root creates the symlink here purely as a deterministic synthetic stand-in
        # for what an unprivileged account can pre-create in a 1777 lock directory.
        link.symlink_to(victim)
        q=subprocess.run(['bash','-c','exec 9>"$1"; flock -n 9; printf ok','x',str(link)],capture_output=True,text=True)
        need(q.returncode==0 and victim.read_bytes()==b'',f'rc={q.returncode} size={victim.stat().st_size}')
        return {'victim_truncated':True,'simulated_parent_mode':'1777'}
check('old_redirection_follows_symlink_and_truncates',old_symlink_clobber_is_real)

def private_parent_blocks_unprivileged_precreate():
    if os.geteuid()!=0 or shutil.which('runuser') is None:return {'skipped_reason':'requires root + runuser'}
    with tempfile.TemporaryDirectory(prefix='ct-lock-new-') as td:
        root=pathlib.Path(td); private=root/'cybertiel'; private.mkdir(); private.chmod(0o700)
        victim=root/'victim'; victim.write_text('SAFE\n'); victim.chmod(0o644)
        link=private/'operation.lock'
        q=subprocess.run(['runuser','-u','nobody','--','ln','-s',str(victim),str(link)],capture_output=True,text=True)
        need(q.returncode!=0 and not os.path.lexists(link) and victim.read_text()=='SAFE\n',f'rc={q.returncode}')
        return {'unprivileged_symlink_creation_rejected':True,'victim_unchanged':True}
check('private_0700_parent_blocks_precreation',private_parent_blocks_unprivileged_precreate)
report={'results':rows,'passed':sum(x['status']=='PASS' for x in rows),'failed':sum(x['status']=='FAIL' for x in rows),'scope':'synthetic local lock-path regression only; not a target-server installation test'}
(R/'LOCK_SECURITY_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2));raise SystemExit(bool(report['failed']))
