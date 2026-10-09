#!/usr/bin/env python3
"""Validate Pi 1.0.3's official installer lock and optional installed tree.
No npm install, scripts, network, or project execution. Hash pins originate from
GitHub's official v1.0.3 release-asset metadata. Does not claim a full CVE audit.
"""
import argparse
import copy
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
from urllib.parse import urlsplit

VERSION = "1.0.3"
NAME = "@earendil-works/pi-coding-agent"
PACKAGE_SHA = "9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea"
LOCK_SHA = "d2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7"
DERIVED_LOCK_SHA = '1d93efc1f55498590ec6d3c8aabda72654a22f67360c2507906c9c5449e0da0a'
SRI_MANIFEST_SHA = '0ccc765161d1a5023ab8ac02f06642d99cf51156738a76075362af3f2ec56bd8'
SRI_MANIFEST = {'official_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'packages': {'node_modules/@earendil-works/chord': {'integrity': 'sha512-H5pKMs3S1z2q4V7NkDGKDFzOMW+OkzdsnGxxj5wNJUANG03VKj29UVmc1xnnnf0FAc03COHYNxwgNApO0nt0fg==', 'metadata_sha256': '7aeb6ef45eb76d0331378ef991714979583cfcb93736bc78062051b0155c2e3b', 'metadata_url': 'https://registry.npmjs.org/@earendil-works/chord/1.0.3', 'name': '@earendil-works/chord', 'resolved': 'https://registry.npmjs.org/@earendil-works/chord/-/chord-1.0.3.tgz', 'tarball_bytes': 209518, 'tarball_sha256': '2b4bdd82da35b9c1e4e10fb0fe1ba2cd99e46eb7419aa2616de0f124e701a8ed', 'version': '1.0.3'}, 'node_modules/@earendil-works/pi-agent-core': {'integrity': 'sha512-lnvi2PJYaq8mDLzwWBttNqfxrLS63SSMONUJnTCypdvt/flmNJchXwWXsXUOJ5Yhe/mN+iHkrXu696lWZZ8o+w==', 'metadata_sha256': '92500d96b193a6d42b437e0f28e9d35efd076a04a9f4d68ab77ea91050eaed1c', 'metadata_url': 'https://registry.npmjs.org/@earendil-works/pi-agent-core/1.0.3', 'name': '@earendil-works/pi-agent-core', 'resolved': 'https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-1.0.3.tgz', 'tarball_bytes': 61366, 'tarball_sha256': '1a6466c6d10849960f62f6066ce6d159c721c4d294bcf3536519f65684a719e1', 'version': '1.0.3'}, 'node_modules/@earendil-works/pi-ai': {'integrity': 'sha512-p+/EUrbmfT0xWOtL/NJRtWOsyzcKKFSyiivHLDBMG0DUVpHdaIykd5jFibq0YZDFGBN/nv61zdOelMb+ylPfSg==', 'metadata_sha256': '4e5fd07a7945a467743683d8698425f44d982d052ac83122972a2e4cad8d5560', 'metadata_url': 'https://registry.npmjs.org/@earendil-works/pi-ai/1.0.3', 'name': '@earendil-works/pi-ai', 'resolved': 'https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-1.0.3.tgz', 'tarball_bytes': 774640, 'tarball_sha256': 'dd8995fb1df3ca3e2bd033053bd2c28b40c44bb7f53c253578ca68082611e0ee', 'version': '1.0.3'}, 'node_modules/@earendil-works/pi-codemode': {'integrity': 'sha512-/rgWAXA9PhuFm0+j6N5FVvvWrAwt1LnhmbjA3Hy5+Q033XUHgh0YCMGAmU76S90ocr0Vfxm50ddYT/O76T5OGQ==', 'metadata_sha256': 'a00845637438a179576ee3b25ab88d7364abf28eff1d77216b858e4fa63831f6', 'metadata_url': 'https://registry.npmjs.org/@earendil-works/pi-codemode/1.0.3', 'name': '@earendil-works/pi-codemode', 'resolved': 'https://registry.npmjs.org/@earendil-works/pi-codemode/-/pi-codemode-1.0.3.tgz', 'tarball_bytes': 54560, 'tarball_sha256': '698162182c454bf98d7f208b7b8d345781c2d4d33cae6886fd92a087e145c183', 'version': '1.0.3'}, 'node_modules/@earendil-works/pi-coding-agent': {'integrity': 'sha512-t2lb0dw4y/jr5a2PRo6eTHGTZOPB3/YAMVyhhYFC1W3Hl5xE+462I/gMWjF4gCLuhGipNEfuNqONFmdqLFz4SQ==', 'metadata_sha256': '0d31f06a59bb8f5529b8b8a533162d50248fd1c86698ca4bd603ab98ba957b77', 'metadata_url': 'https://registry.npmjs.org/@earendil-works/pi-coding-agent/1.0.3', 'name': '@earendil-works/pi-coding-agent', 'resolved': 'https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-1.0.3.tgz', 'tarball_bytes': 7474225, 'tarball_sha256': '106eadb1f823f72f012c08f23bd36e435f9e62f6c81e98a5d8f70c8a9543dd05', 'version': '1.0.3'}, 'node_modules/@earendil-works/pi-mcp': {'integrity': 'sha512-ZAhL/g0rpjyKtcKzD0jSDk7sFIrMCQocmKtpAE1F9eRnI5fGGVWUyiZwALG/Tn1sagzxFbSqtc29zGx5OvDDGA==', 'metadata_sha256': '155613f97f0601765a777eb24bf88e04162c2dff150c048834c9c465af0554a3', 'metadata_url': 'https://registry.npmjs.org/@earendil-works/pi-mcp/1.0.3', 'name': '@earendil-works/pi-mcp', 'resolved': 'https://registry.npmjs.org/@earendil-works/pi-mcp/-/pi-mcp-1.0.3.tgz', 'tarball_bytes': 90153, 'tarball_sha256': '0ca4a95f2a1459e51ab1d761ac84186bf2cf2bd2c236034d8f18513e964df229', 'version': '1.0.3'}, 'node_modules/@earendil-works/pi-telemetry': {'integrity': 'sha512-Li4YamN09x9zzCquPbtEL2AQmwqv3Vn3sNOYqG0DRg24fjiMfntCsb7QKbejCXZssTAyaN+hutLl6O0UnJDrfg==', 'metadata_sha256': '38ab5d44f2cb293e3d0c267b5cfb3ea00b84bfd4fb9ec218705b20c8cf3fe014', 'metadata_url': 'https://registry.npmjs.org/@earendil-works/pi-telemetry/1.0.3', 'name': '@earendil-works/pi-telemetry', 'resolved': 'https://registry.npmjs.org/@earendil-works/pi-telemetry/-/pi-telemetry-1.0.3.tgz', 'tarball_bytes': 27361, 'tarball_sha256': 'a7331de30f12f42b32b743681b572cc8e414eacbff49c973212c096bf1029ea2', 'version': '1.0.3'}, 'node_modules/@earendil-works/pi-tui': {'integrity': 'sha512-C7b8Y+7iz+/oPEZUJubv6NPm3M/4ziq0hjQ2jhqMNpBwcXeqDMYKL2FYP90t2b5S1IoGc2io47dj5ZlIC1IZWg==', 'metadata_sha256': '1bae98370443df6b2758b8afce06d94a994d076b2fcc061a1ed1e7751a715cc4', 'metadata_url': 'https://registry.npmjs.org/@earendil-works/pi-tui/1.0.3', 'name': '@earendil-works/pi-tui', 'resolved': 'https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-1.0.3.tgz', 'tarball_bytes': 513772, 'tarball_sha256': '673000db8f98fd8c3166d7ca8fb9b6679bf341a4aa6961966f6e20834dbfa205', 'version': '1.0.3'}}, 'schema': 'cybertiel-pi-sri/v1'}
MAX_BYTES = 8 * 1024 * 1024


def unique(pairs):
    d = {}
    for k, v in pairs:
        if k in d:
            raise ValueError("duplicate JSON key")
        d[k] = v
    return d


def load(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        s = os.fstat(fd)
        if not stat.S_ISREG(s.st_mode) or s.st_size > MAX_BYTES:
            raise ValueError("lock input type/size")
        with os.fdopen(os.dup(fd), "rb") as f:
            raw = f.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError("lock input oversized")
        e = os.fstat(fd)
        if (s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns) != (e.st_dev,e.st_ino,e.st_size,e.st_mtime_ns,e.st_ctime_ns):
            raise ValueError("lock changed during read")
        obj = json.loads(raw, object_pairs_hook=unique,
            parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))
        todo = [(obj, 0)]; nodes = 0
        while todo:
            v, depth = todo.pop(); nodes += 1
            if depth > 64 or nodes > 100000:
                raise ValueError("JSON complexity limit")
            if isinstance(v, dict): todo.extend((a,depth+1) for a in v.values())
            elif isinstance(v, list): todo.extend((a,depth+1) for a in v)
        return obj, hashlib.sha256(raw).hexdigest()
    finally:
        os.close(fd)


def package_name(key):
    parts = PurePosixPath(key).parts
    if not isinstance(key,str) or str(PurePosixPath(key)) != key or not parts or PurePosixPath(key).is_absolute() or any(p in (".","..") for p in parts) or "\\" in key:
        raise ValueError("unsafe npm package path")
    i = 0; result = None
    while i < len(parts):
        if parts[i] != "node_modules" or i + 1 >= len(parts):
            raise ValueError("invalid npm lock key")
        i += 1
        if parts[i].startswith("@"):
            if i+1 >= len(parts): raise ValueError("invalid scoped package")
            result = parts[i] + "/" + parts[i+1]; i += 2
        else:
            result = parts[i]; i += 1
    if not result or not re.fullmatch(r"(?:@[A-Za-z0-9_.-]+/)?[A-Za-z0-9_.-]+",result):
        raise ValueError("invalid package name")
    return result


def derive_lock(lock):
    # Only callable for the authenticated official asset. Never general missing-SRI repair.
    derived = copy.deepcopy(lock)
    missing = {k for k,e in lock['packages'].items() if k and 'integrity' not in e}
    if missing != set(SRI_MANIFEST['packages']):
        raise ValueError('unexpected missing-SRI package set')
    for key, pin in SRI_MANIFEST['packages'].items():
        entry = derived['packages'][key]
        if package_name(key) != pin['name'] or any(entry.get(f) != pin[f] for f in ('version','resolved')):
            raise ValueError('SRI supplement identity mismatch')
        entry['integrity'] = pin['integrity']
    raw = (json.dumps(derived,indent=2,sort_keys=True)+'\n').encode()
    if hashlib.sha256(raw).hexdigest() != DERIVED_LOCK_SHA:
        raise ValueError('derived lock SHA256 mismatch')
    return derived, raw


def check_pair(pkg, lock):
    if not isinstance(pkg, dict) or not isinstance(lock, dict): raise ValueError("manifest type")
    if pkg.get("name") != NAME + "-install" or pkg.get("version") != VERSION:
        raise ValueError("wrong official installer identity")
    if pkg.get("dependencies") != {NAME: VERSION}:
        raise ValueError("unexpected direct dependencies")
    if lock.get("name") != pkg["name"] or lock.get("version") != VERSION or type(lock.get("lockfileVersion")) is not int or lock["lockfileVersion"] != 3:
        raise ValueError("wrong lock identity/version")
    entries = lock.get("packages")
    if not isinstance(entries, dict) or not 3 <= len(entries) <= 4096: raise ValueError("incomplete/oversized lock")
    root = entries.get("")
    if not isinstance(root,dict) or root.get("dependencies") != pkg["dependencies"] or root.get("version") != VERSION or root.get("name") != pkg["name"]:
        raise ValueError("lock root differs from manifest")
    pi = entries.get("node_modules/"+NAME)
    if not isinstance(pi,dict) or pi.get("version") != VERSION:
        raise ValueError("wrong/missing Pi package")
    if pi.get("resolved") != "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-"+VERSION+".tgz":
        raise ValueError("wrong Pi registry object")
    allowed = {}; brace = []
    for key, entry in entries.items():
        if key == "": continue
        name = package_name(key)
        if not isinstance(entry,dict) or entry.get("link") is True:
            raise ValueError("linked/malformed dependency")
        version = entry.get("version")
        if not isinstance(version,str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.+-]+)?",version):
            raise ValueError("dependency version not exact")
        url = urlsplit(entry.get("resolved", ""))
        if url.scheme != "https" or url.netloc != "registry.npmjs.org" or url.fragment or url.query or not url.path.endswith(".tgz"):
            raise ValueError("dependency registry not allowed")
        sri = entry.get("integrity", "")
        if not isinstance(sri,str) or not sri.startswith("sha512-"):
            raise ValueError("missing sha512 SRI")
        try: digest = base64.b64decode(sri[7:],validate=True)
        except Exception as e: raise ValueError("invalid SRI") from e
        if len(digest) != 64: raise ValueError("invalid sha512 length")
        actual_name = entry.get("name",name)
        if not isinstance(actual_name,str) or not re.fullmatch(r"(?:@[A-Za-z0-9_.-]+/)?[A-Za-z0-9_.-]+",actual_name):
            raise ValueError("invalid aliased package name")
        if actual_name == "brace-expansion":
            if version != "5.0.12": raise ValueError("unreviewed/vulnerable brace-expansion")
            brace.append(key)
        allowed.setdefault(name,set()).add(version)
    if not brace: raise ValueError("brace-expansion missing from proof")
    return entries, allowed, brace


