#!/usr/bin/env python3
"""Real pinned assets, negative tests and independent derivation; no Pi execution."""
import copy,hashlib,importlib.util,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('validator',ROOT/'generated-config/verify-pi-lock.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
pkg,ph=v.load(ROOT/'upstream/pi-official-install-package.json');lock,lh=v.load(ROOT/'upstream/pi-official-install-package-lock.json')
R=[]
def check(n,f):
 try:f();status='PASS';detail=''
 except Exception as e:status='FAIL';detail=repr(e)
 R.append(dict(id=n,status=status,detail=detail))
def need(x):assert x

def reject(f):
 try:f()
 except (ValueError,OSError,TypeError,KeyError):return
 raise AssertionError('unexpected acceptance')
check('original_release_hashes',lambda:need(ph==v.PACKAGE_SHA and lh==v.LOCK_SHA))
manifest,mh=v.load(ROOT/'generated-config/pi-sri-manifest.json')
check('manifest_exact_hash_and_embedded_match',lambda:need(mh==v.SRI_MANIFEST_SHA and manifest==v.SRI_MANIFEST))
derived,raw=v.derive_lock(lock)
check('derived_exact_sha256',lambda:need(hashlib.sha256(raw).hexdigest()==v.DERIVED_LOCK_SHA))
check('exactly_eight_missing_SRI',lambda:need(len(manifest['packages'])==8 and all(k.startswith('node_modules/@earendil-works/') for k in manifest['packages'])))
check('original_validator_failure_reproduced',lambda:reject(lambda:v.check_pair(pkg,lock)))
check('derived_graph_accepted',lambda:v.check_pair(pkg,derived))
restored=copy.deepcopy(derived)
for k in manifest['packages']:restored['packages'][k].pop('integrity')
check('only_eight_SRI_fields_changed',lambda:need(restored==lock))
for k,pin in manifest['packages'].items():
 meta,mh=v.load(ROOT/'upstream/registry-evidence'/(pin['name'].split('/')[-1]+'.json'))
 check('metadata_'+pin['name'],lambda meta=meta,mh=mh,pin=pin:need(mh==pin['metadata_sha256'] and meta['name']==pin['name'] and meta['version']==pin['version'] and meta['dist']['tarball']==pin['resolved'] and meta['dist']['integrity']==pin['integrity']))
for label,mut in [('version',lambda d:d['packages'][next(iter(manifest['packages']))].update(version='1.0.4')),('url',lambda d:d['packages'][next(iter(manifest['packages']))].update(resolved='https://evil.invalid/x.tgz')),('extra_missing_sri',lambda d:d['packages']['node_modules/brace-expansion'].pop('integrity')),('extra_dependency',lambda d:d['packages'].update({'node_modules/evil':dict(d['packages']['node_modules/brace-expansion'])})),('root_override',lambda d:d['packages'][''].update(overrides={'evil':'1.0.0'}))]:
 def f(mut=mut):
  x=copy.deepcopy(lock);mut(x);reject(lambda:v.derive_lock(x))
 check('reject_derivation_'+label,f)
with tempfile.TemporaryDirectory() as td:
 t=Path(td);p=t/'package.json';p.write_bytes((ROOT/'upstream/pi-official-install-package.json').read_bytes());l=t/'lock.json';l.write_bytes(raw)
 def cli(*args):return subprocess.run(['python3',str(ROOT/'generated-config/verify-pi-lock.py'),str(p),str(l),'--require-release-hashes',*map(str,args)],capture_output=True,text=True)
 check('CLI_real_derived_positive',lambda:need(cli().returncode==0))
 for label,mut in [('SRI',lambda x:x['packages'][next(iter(manifest['packages']))].update(integrity='sha512-'+'A'*86+'==')),('registry',lambda x:x['packages'][next(iter(manifest['packages']))].update(resolved='https://example.invalid/x.tgz')),('version',lambda x:x['packages'][next(iter(manifest['packages']))].update(version='1.0.4'))]:
  x=copy.deepcopy(derived);mut(x);l.write_text(json.dumps(x));check('CLI_reject_changed_'+label,lambda:need(cli().returncode!=0))
 l.write_bytes((ROOT/'upstream/pi-official-install-package-lock.json').read_bytes());out=t/'derived.json'
 check('CLI_derive_real_official',lambda:need(cli('--write-install-lock',out).returncode==0 and out.read_bytes()==raw))
 check('CLI_reject_overwrite_output',lambda:need(cli('--write-install-lock',out).returncode!=0))
 out.unlink();out.symlink_to(p);before=p.read_bytes()
 check('CLI_reject_symlink_output',lambda:need(cli('--write-install-lock',out).returncode!=0 and p.read_bytes()==before))
# Independent checker pins and negative proof bindings.
spec=importlib.util.spec_from_file_location('checker',ROOT/'checker/check_cybertiel.py');c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
b=c.BASELINES['2026-10-06.v25-r3']
check('checker_derived_and_manifest_independent_pins',lambda:need(b['pi_derived_lock_sha256']==v.DERIVED_LOCK_SHA and b['pi_sri_manifest_sha256']==v.SRI_MANIFEST_SHA))
proof={'status':'PASS','pi_version':'1.0.3','brace_expansion':'5.0.12','lock_sha256':v.DERIVED_LOCK_SHA,'package_sha256':v.PACKAGE_SHA,'official_lock_sha256':v.LOCK_SHA,'derived_lock_sha256':v.DERIVED_LOCK_SHA,'sri_manifest_sha256':v.SRI_MANIFEST_SHA,'release_hashes_checked':True,'installed_metadata_checked':True,'installed_packages':{'a':{'name':v.NAME,'version':v.VERSION},'b':{'name':'brace-expansion','version':'5.0.12'}}}
check('checker_real_contract_positive',lambda:need(not c.live_lock_problems(proof,b)))
for field in ['official_lock_sha256','derived_lock_sha256','sri_manifest_sha256','lock_sha256']:
 x=dict(proof);x[field]='0'*64;check('checker_reject_'+field,lambda x=x:need(bool(c.live_lock_problems(x,b))))
s=(ROOT/'install-cybertiel.sh').read_text();df=(ROOT/'generated-config/Dockerfile.agent').read_text()
check('Docker_npm_uses_derived_lock',lambda:need('COPY pi-derived-install-package-lock.json /opt/pi/install/package-lock.json' in df and 'official-package-lock.json --require-release-hashes' in df))
check('installed_lock_uses_derived_pin',lambda:need('verify_hash "$BASE/locks/pi-installed-lock.json" sha256 "$PI_DERIVED_LOCK_SHA256"' in s))
check('READY_binds_manifest_and_derived',lambda:need(all(k in c.ready_bindings('2026-10-06.v25-r3') and '"'+k+'"' in s for k in ['pi_sri_manifest_sha256','pi_derived_install_lock_sha256'])))
report={'passed':sum(r['status']=='PASS' for r in R),'failed':sum(r['status']=='FAIL' for r in R),'results':R,'scope':'Actual upstream release bytes and registry metadata; deterministic derivation and negative tests; no server or Pi runtime'}
(ROOT/'PI_SRI_REPAIR_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(bool(report['failed']))
