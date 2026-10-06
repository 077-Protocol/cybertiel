#!/usr/bin/env python3
"""Read-only verification of the curated checkout. Does not install CyberTiel."""
import ast
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors = []
warnings = []

def require(condition, message):
    if not condition:
        errors.append(message)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

lock = json.loads((ROOT / 'SOURCE_LOCK.json').read_text())
for name, expected in lock['script_bindings'].items():
    require(bool(re.fullmatch(r'[0-9a-f]{64}', expected)), f'Invalid current digest: {name}')
    require(digest(ROOT / name) == expected, f'Current script mismatch: {name}')
installer = (ROOT / 'install-cybertiel.sh').read_text()
checker = (ROOT / 'checker/check_cybertiel.py').read_text()
require(f"readonly INSTALL_ID={lock['installer_id']}\n" in installer, 'Installer identity mismatch')
require(f"VERSION = '{lock['checker']}'" in checker, 'Checker identity mismatch')
require((ROOT / 'check-cybertiel-server.sh').read_bytes() ==
        (ROOT / 'checker/check-cybertiel-server.sh').read_bytes(), 'Checker wrappers differ')
setup = (ROOT / 'setup-cybertiel.sh').read_text()
helper = (ROOT / 'setup_helper.py').read_text()
require(setup.split("<<'CYBERTIEL_SETUP_PY'\n", 1)[1].rsplit('CYBERTIEL_SETUP_PY', 1)[0] == helper,
        'Embedded setup helper differs')
pins = next(ast.literal_eval(n.value) for n in ast.parse(helper).body
            if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'PINS' for t in n.targets))
require(pins == {n: lock['script_bindings'][n] for n in pins}, 'Setup pins mismatch')
parent = lock['lineage']['parent_checker_sha256']
if not re.fullmatch(r'[0-9a-f]{64}', parent):
    warnings.append('Known source error: parent checker digest is malformed; parent authentication is unavailable.')
count = 0
for line in (ROOT / 'SHA256SUMS').read_text().splitlines():
    expected, name = line.split('  ', 1)
    rel = Path(name)
    require(not rel.is_absolute() and '..' not in rel.parts, 'Unsafe checksum path')
    if rel.is_absolute() or '..' in rel.parts:
        continue
    path = ROOT / rel
    require(path.is_file() and not path.is_symlink(), f'Missing/non-regular file: {name}')
    if path.is_file():
        require(digest(path) == expected, f'Published file mismatch: {name}')
    count += 1
print(json.dumps({'status': 'FAIL' if errors else 'PASS_WITH_KNOWN_SOURCE_WARNING',
                  'checked_files': count, 'errors': errors, 'warnings': warnings,
                  'scope': 'Local byte/identity consistency; not publisher authentication or runtime qualification'}, indent=2))
raise SystemExit(bool(errors))
