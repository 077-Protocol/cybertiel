# CyberTiel v25-r3.6

This release fixes the Pi 1.0.3 lockfile installation failure and the build/toolchain problems found while installing CyberTiel on Ubuntu. It is based on public commit `6acfe4624607581223b56163d4617adbe99345f5` of `077-Protocol/cybertiel`.

The complete installer passed a real Ubuntu 24.04.5 LTS x86_64 deployment. Pi read a synthetic debug log, edited the actual C++ implementation, and the repaired program passed four native acceptance cases. A Windows x64 EXE was also built; Windows execution and the user's own project were not tested. The independent postinstall checker performed deep model hashes and live runtime probes: 131 PASS, zero FAIL, three WARN and four UNTESTED items. The inspector itself does not generate model inference; the completed Pi repair receipt provides that evidence separately.

The official Pi lock stays unchanged, with SHA256 `d2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7`. Eight missing SHA512 SRI values are supplied by a separate pinned manifest, checked against official registry metadata and tarballs. A deterministic derived lock changes exactly eight integrity fields. npm ci uses that lock with scripts disabled. Installed metadata, dependency tree, READY receipts, source bindings and independent checker pins remain enforced.

The follow-up installs pkg-config and the Debian mypy CLI, preserves the verified modprobe alias, publishes the public build lock as readable to the non-root image user, and corrects temporary HOME/cache setup and native toolchain fixtures. Temporary build scratch explicitly permits execution. Non-root users, read-only root filesystems, nosuid/nodev, dropped capabilities, no-new-privileges, seccomp, AppArmor, resource limits and isolated networking remain enforced.

Package revision: `2026-10-06.v25-r3.6`. Managed installer identity: `2026-10-06.v25-r3`, retained so partial v25-r3 installations can resume. Independent checker: `CT-CHECK-2.9.6`. Model, llama.cpp, Node/npm base and original Pi assets retain their source pins. No model weights or upstream tarballs are bundled.

Download [the sealed installer ZIP](releases/v25-r3.6/cybertiel-v25-r3.6.zip) and its [SHA256](releases/v25-r3.6/cybertiel-v25-r3.6.zip.sha256). Start with `SERVER_STEPS.txt`. Keep existing v25-r2 backups; do not archive a partial v25-r3 installation. The guarded archival helper is only for the earlier partial v25-r2 state and refuses qualified installations, project data, active installers and managed containers.

Validation: 355 regression checks across 16 isolated x86_64 Linux suites and two additional cppcheck regression checks passed. The tested candidate ZIP was safely extracted and all files/script bindings were verified. Final archive changes add qualification records and documentation; executable bytes remain identical to the qualified candidate. Current records are under `evidence/v25-r3.6`. Earlier `evidence` and `docs/evidence` records remain historical.

The deployment qualified the official Q8_K_XL model, 262144 configured context, Pi 1.0.3, toolchain, source repair and sandbox/runtime checks. Image inference, the user's project, Windows execution and sustained context/performance benchmarks remain separate qualifications. This distribution adds no repository-wide license grant.

Operator details: [usage](docs/USAGE.md), [threat model](docs/THREAT_MODEL.md).
