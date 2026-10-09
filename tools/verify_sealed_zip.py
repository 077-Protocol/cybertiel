#!/usr/bin/env python3
"""Verify archive paths, entry types and complete SHA256 coverage without extracting."""
import argparse,hashlib,json,re,stat,zipfile
from pathlib import PurePosixPath,Path
PREFIX='cybertiel-v25-r3.6/'
def verify(path,expected=None):
 raw=Path(path).read_bytes();digest=hashlib.sha256(raw).hexdigest()
 if expected and digest!=expected:raise ValueError('ZIP SHA256 mismatch')
 with zipfile.ZipFile(path) as z:
  infos=z.infolist();names=[i.filename for i in infos]
  if len(names)!=len(set(names)):raise ValueError('duplicate ZIP member')
  for i in infos:
   p=PurePosixPath(i.filename);mode=i.external_attr>>16
   if not i.filename.startswith(PREFIX) or '..' in p.parts or str(p)!=i.filename or p.is_absolute() or '\\' in i.filename:raise ValueError('unsafe ZIP member')
   if i.is_dir() or stat.S_IFMT(mode)!=stat.S_IFREG or i.file_size>20*1024*1024:raise ValueError('nonregular/oversized ZIP member')
  sums=z.read(PREFIX+'SHA256SUMS').decode().splitlines();manifest={}
  for line in sums:
   h,n=line.split('  ',1)
   if not re.fullmatch('[0-9a-f]{64}',h) or n in manifest:raise ValueError('invalid checksum manifest')
   manifest[n]=h
  if set(names)!={PREFIX+n for n in manifest}|{PREFIX+'SHA256SUMS'}:raise ValueError('ZIP coverage differs from checksum manifest')
  for n,h in manifest.items():
   if hashlib.sha256(z.read(PREFIX+n)).hexdigest()!=h:raise ValueError('member checksum mismatch: '+n)
 return {'status':'PASS','zip_sha256':digest,'checked_files':len(manifest),'zip_bytes':len(raw),'scope':'Complete archive byte integrity and safe paths; no publisher signature or server qualification'}
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('zip');ap.add_argument('--sha256');a=ap.parse_args()
 try:print(json.dumps(verify(a.zip,a.sha256),indent=2))
 except (ValueError,OSError,KeyError,zipfile.BadZipFile) as e:raise SystemExit('REJECT: '+str(e))
