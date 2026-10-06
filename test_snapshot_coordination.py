#!/usr/bin/env python3
"""v22 persistent snapshot/mutator coordination tests; no server mutation."""
import fcntl, json, os, pathlib, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
installer=(ROOT/'install-cybertiel.sh').read_text()
launcher=(ROOT/'generated-config/cybertiel-launcher').read_text()
checker=(ROOT/'checker/check_cybertiel.py').read_text()
results=[]
def check(name,cond,detail=None):
    results.append({'name':name,'status':'PASS' if cond else 'FAIL','detail':detail})
    print(json.dumps(results[-1]))

def main():
    # Contract: all ordinary mutators use persistent BASE directory flock before volatile operation.lock.
    check('installer_persistent_directory_lock_contract',
          'secure_base_coordination_lock' in installer and 'exec 7<"$BASE"' in installer and
          installer.index('secure_base_coordination_lock\n    secure_runtime_lock_dir') < installer.index('ensure_owned_tree "$BASE"'))
    check('launcher_persistent_directory_lock_contract',
          'acquire_base_coordination_lock' in launcher and 'exec 7<"$BASE"' in launcher)
    il=launcher.index('if [[ "${1:-}" == import-log ]]')
    check('import_log_directory_lock_before_volatile_lock',
          launcher.index('acquire_base_coordination_lock',il) < launcher.index('/run/cybertiel/operation.lock',il))
    normal=launcher.index('\nacquire_base_coordination_lock\nsecure_lock_dir',il)
    check('normal_mutation_directory_lock_before_volatile_lock', normal>il)
    check('checker_uses_readonly_persistent_shared_lock',
          'base_fd,_=open_managed_dir(BASE)' in checker and 'fcntl.LOCK_SH|fcntl.LOCK_NB' in checker and
          "legacy release has no persistent coordination protocol and runtime lock is absent" in checker)
    check('installer_first_install_parent_lock_contract',
          'local perms parent=/opt parent_locked=0' in installer and 'exec 6<"$parent"' in installer and
          'flock -n 6' in installer and '[[ -e "$BASE" ]] || install -d' in installer)
    check('checker_fresh_host_parent_shared_lock_contract',
          "open_managed_dir(Path('/opt'))" in checker and
          'fcntl.flock(parent_fd,fcntl.LOCK_SH|fcntl.LOCK_NB)' in checker)
    # Behavioral: shared checker lock blocks a newly starting exclusive mutator even when no operation.lock exists.
    with tempfile.TemporaryDirectory(prefix='ct-v22-coord-') as td:
        base=pathlib.Path(td)/'cybertiel';base.mkdir()
        sfd=os.open(base,os.O_RDONLY|os.O_DIRECTORY)
        fcntl.flock(sfd,fcntl.LOCK_SH|fcntl.LOCK_NB)
        q=subprocess.run(['python3','-c',f"import os,fcntl,sys; fd=os.open({str(base)!r},os.O_RDONLY|os.O_DIRECTORY);\ntry: fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB); sys.exit(0)\nexcept BlockingIOError: sys.exit(7)"])
        check('shared_checker_lock_blocks_new_mutator',q.returncode==7,{'mutator_rc':q.returncode})
        os.close(sfd)
        # Positive converse: exclusive mutator lock blocks checker shared lock.
        efd=os.open(base,os.O_RDONLY|os.O_DIRECTORY);fcntl.flock(efd,fcntl.LOCK_EX|fcntl.LOCK_NB)
        q=subprocess.run(['python3','-c',f"import os,fcntl,sys; fd=os.open({str(base)!r},os.O_RDONLY|os.O_DIRECTORY);\ntry: fcntl.flock(fd,fcntl.LOCK_SH|fcntl.LOCK_NB); sys.exit(0)\nexcept BlockingIOError: sys.exit(7)"])
        check('exclusive_mutator_lock_blocks_checker',q.returncode==7,{'checker_rc':q.returncode})
        os.close(efd)
    failed=[x for x in results if x['status']=='FAIL']
    report={'passed':len(results)-len(failed),'failed':len(failed),'failures':failed}
    (ROOT/'SNAPSHOT_COORDINATION_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return 1 if failed else 0
if __name__=='__main__':raise SystemExit(main())
