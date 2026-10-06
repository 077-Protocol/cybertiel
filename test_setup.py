#!/usr/bin/env python3
"""Tests use harmless local fake scripts. No real installer is invoked.
The coordinator itself is root-only; run this suite as root for ownership semantics.
"""
import hashlib,importlib.util,json,os,signal,subprocess,tempfile,time,shlex
from pathlib import Path
R=Path(__file__).resolve().parent
sp=importlib.util.spec_from_file_location('setup',R/'setup_helper.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
rows=[]
def check(n,f):
 try:f();s='PASS';d=''
 except Exception as e:s='FAIL';d=repr(e)
 rows.append({'id':n,'status':s,'detail':d})
def need(x):
 if not x:raise AssertionError('predicate false')
def reject(f):
 try:f()
 except (ValueError,OSError):return
 raise AssertionError('unexpected acceptance')
def diagnostic_obj(crc,runtime):
 status='ISSUES_FOUND' if crc==1 else 'INCOMPLETE' if crc==2 else 'CHECKED_NOT_PROJECT_QUALIFIED'
 row_status='FAIL' if crc==1 else 'UNTESTED' if crc==2 else 'PASS'
 return {'schema':'cybertiel-diagnostic/v1','checker':m.EXPECTED_CHECKER,'status':status,
  'runtime_opt_in':bool(runtime),'full_model_hash_opt_in':bool(runtime),
  'checks':[{'id':'synthetic','status':row_status,'message':'test'}],
  'counts':{row_status:1},'downloads_or_package_changes':False,'user_project_executed':False,
  'secrets_or_project_log_contents_included':False}
def write_report(d,obj):
 rd=d/'cybertiel-check-fake';rd.mkdir(mode=0o700)
 (rd/'report.json').write_text(json.dumps(obj,separators=(',',':'))+'\n');(rd/'report.json').chmod(0o600)

for name,sha in m.PINS.items():check('real_companion_hash_'+name,lambda name=name,sha=sha:need(hashlib.sha256((R/name).read_bytes()).hexdigest()==sha))
with tempfile.TemporaryDirectory(prefix='ct-setup-test-') as td:
 t=Path(td);src=t/'source';src.mkdir();dest=t/'dest';dest.mkdir()
 for name in m.PINS:(src/name).write_text('#!/bin/bash\nprintf harmless\\n\n')
 pins={n:hashlib.sha256((src/n).read_bytes()).hexdigest() for n in m.PINS}
 paths=m.stage(src,dest,pins)
 check('stage_verified_bytes',lambda:need(all(paths[n].read_bytes()==(src/n).read_bytes() for n in pins)))
 check('stage_private_permissions',lambda:need(all(paths[n].stat().st_mode&0o777==0o600 for n in pins)))
 f=src/'install-cybertiel.sh';f.write_text('corrupt')
 check('corrupt_upload_rejected',lambda:reject(lambda:m.checked_bytes(f,pins[f.name])))
 f.unlink();f.symlink_to(dest/f.name)
 check('symlink_upload_rejected',lambda:reject(lambda:m.checked_bytes(f,pins[f.name])))
 f.unlink();os.mkfifo(f)
 check('FIFO_rejected_without_block',lambda:reject(lambda:m.checked_bytes(f,pins[f.name])))
 f.unlink();f.write_text('x');h=src/'hard';os.link(f,h)
 check('hardlink_rejected',lambda:reject(lambda:m.checked_bytes(f,hashlib.sha256(b'x').hexdigest())))
 # Run actual harmless shell processes, not just mocked exitcodes.
 for n,irc,crc in [('install_fail',7,2),('postcheck_fail',0,1),('remaining_unknown',0,2),('all_smokes',0,0)]:
  case=t/n;case.mkdir();ins=case/'installer';chk=case/'checker'
  ins.write_text('#!/bin/bash\necho invoked > '+shlex.quote(str(case/'install-called'))+'\nexit '+str(irc)+'\n')
  payload=json.dumps(diagnostic_obj(crc,irc==0),separators=(',',':'))
  chk.write_text('#!/bin/bash\necho diagnosed > '+shlex.quote(str(case/'check-called'))+'\nout=""\nwhile [ "$#" -gt 0 ]; do if [ "$1" = --output-parent ]; then out="$2"; shift 2; else shift; fi; done\nmkdir -m 700 "$out/cybertiel-check-fake"\nprintf \'%s\\n\' '+shlex.quote(payload)+' > "$out/cybertiel-check-fake/report.json"\nchmod 600 "$out/cybertiel-check-fake/report.json"\nexit '+str(crc)+'\n')
  report,rc=m.drive('install',{'install-cybertiel.sh':ins,'check-cybertiel-server.sh':chk},case,60,60,1)
  check(n+'_both_commands_executed',lambda case=case:need((case/'install-called').is_file() and (case/'check-called').is_file()))
  expected=m.outcome('install',irc,crc,'valid')
  check(n+'_status_and_return',lambda report=report,rc=rc,expected=expected:need((report['status'],rc)==expected))
  check(n+'_no_project_success_claim',lambda report=report:need(report['project_correctness_proven'] is False))
  check(n+'_report_written',lambda case=case,report=report:need(json.loads((case/'setup-result.json').read_text())==report))
 for n,irc in [('failure_no_runtime',4),('success_runtime',0)]:
  calls=[];dest=t/n;dest.mkdir()
  def fake(argv,out):
   calls.append(argv)
   if len(calls)==1:return irc
   write_report(dest,diagnostic_obj(2,irc==0));return 2
  m.drive('install',paths,dest,7200,14400,4,runner=fake)
  check(n,lambda calls=calls,irc=irc:need(('--runtime' in calls[1])==(irc==0) and len(calls)==2))
check('setup_embedded_matches',lambda:need((R/'setup-cybertiel.sh').read_text().split("<<'CYBERTIEL_SETUP_PY'\n",1)[1].rsplit('\nCYBERTIEL_SETUP_PY',1)[0].rstrip()==(R/'setup_helper.py').read_text().rstrip()))
for flag in ['--help','--plan']:
 q=subprocess.run(['bash',str(R/'setup-cybertiel.sh'),flag],capture_output=True,text=True,timeout=5)
 check('setup_cli_'+flag,lambda q=q:need(q.returncode==0))
for args in [['--install'],['--build-jobs','0'],['--install','--check'],['--unknown']]:
 q=subprocess.run(['bash',str(R/'setup-cybertiel.sh')]+args,capture_output=True,text=True,timeout=5)
 check('setup_cli_reject_'+str(args),lambda q=q:need(q.returncode!=0))
with tempfile.TemporaryDirectory(prefix='ct-setup-missing-report-') as md:
 missing=Path(md);calls=[]
 def no_report_runner(argv,out):
  calls.append(argv);return 7 if len(calls)==1 else 2
 report,rc=m.drive('install',paths,missing,60,60,1,runner=no_report_runner)
 check('missing_checker_report_never_claimed_available',lambda report=report,rc=rc:need(report['status']=='INSTALL_FAILED_CHECKER_REPORT_MISSING' and report['checker_report_verified'] is False and rc==1))
# CT-BUG-023: exit code alone cannot overrule the diagnostic content.
with tempfile.TemporaryDirectory(prefix='ct-setup-contradiction-') as cd:
 c=Path(cd)
 def contradiction_case(name,crc,obj,installer_rc=0):
  d=c/name;d.mkdir();ins=d/'installer';chk=d/'checker';ins.write_text('x');chk.write_text('x');calls=[]
  def fake(argv,out):
   calls.append(argv)
   if len(calls)==1:return installer_rc
   write_report(d,obj);return crc
  return m.drive('install',{'install-cybertiel.sh':ins,'check-cybertiel-server.sh':chk},d,60,60,1,runner=fake)
 obj=diagnostic_obj(1,True);r,rc=contradiction_case('fail_report_exit0',0,obj)
 check('checker_fail_report_exit0_rejected',lambda r=r,rc=rc:need(r['status']=='CHECKER_REPORT_CONTRADICTION' and rc==1 and r['checker_report_verified'] is False))
 obj=diagnostic_obj(0,True);obj['counts']={'PASS':2};r,rc=contradiction_case('count_mismatch',0,obj)
 check('checker_count_mismatch_rejected',lambda r=r,rc=rc:need(r['status']=='CHECKER_REPORT_CONTRADICTION' and rc==1))
 obj=diagnostic_obj(0,False);r,rc=contradiction_case('runtime_flag_mismatch',0,obj)
 check('checker_runtime_optin_mismatch_rejected',lambda r=r,rc=rc:need(r['status']=='CHECKER_REPORT_CONTRADICTION' and rc==1))
 obj=diagnostic_obj(0,True);obj['checker']='OTHER';r,rc=contradiction_case('checker_id_mismatch',0,obj)
 check('checker_identity_mismatch_rejected',lambda r=r,rc=rc:need(r['status']=='CHECKER_REPORT_CONTRADICTION' and rc==1))
 obj=diagnostic_obj(0,True);obj['status']='ISSUES_FOUND';r,rc=contradiction_case('overall_status_mismatch',0,obj)
 check('checker_overall_status_mismatch_rejected',lambda r=r,rc=rc:need(r['status']=='CHECKER_REPORT_CONTRADICTION' and rc==1))
check('clean_command_environment',lambda:need(not any(k in m.ENV for k in ['DOCKER_HOST','BASH_ENV','LD_PRELOAD','PYTHONPATH'])))
# CT-BUG-021: SIGTERM/HUP to the coordinator must not orphan its child process group.
with tempfile.TemporaryDirectory(prefix='ct-setup-signal-') as sd:
 sigdir=Path(sd);childpid=sigdir/'child.pid';h=sigdir/'harness.py'
 h.write_text("""import importlib.util,sys
sp=importlib.util.spec_from_file_location('s',sys.argv[1]);m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
rc=m.run_command(['/bin/bash','-c',f'echo $$ > {sys.argv[2]}; sleep 30'])
raise SystemExit(rc)
""")
 proc=subprocess.Popen(['python3',str(h),str(R/'setup_helper.py'),str(childpid)])
 for _ in range(100):
  if childpid.is_file() and childpid.read_text().strip():break
  time.sleep(.02)
 need(childpid.is_file())
 cpid=int(childpid.read_text().strip());proc.send_signal(signal.SIGTERM);rc=proc.wait(timeout=5)
 alive=True
 try:os.kill(cpid,0)
 except ProcessLookupError:alive=False
 if alive:
  try:os.killpg(cpid,signal.SIGKILL)
  except ProcessLookupError:pass
 check('setup_SIGTERM_reaps_child_group',lambda rc=rc,alive=alive:need(rc==143 and not alive))
report={'results':rows,'passed':sum(x['status']=='PASS' for x in rows),'failed':sum(x['status']=='FAIL' for x in rows),'scope':'real harmless shell subprocesses and private local files; actual installer never run; ownership semantics require root as production does'}
(R/'SETUP_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(bool(report['failed']))