def check_tree(tree, allowed):
    if not isinstance(tree,dict) or tree.get("name") != NAME+"-install" or tree.get("version") != VERSION:
        raise ValueError("wrong installed npm tree root")
    todo = [(tree,0)]; seen = {}; nodes = 0
    while todo:
        node,depth = todo.pop(); nodes += 1
        if depth > 64 or nodes > 20000: raise ValueError("npm tree bound")
        if not isinstance(node,dict) or node.get("problems") or node.get("invalid") or node.get("extraneous") or node.get("missing"):
            raise ValueError("npm reports invalid installed tree")
        deps = node.get("dependencies", {})
        if not isinstance(deps,dict): raise ValueError("invalid dependencies shape")
        for name, child in deps.items():
            if not isinstance(child,dict): raise ValueError("invalid dependency object")
            # npm ls represents optional uninstalled platform packages as {}.
            if child == {}: continue
            version = child.get("version")
            if not isinstance(version,str) or version not in allowed.get(name,set()):
                raise ValueError("installed dependency differs from official lock")
            seen.setdefault(name,set()).add(version); todo.append((child,depth+1))
    if seen.get(NAME) != {VERSION} or seen.get("brace-expansion") != {"5.0.12"}:
        raise ValueError("installed Pi/brace proof missing")
    return nodes


