#!/usr/bin/env python3
"""Partial-install archive intake safety; temporary fixture only, never server paths."""
import importlib.util,json,os,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sp=importlib.util.spec_from_file_location('archive',ROOT/'tools/archive_partial_v25_r2.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
rows=[]
def check(n,f):
 try:f();s='PASS';d=''
 except Exception as e:s='FAIL';d=repr(e)
 rows.append(dict(id=n,status=s,detail=d))
def reject(f):
 try:f()
 except (OSError,ValueError):return
 raise AssertionError('unsafe partial accepted')
with tempfile.TemporaryDirectory() as td:
 b=Path(td)/'base';d=Path(td)/'data'
 for p in [b,d]:p.mkdir(mode=0o700);(p/'.cybertiel-install-id').write_text(m.OLD+'\n')
 (b/'locks').mkdir();l=b/'locks/pi-official-install-package-lock.json';l.write_bytes((ROOT/'upstream/pi-official-install-package-lock.json').read_bytes())
 valid=lambda:m.partial(b,d,os.geteuid())
 check('genuine_partial_intake',valid)
 (b/'READY.json').write_text('{}');check('reject_qualified_install',lambda:reject(valid));(b/'READY.json').unlink()
 (d/'.cybertiel-install-id').write_text('2026-10-06.v25-r3');check('reject_other_release',lambda:reject(valid));(d/'.cybertiel-install-id').write_text(m.OLD)
 (d/'project').mkdir();(d/'project/user.txt').write_text('preserve');check('reject_existing_project',lambda:reject(valid));(d/'project/user.txt').unlink();(d/'project').rmdir()
 original=l.read_bytes();l.write_bytes(original+b' ');check('reject_modified_official_lock',lambda:reject(valid));l.write_bytes(original)
 l.rename(l.with_suffix('.saved'));l.symlink_to(l.with_suffix('.saved'));check('reject_symlink_lock',lambda:reject(valid));l.unlink();l.with_suffix('.saved').rename(l)
 d.chmod(0o777);check('reject_writable_managed_directory',lambda:reject(valid));d.chmod(0o700)
report={'passed':sum(x['status']=='PASS' for x in rows),'failed':sum(x['status']=='FAIL' for x in rows),'results':rows,'scope':'temporary intake fixtures; no archive performed on server'}
(ROOT/'PARTIAL_ARCHIVE_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(bool(report['failed']))
