#!/usr/bin/env python3
"""Cross-check Pi's published package shrinkwrap against the official v1 release installer lock."""
import json, pathlib, sys

def load_regular(path):
    p=pathlib.Path(path)
    if not p.is_file() or p.is_symlink() or p.stat().st_size > 16*1024*1024:
        raise ValueError(f"unsafe/non-regular lock input: {p}")
    return json.loads(p.read_text(encoding="utf-8"))

def verify(package_path, lock_path, shrink_path, version):
    pkg=load_regular(package_path); lock=load_regular(lock_path); shrink=load_regular(shrink_path)
    if pkg.get("name") != "@earendil-works/pi-coding-agent-install" or pkg.get("version") != version:
        raise ValueError("official Pi installer package identity mismatch")
    if pkg.get("dependencies") != {"@earendil-works/pi-coding-agent": version}:
        raise ValueError("official Pi installer dependency mismatch")
    if (pkg.get("overrides") or {}).get("protobufjs") != "7.6.6":
        raise ValueError("official Pi protobufjs override missing")
    if lock.get("lockfileVersion") != 3 or shrink.get("lockfileVersion") != 3:
        raise ValueError("Pi lockfile version mismatch")
    lp=lock.get("packages"); sp=shrink.get("packages")
    if not isinstance(lp,dict) or not isinstance(sp,dict):
        raise ValueError("Pi package maps missing")
    root=lp.get("") or {}
    if root.get("name") != pkg["name"] or root.get("version") != version or root.get("dependencies") != pkg["dependencies"]:
        raise ValueError("official Pi installer lock root mismatch")
    sroot=sp.get("") or {}
    if sroot.get("name") != "@earendil-works/pi-coding-agent" or sroot.get("version") != version:
        raise ValueError("published Pi shrinkwrap root mismatch")
    for item, entry in sp.items():
        if item == "": continue
        if lp.get(item) != entry:
            raise ValueError(f"Pi release lock graph differs at {item}")
    extra=sorted(set(lp)-set(sp))
    if extra != ["node_modules/@earendil-works/pi-coding-agent"]:
        raise ValueError(f"unexpected Pi installer-lock extras: {extra}")
    pi_entry=lp[extra[0]]
    if pi_entry.get("version") != version:
        raise ValueError("Pi installer-lock root package version mismatch")
    return {
      "status":"PASS", "pi_version":version,
      "shared_dependency_entries":len(sp)-1,
      "official_install_lock_entries":len(lp),
      "only_extra_install_lock_entry":extra[0],
      "comparison":"every dependency entry from published npm-shrinkwrap is byte-for-byte JSON-equal to the official v1.0.0 installer package-lock entry",
      "root_tarball_integrity":"verified separately by pinned npm sha512 before image build"
    }

if __name__=="__main__":
    try:
        print(json.dumps(verify(sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]),indent=2))
    except (OSError,ValueError,TypeError,KeyError,IndexError,json.JSONDecodeError) as exc:
        raise SystemExit(f"FAIL: {exc}")