def check_installed(root, entries):
    root = Path(root).resolve(strict=True)
    if not root.is_dir(): raise ValueError("installed root not directory")
    found = {}; missing = []
    for key,entry in entries.items():
        if key == "": continue
        name = package_name(key)
        p = root / key / "package.json"
        if not p.exists():
            # Optional dependencies for other OS/CPU may be omitted by npm.
            if entry.get("optional") is True or entry.get("dev") is True:
                missing.append(key); continue
            raise ValueError("required installed dependency missing: "+key)
        resolved = p.resolve(strict=True)
        if resolved != p or not resolved.is_relative_to(root):
            raise ValueError("installed dependency uses unexpected symlink")
        meta,_ = load(p)
        if not isinstance(meta,dict) or meta.get("name") != entry.get("name",name) or meta.get("version") != entry["version"]:
            raise ValueError("installed dependency metadata mismatch: "+key)
        found[key] = {"name":meta["name"],"version":meta["version"]}
    if not any(v == {"name":"brace-expansion","version":"5.0.12"} for v in found.values()):
        raise ValueError("required patched brace not installed")
    return found, missing


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("package");ap.add_argument("lock")
    ap.add_argument("--require-release-hashes",action="store_true")
    ap.add_argument("--write-install-lock");ap.add_argument("--installed-root");ap.add_argument("--tree")
    args=ap.parse_args()
    pkg,ph=load(args.package);lock,lh=load(args.lock)
    if args.require_release_hashes and (ph != PACKAGE_SHA or lh not in (LOCK_SHA, DERIVED_LOCK_SHA)):
        raise ValueError("official release asset SHA256 mismatch")
    original = lh == LOCK_SHA
    if original:
        if ph != PACKAGE_SHA: raise ValueError('official manifest mismatch')
        lock, derived_raw = derive_lock(lock)
    if args.write_install_lock:
        if not args.require_release_hashes or not original:
            raise ValueError('derivation requires authenticated official pair')
        # Exclusive creation: no symlink, no overwrite of existing lock.
        fd = os.open(args.write_install_lock, os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW, 0o644)
        with os.fdopen(fd,'wb') as f: f.write(derived_raw)
    entries,allowed,brace=check_pair(pkg,lock)
    result={"status":"PASS","pi_version":VERSION,"brace_expansion":"5.0.12",
        "package_sha256":ph,"lock_sha256":lh,
        "official_lock_sha256":LOCK_SHA if args.require_release_hashes else None,
        "derived_lock_sha256":DERIVED_LOCK_SHA if args.require_release_hashes else None,
        "sri_manifest_sha256":SRI_MANIFEST_SHA if args.require_release_hashes else None,"package_entries":len(entries)-1,
        "release_hashes_checked":args.require_release_hashes,"full_vulnerability_audit":False,
        "installed_metadata_checked":False,"installed_tree_checked":False}
    if args.tree:
        tree,_=load(args.tree);result["installed_tree_nodes"]=check_tree(tree,allowed)
        result["installed_tree_checked"]=True
    if args.installed_root:
        found,missing=check_installed(args.installed_root,entries)
        result.update(installed_metadata_checked=True,installed_packages=found,optional_or_dev_omitted=missing)
    print(json.dumps(result,sort_keys=True))


if __name__ == "__main__":
    try: main()
    except (ValueError,OSError,TypeError,KeyError,RecursionError) as e:
        print("PI_LOCK_REJECT: "+str(e),file=sys.stderr);raise SystemExit(1)
