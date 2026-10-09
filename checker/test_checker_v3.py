#!/usr/bin/env python3
"""Current current checker contracts; synthetic receipts, no Docker/model claimed."""
import copy,hashlib,importlib.util,json,stat,types
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sp=importlib.util.spec_from_file_location('checker',ROOT/'check_cybertiel.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
R=[]
def check(n,f):
 try:f();s='PASS';detail=''
 except Exception as e:s='FAIL';detail=repr(e)
 R.append({'id':n,'status':s,'detail':detail})
def need(x):
 if not x:raise AssertionError('predicate false')
b=m.BASELINES['2026-10-06.v25-r3'];parent=ROOT.parent
check('v18_installer_hash_exact',lambda:need(b['installer_sha256']==hashlib.sha256((parent/'install-cybertiel.sh').read_bytes()).hexdigest()))
check('v16_history_preserved',lambda:need('2026-10-05.v16' in m.BASELINES))
check('current_no_shrinkwrap_receipt',lambda:need('pi_published_shrinkwrap_sha256' not in m.ready_bindings('2026-10-06.v25-r3')))
check('v16_keeps_historical_binding',lambda:need('pi_published_shrinkwrap_sha256' in m.ready_bindings('2026-10-05.v16')))
for path,h in b['managed_files'].items():
 name=Path(path).name
 if name=='cybertiel':name='cybertiel-launcher'
 check('bundle_binding_'+name,lambda name=name,h=h:need(hashlib.sha256((parent/'generated-config'/name).read_bytes()).hexdigest()==h))
proof={'status':'PASS','pi_version':'1.0.3','brace_expansion':'5.0.12','lock_sha256':b['pi_derived_lock_sha256'],'official_lock_sha256':b['pi_lock_sha256'],'derived_lock_sha256':b['pi_derived_lock_sha256'],'sri_manifest_sha256':b['pi_sri_manifest_sha256'],
 'package_sha256':b['pi_package_sha256'],'release_hashes_checked':True,'installed_metadata_checked':True,
 'installed_packages':{'a':{'name':'@earendil-works/pi-coding-agent','version':'1.0.3'},'b':{'name':'brace-expansion','version':'5.0.12'}}}
check('live_proof_positive',lambda:need(not m.live_lock_problems(proof,b)))
for k,v in [('status','FAIL'),('pi_version','1.0.0'),('brace_expansion','5.0.9'),('lock_sha256','0'*64),('package_sha256','0'*64),('release_hashes_checked',False),('installed_metadata_checked',1),('installed_packages',{}),('installed_packages',[]),('installed_packages',{'a':{'name':'@earendil-works/pi-coding-agent','version':'1.0.3'},'b':{'name':'brace-expansion','version':'5.0.9'}})]:
 def f(k=k,v=v):x=copy.deepcopy(proof);x[k]=v;need(m.live_lock_problems(x,b))
 check('live_proof_reject_'+k+'_'+str(len(R)),f)
check('live_proof_missing_rejected',lambda:need(m.live_lock_problems(None,b)))
check('runtime_version_injected_not_hardcoded',lambda:need("@PI_VERSION_EXPECTED@" in m.TOOLCHAIN_PROBE and "'1.0.3'" in m.TOOLCHAIN_PROBE))
# Only emulate installed managed data for selection logic; NOT a live install.
real=m.read_managed;wanted='2026-10-06.v25-r3';data={str(m.BASE/'.cybertiel-install-id'):wanted.encode()}
def rd(p,*args,**kwargs):
 if str(p) not in data:raise FileNotFoundError(str(p))
 return data[str(p)],types.SimpleNamespace(st_uid=0,st_gid=0,st_mode=stat.S_IFREG|0o600)
m.read_managed=rd
try:
 a=m.Auditor(types.SimpleNamespace(installer=str(parent/'install-cybertiel.sh'),runtime=False,deep_model_hash=False,hash_timeout=3600))
 a.installed();rows={x['id']:x for x in a.rows}
 check('current_upload_recognized_not_v16_advisory',lambda:need(rows['upload.installer']['status']=='PASS' and 'audit.upload_security' not in rows))
 check('current_missing_install_data_not_green',lambda:need(any(x['status']=='FAIL' for x in a.rows)))
 check('current_runtime_state_selected',lambda:need(a.baseline['pi_version']=='1.0.3'))
finally:m.read_managed=real
report={'results':R,'passed':sum(x['status']=='PASS' for x in R),'failed':sum(x['status']=='FAIL' for x in R),'scope':'synthetic receipts/managed data; exact local file hashes; not a Docker/server test'}
(ROOT/'V3_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(bool(report['failed']))
