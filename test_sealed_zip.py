#!/usr/bin/env python3
"""Archive integrity failure cases; tiny synthetic ZIPs."""
import hashlib,importlib.util,json,tempfile,zipfile,stat
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sp=importlib.util.spec_from_file_location('seal',ROOT/'tools/verify_sealed_zip.py');m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
rows=[]
def check(n,f):
 try:f();s='PASS';d=''
 except Exception as e:s='FAIL';d=repr(e)
 rows.append(dict(id=n,status=s,detail=d))
def reject(f):
 try:f()
 except (ValueError,OSError,KeyError,zipfile.BadZipFile):return
 raise AssertionError('unsafe ZIP accepted')
with tempfile.TemporaryDirectory() as td:
 p=Path(td)/'tiny.zip'
 def build(mutation=''):
  with zipfile.ZipFile(p,'w') as z:
   contents=[('a.txt',b'ok'),('SHA256SUMS',(hashlib.sha256(b'ok').hexdigest()+'  a.txt\n').encode())]
   if mutation=='changed':contents[0]=('a.txt',b'changed')
   if mutation=='extra':contents.append(('extra.txt',b'extra'))
   if mutation=='traversal':contents.append(('../escape.txt',b'escape'))
   if mutation=='missing':contents=contents[1:]
   if mutation=='duplicate':contents.append(contents[0])
   for n,b in contents:
    i=zipfile.ZipInfo(m.PREFIX+n);i.external_attr=(stat.S_IFREG|0o644)<<16
    if mutation=='symlink' and n=='a.txt':i.external_attr=(stat.S_IFLNK|0o777)<<16
    z.writestr(i,b)
 build();check('complete_synthetic_zip_accepted',lambda:m.verify(p))
 check('wrong_external_ZIP_SHA_rejected',lambda:reject(lambda:m.verify(p,'0'*64)))
 for case in ['changed','extra','traversal','missing','duplicate','symlink']:
  build(case);check('reject_'+case,lambda:reject(lambda:m.verify(p)))
report={'passed':sum(x['status']=='PASS' for x in rows),'failed':sum(x['status']=='FAIL' for x in rows),'results':rows,'scope':'synthetic malformed archives; final actual ZIP checked separately'}
(ROOT/'SEALED_ZIP_NEGATIVE_TEST_REPORT.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(bool(report['failed']))
