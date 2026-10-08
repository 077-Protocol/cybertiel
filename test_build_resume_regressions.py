#!/usr/bin/env python3
"""Linux root fixtures for the observed pkg-config and modprobe-alias failures."""
import hashlib,importlib.util,json,os,stat,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sp=importlib.util.spec_from_file_location('checker',ROOT/'checker/check_cybertiel.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
rows=[]
def check(n,f):
 try:f();s='PASS';d=''
 except Exception as e:s='FAIL';d=repr(e)
 rows.append(dict(id=n,status=s,detail=d))
def need(x):assert x
s=(ROOT/'install-cybertiel.sh').read_text();df=(ROOT/'generated-config/Dockerfile.llama').read_text()
check('builder_installs_pkg_config_explicitly',lambda:need('ninja-build pkg-config libopenblas-dev' in df))
check('builder_retains_OpenBLAS_and_disabled_features',lambda:need(all(x in df for x in ['-DGGML_BLAS=ON','-DGGML_BLAS_VENDOR=OpenBLAS','-DLLAMA_SUBPROCESS=OFF','-DLLAMA_OPENSSL=OFF'])))
check('resume_keeps_v25_r3_managed_identity',lambda:need('readonly INSTALL_ID=2026-10-06.v25-r3\n' in s))
check('setup_and_source_report_r3_1',lambda:need(json.loads((ROOT/'SOURCE_LOCK.json').read_text())['package_revision']=='2026-10-06.v25-r3.1' and "'package_revision':'2026-10-06.v25-r3.1'" in (ROOT/'setup_helper.py').read_text()))
check('builder_checksum_rebound',lambda:need(m.BASELINES['2026-10-06.v25-r3']['managed_files']['/opt/cybertiel/bundle/Dockerfile.llama']==hashlib.sha256(df.encode()).hexdigest()))
if os.geteuid()!=0:raise SystemExit('Run in disposable Linux VM as root; only /root temporary fixtures are used.')
with tempfile.TemporaryDirectory(dir='/root',prefix='ct-command-alias-') as td:
 root=Path(td);real=root/'kmod';alias=root/'modprobe'
 real.write_text('#!/bin/sh\ncase "${0##*/}" in modprobe) printf "install /bin/false\\n";; *) printf "wrong applet\\n" >&2; exit 2;; esac\n');real.chmod(0o755);alias.symlink_to(real)
 orig=m.Path;m.Path=lambda _:root
 try:
  cmd=m.find_command('modprobe')
  check('validated_symlink_retains_applet_name',lambda:need(cmd==str(alias)))
  result=m.bounded_run([cmd,'-n','-v','algif_aead'])
  check('modprobe_alias_real_subprocess_dispatch',lambda:need(result['rc']==0 and result['stdout']==b'install /bin/false\n'))
  result=m.bounded_run([str(real),'-n','-v','algif_aead'])
  check('old_resolved_path_failure_reproduced',lambda:need(result['rc']==2))
  check('unsafe_command_name_rejected',lambda:need(m.find_command('../modprobe') is None))
  real.chmod(0o777);check('world_writable_target_rejected',lambda:need(m.find_command('modprobe') is None));real.chmod(0o755)
  root.chmod(0o777);check('world_writable_alias_parent_rejected',lambda:need(m.find_command('modprobe') is None));root.chmod(0o700)
  os.lchown(alias,65534,65534);check('nonroot_alias_owner_rejected',lambda:need(m.find_command('modprobe') is None));os.lchown(alias,0,0)
  real.chmod(0o644);check('nonexecutable_target_rejected',lambda:need(m.find_command('modprobe') is None));real.chmod(0o755)
 finally:m.Path=orig
report={'passed':sum(x['status']=='PASS' for x in rows),'failed':sum(x['status']=='FAIL' for x in rows),'results':rows,'scope':'actual argv0-dispatch subprocess plus trusted-root negative fixtures; installer dependency/pin checks; no real server mutation'}
(ROOT/'BUILD_RESUME_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(bool(report['failed']))
