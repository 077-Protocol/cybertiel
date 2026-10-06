#!/usr/bin/env python3
"""Regression corpus for the new Pi lock contract; explicit SYNTHETIC fixtures."""
import base64,copy,hashlib,importlib.util,json,os,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def fixtures():
    name='@earendil-works/pi-coding-agent';version='1.0.3'
    pkg={'name':name+'-install','version':version,'dependencies':{name:version},'overrides':{'protobufjs':'7.6.6'}}
    def ent(n,v):
        return {'version':v,'resolved':'https://registry.npmjs.org/'+n+'/-/'+n.split('/')[-1]+'-'+v+'.tgz',
                'integrity':'sha512-'+base64.b64encode(hashlib.sha512((n+v).encode()).digest()).decode()}
    lock={'name':pkg['name'],'version':version,'lockfileVersion':3,
          'packages':{'':{'name':pkg['name'],'version':version,'dependencies':pkg['dependencies']},
             'node_modules/'+name:ent(name,version),'node_modules/brace-expansion':ent('brace-expansion','5.0.12')}}
    tree={'name':pkg['name'],'version':version,'dependencies':{name:{'version':version,'dependencies':{'brace-expansion':{'version':'5.0.12'}}}}}
    return pkg,lock,tree

def main():
    sp=importlib.util.spec_from_file_location('lockcheck',ROOT/'generated-config/verify-pi-lock.py')
    m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
    results=[]
    def check(name,fn):
        t=time.monotonic()
        try:fn();s='PASS';detail=''
        except Exception as e:s='FAIL';detail=repr(e)
        results.append(dict(id=name,status=s,detail=detail,seconds=round(time.monotonic()-t,4)))
    def require(x):
        if not x:raise AssertionError('predicate false')
    def reject(fn):
        try:fn()
        except (ValueError,OSError,TypeError,KeyError):return
        raise AssertionError('unexpected acceptance')
    pkg,lock,tree=fixtures();_,allowed,_=m.check_pair(pkg,lock)
    check('official_lock_contract_positive_synthetic',lambda:m.check_pair(pkg,lock))
    for v in ['5.0.9','5.0.11','5.0.12-rc.1','UNKNOWN','1.1.20','3.0.8']:
        def bad(v=v):
            d=copy.deepcopy(lock);d['packages']['node_modules/brace-expansion']['version']=v
            reject(lambda:m.check_pair(pkg,d))
        check('reject_dependency_'+v,bad)
    for label,fn in [
      ('missing_brace',lambda d:d['packages'].pop('node_modules/brace-expansion')),
      ('missing_pi',lambda d:d['packages'].pop('node_modules/@earendil-works/pi-coding-agent')),
      ('old_pi',lambda d:d['packages']['node_modules/@earendil-works/pi-coding-agent'].update(version='1.0.0')),
      ('http_url',lambda d:d['packages']['node_modules/brace-expansion'].update(resolved='http://registry.npmjs.org/x.tgz')),
      ('foreign_registry',lambda d:d['packages']['node_modules/brace-expansion'].update(resolved='https://example.invalid/x.tgz')),
      ('registry_credentials',lambda d:d['packages']['node_modules/brace-expansion'].update(resolved='https://user@registry.npmjs.org/x.tgz')),
      ('bad_sri',lambda d:d['packages']['node_modules/brace-expansion'].update(integrity='sha512-test')),
      ('missing_sri',lambda d:d['packages']['node_modules/brace-expansion'].pop('integrity')),
      ('link_entry',lambda d:d['packages']['node_modules/brace-expansion'].update(link=True)),
      ('lock_version_bool',lambda d:d.update(lockfileVersion=True)),
      ('lock_root_mismatch',lambda d:d['packages'][''].update(dependencies={})),
      ('path_traversal',lambda d:d['packages'].update({'../node_modules/x':d['packages']['node_modules/brace-expansion']})),
      ('nested_vulnerable',lambda d:d['packages'].update({'node_modules/x/node_modules/brace-expansion':dict(d['packages']['node_modules/brace-expansion'],version='5.0.9')})),
    ]:
        def case(fn=fn):d=copy.deepcopy(lock);fn(d);reject(lambda:m.check_pair(pkg,d))
        check('lock_reject_'+label,case)
    check('installed_tree_positive_synthetic',lambda:m.check_tree(tree,allowed))
    for label,fn in [('unknown_dependency',lambda d:d['dependencies'].update(evil={'version':'1.0.0'})),
                      ('vulnerable',lambda d:d['dependencies']['@earendil-works/pi-coding-agent']['dependencies']['brace-expansion'].update(version='5.0.9')),
                      ('extraneous',lambda d:d.update(extraneous=True)),
                      ('missing',lambda d:d.update(missing=True)),
                      ('reported_problem',lambda d:d.update(problems=['invalid dependency'])),
                      ('wrong_root',lambda d:d.update(version='1.0.0')),
                      ('missing_brace',lambda d:d['dependencies']['@earendil-works/pi-coding-agent'].update(dependencies={}))]:
        def case(fn=fn):d=copy.deepcopy(tree);fn(d);reject(lambda:m.check_tree(d,allowed))
        check('tree_reject_'+label,case)
    with tempfile.TemporaryDirectory(prefix='ct-pi-contract-') as td:
        root=Path(td)
        for key,e in lock['packages'].items():
            if not key:continue
            p=root/key/'package.json';p.parent.mkdir(parents=True);p.write_text(json.dumps({'name':m.package_name(key),'version':e['version']}))
        check('real_files_installed_metadata_positive',lambda:m.check_installed(root,lock['packages']))
        f=root/'node_modules/brace-expansion/package.json';original=f.read_bytes()
        f.write_text(json.dumps({'name':'brace-expansion','version':'5.0.9'}))
        check('real_files_installed_vulnerable_reject',lambda:reject(lambda:m.check_installed(root,lock['packages'])))
        f.write_bytes(original);f.rename(f.with_suffix('.saved'));f.symlink_to(f.with_suffix('.saved'))
        check('real_files_installed_symlink_reject',lambda:reject(lambda:m.check_installed(root,lock['packages'])))
        f.unlink();f.with_suffix('.saved').rename(f)
        p=root/'package.json';p.write_text(json.dumps(pkg));l=root/'package-lock.json';l.write_text(json.dumps(lock))
        r=subprocess.run(['python3',str(ROOT/'generated-config/verify-pi-lock.py'),str(p),str(l),'--installed-root',str(root)],capture_output=True,text=True,timeout=5)
        check('CLI_synthetic_positive',lambda:require(r.returncode==0 and json.loads(r.stdout)['installed_metadata_checked']))
        r=subprocess.run(['python3',str(ROOT/'generated-config/verify-pi-lock.py'),str(p),str(l),'--require-release-hashes'],capture_output=True,text=True,timeout=5)
        check('CLI_synthetic_not_official_hash_reject',lambda:require(r.returncode!=0))
        for label,b in [('duplicate',b'{"x":1,"x":2}'),('nan',b'{"x":NaN}'),('broken',b'{'),('deep',b'['*2000+b']'*2000)]:
            p.write_bytes(b)
            def fbad():
                try:m.load(p)
                except (ValueError,OSError,RecursionError):return
                raise AssertionError('malformed accepted')
            check('JSON_reject_'+label,fbad)
        p.unlink();p.symlink_to(l)
        check('JSON_symlink_reject',lambda:reject(lambda:m.load(p)))
    # npm alias: directory alias is not necessarily package.json.name.
    with tempfile.TemporaryDirectory(prefix='ct-pi-alias-') as td:
        rr=Path(td); ali=copy.deepcopy(lock)
        source=copy.deepcopy(ali['packages']['node_modules/brace-expansion'])
        source.update(name='brace-expansion')
        ali['packages']['node_modules/patched-brace-alias']=source
        check('npm_alias_lock_supported',lambda:m.check_pair(pkg,ali))
        for key,e in ali['packages'].items():
            if not key:continue
            f=rr/key/'package.json';f.parent.mkdir(parents=True,exist_ok=True)
            f.write_text(json.dumps({'name':e.get('name',m.package_name(key)),'version':e['version']}))
        check('npm_alias_installed_metadata_supported',lambda:m.check_installed(rr,ali['packages']))
        ali['packages']['node_modules/patched-brace-alias']['version']='5.0.9'
        check('npm_alias_vulnerable_rejected',lambda:reject(lambda:m.check_pair(pkg,ali)))
    check('lock_key_repeated_separator_rejected',lambda:reject(lambda:m.package_name('node_modules//pkg')))
    check('lock_key_dot_component_rejected',lambda:reject(lambda:m.package_name('node_modules/./pkg')))
    # Test the actual timeout extension as JavaScript; no Pi runtime is claimed.
    code=(ROOT/'generated-config/bash-timeout.ts').read_text().replace('export default function','function register')
    js=code+'''\nlet handler; register({on:(n,f)=>{if(n!=="tool_call")throw Error(n);handler=f;}});
for(const raw of [undefined,null,-1,0,NaN,Infinity,9000,1,90,0.5,"10"]){
let event={toolName:"bash",input:{timeout:raw}};handler(event);
const expected=typeof raw==="number"&&Number.isFinite(raw)&&raw>0?Math.min(Math.max(Math.trunc(raw),1),7200):7200;
if(event.input.timeout!==expected)throw Error("bad clamp");}
let e={toolName:"read",input:{timeout:99999}};handler(e);if(e.input.timeout!==99999)throw Error("foreign tool mutation");
console.log("TIMEOUT_CONTRACT_PASS");'''
    r=subprocess.run(['node','-e',js],capture_output=True,text=True,timeout=5)
    check('real_node_extension_logic_not_Pi_integration',lambda:require(r.returncode==0 and 'TIMEOUT_CONTRACT_PASS' in r.stdout))
    s=(ROOT/'install-cybertiel.sh').read_text()
    check('model_download_after_toolchain',lambda:require(s.index('Deterministische agent-toolchaincontrole') < s.index('# Download the exact published model;')))
    check('no_shrinkwrap_runtime_requirement',lambda:require('/opt/pi/package/npm-shrinkwrap.json' not in s))
    check('Pi_version_consistent',lambda:require('readonly PI_VERSION=1.0.3' in s and '= "1.0.3"' in s))
    check('dependency_proof_before_Pi_exec',lambda:require(s.index('--require-release-hashes --installed-root /opt/pi/install') < s.index('&& pi --version')))
    report={'results':results,'passed':sum(x['status']=='PASS' for x in results),'failed':sum(x['status']=='FAIL' for x in results),
        'evidence':'synthetic lock/tree plus real local filesystem/CLI/Node execution; no Docker/model/npm dependency download',
        'installer_sha256':hashlib.sha256((ROOT/'install-cybertiel.sh').read_bytes()).hexdigest()}
    (ROOT/'PI_LOCK_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return 1 if report['failed'] else 0

if __name__=='__main__':raise SystemExit(main())
