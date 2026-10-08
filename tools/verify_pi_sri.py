#!/usr/bin/env python3
"""Independently re-fetch official release bytes, metadata and eight tarballs. Read-only."""
import base64,hashlib,json,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
manifest_raw=(ROOT/'generated-config/pi-sri-manifest.json').read_bytes()
assert hashlib.sha256(manifest_raw).hexdigest()=='0ccc765161d1a5023ab8ac02f06642d99cf51156738a76075362af3f2ec56bd8'
manifest=json.loads(manifest_raw)
def get(url,limit):
 with urllib.request.urlopen(url,timeout=90) as r:
  data=r.read(limit+1)
 if len(data)>limit:raise ValueError('upstream input too large')
 return data
for name,pin in [('package','9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea'),('package-lock',manifest['official_lock_sha256'])]:
 data=get('https://github.com/earendil-works/pi/releases/download/v1.0.3/pi-coding-agent-install-'+name+'.json',8*1024*1024)
 if hashlib.sha256(data).hexdigest()!=pin:raise ValueError('official release hash mismatch')
 print('PASS official '+name)
for key,pin in manifest['packages'].items():
 meta=json.loads(get(pin['metadata_url'],1024*1024))
 if meta['name']!=pin['name'] or meta['version']!=pin['version'] or meta['dist']['tarball']!=pin['resolved'] or meta['dist']['integrity']!=pin['integrity']:raise ValueError('registry identity/SRI mismatch')
 raw=get(pin['resolved'],32*1024*1024)
 actual='sha512-'+base64.b64encode(hashlib.sha512(raw).digest()).decode()
 if actual!=pin['integrity'] or hashlib.sha256(raw).hexdigest()!=pin['tarball_sha256'] or len(raw)!=pin['tarball_bytes']:raise ValueError('tarball mismatch')
 print('PASS '+pin['name']+'@'+pin['version'])
print('PASS official pair + 8/8 metadata/tarballs; no dependency code executed')
