#!/usr/bin/env python3
"""Preserve a failed v25-r2 install before v25-r3. Plan by default; never delete data."""
import argparse,datetime,fcntl,hashlib,json,os,stat,subprocess
from pathlib import Path
OLD='2026-10-06.v25'
LOCK_SHA='d2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7'
def regular(p,uid=0):
 fd=os.open(p,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
 try:
  s=os.fstat(fd)
  if not stat.S_ISREG(s.st_mode) or s.st_uid!=uid or s.st_size>8*1024*1024:raise ValueError('unsafe managed file: '+str(p))
  with os.fdopen(os.dup(fd),'rb') as f:return f.read(8*1024*1024+1)
 finally:os.close(fd)
def partial(base,data,uid=0):
 paths=[]
 for p in (base,data):
  if not p.exists() and not p.is_symlink():continue
  s=p.lstat()
  if not stat.S_ISDIR(s.st_mode) or s.st_uid!=uid or stat.S_IMODE(s.st_mode)&0o022:raise ValueError('unsafe managed directory: '+str(p))
  if regular(p/'.cybertiel-install-id',uid).strip()!=OLD.encode():raise ValueError('not a managed v25 partial install')
  if (p/'READY.json').exists() or (p/'READY.json').is_symlink():raise ValueError('READY exists: this tool only archives an unqualified partial install')
  paths.append(p)
 if base not in paths:raise ValueError('partial /opt installation missing')
 if hashlib.sha256(regular(base/'locks/pi-official-install-package-lock.json',uid)).hexdigest()!=LOCK_SHA:raise ValueError('original official lock mismatch')
 for name in ('project','projects'):
  p=data/name
  if p.is_symlink() or (p.exists() and (not p.is_dir() or any(p.iterdir()))):raise ValueError('project data present: archive requires operator review')
 return paths

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--apply',action='store_true');a=ap.parse_args()
 if os.geteuid()!=0:raise ValueError('run with sudo; default is a read-only plan')
 # Match the installer's private lock contract. Fail on active agent/installer.
 run=Path('/run/cybertiel')
 if not run.exists():run.mkdir(mode=0o700)
 s=run.lstat()
 if not stat.S_ISDIR(s.st_mode) or s.st_uid!=0 or stat.S_IMODE(s.st_mode)!=0o700:raise ValueError('unsafe runtime lock directory')
 fd=os.open(run/'operation.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW|os.O_NONBLOCK,0o600)
 try:
  fs=os.fstat(fd)
  if not stat.S_ISREG(fs.st_mode) or fs.st_uid!=0 or fs.st_nlink!=1:raise ValueError('unsafe operation lock')
  fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
  # A partial installer may not have acquired the lock yet.
  for cmdline in Path('/proc').glob('[0-9]*/cmdline'):
   try:args=cmdline.read_bytes().split(b'\0')
   except (OSError,ProcessLookupError):continue
   if any(Path(x.decode(errors='replace')).name in ('setup-cybertiel.sh','install-cybertiel.sh') for x in args):raise ValueError('installer/setup process active')
  r=subprocess.run(['/usr/bin/docker','ps','-a','--filter','label=io.cybertiel.managed','--format','{{.ID}}'],capture_output=True,text=True,timeout=30,env={'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','DOCKER_HOST':'unix:///var/run/docker.sock'})
  if r.returncode!=0 or r.stdout.strip():raise ValueError('Docker unavailable or managed containers present; no archive')
  paths=partial(Path('/opt/cybertiel'),Path('/srv/cybertiel'))
  suffix='.v25-r2-backup-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
  targets=[p.with_name(p.name+suffix) for p in paths]
  if any(p.exists() or p.is_symlink() for p in targets):raise ValueError('backup destination exists')
  print(json.dumps({'mode':'APPLY' if a.apply else 'PLAN','preserved_renames':{str(p):str(t) for p,t in zip(paths,targets)}},indent=2))
  if a.apply:
   done=[]
   try:
    for p,t in zip(paths,targets):os.rename(p,t);done.append((p,t))
   except Exception:
    for p,t in reversed(done):os.rename(t,p)
    raise
   print('Archived; all original files preserved. Now use the verified v25-r3 setup.')
 finally:os.close(fd)
if __name__=='__main__':
 try:main()
 except (ValueError,OSError,subprocess.SubprocessError) as e:raise SystemExit('REFUSED: '+str(e))
