# CyberTiel v25-r3 — Pi 1.0.3 SRI repair

Complete local installer distribution based on public commit `6acfe4624607581223b56163d4617adbe99345f5` of `077-Protocol/cybertiel`. The repair is published as a reviewable patch with its sealed installer ZIP. Target-side installation and runtime qualification remain pending.

The official Pi 1.0.3 installer lock is preserved byte for byte (SHA256 `d2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7`). Its eight missing SHA512 SRI values are supplied by a separate pinned manifest. Each official tarball was freshly downloaded and checked against npm registry metadata. A deterministic derived lock changes exactly those eight `integrity` fields; npm ci uses that derived lock with scripts disabled. Original and derived hashes, installed metadata, dependency tree, READY receipts and independent checker pins are enforced.

Package and runtime installer: `2026-10-06.v25-r3`. Checker: `CT-CHECK-2.9.0`. Generated files, setup script bindings, checker baseline source snapshots and source pins have been updated together. Historical checker baseline identities remain present. Model, llama.cpp, Node base, container restrictions and host gates remain pinned to the parent values.

Download the exact installer from [`releases/v25-r3/cybertiel-v25-r3.zip`](releases/v25-r3/cybertiel-v25-r3.zip) and compare its [SHA256](releases/v25-r3/cybertiel-v25-r3.zip.sha256). The ZIP is the same artifact used for the final sealed-package tests; its contents are preserved unchanged.

**Start with `SERVER_STEPS.txt`.** It includes independent verification and guarded archival of the failed v25-r2 installation. The archival helper preserves all files and refuses qualified installations, project data, active installers and managed containers. It does not relabel old evidence as a new installation.

Validation: **330 PASS / 0 FAIL across 14 Linux suites**, plus **8 PASS / 0 FAIL archive negative tests**. Actual npm ci and npm ls passed on macOS arm64 with Node 24.21.0/npm 11.19.0. A corrupt SRI was rejected by npm with EINTEGRITY. See `evidence/v25-r3/VALIDATION_SUMMARY.json` and individual reports/logs. The final ZIP verification is recorded in `evidence/v25-r3/SEALED_VERIFICATION.json`: 338 PASS / 0 FAIL across 15 suites run against the extracted ZIP.

Ubuntu 24.04 x86_64 deployment, Docker builds, Pi runtime, model inference and Windows execution have not been performed here. The installer retains its target-side gates and smoke tests. Linux regression execution used an isolated Alpine VM with GNU tools, not a claimed Ubuntu server installation. Older `docs/evidence` files are parent/historical evidence; current results are in `evidence/v25-r3`.

No model weights or upstream tarballs are bundled. The unchanged original release assets and npm metadata are included under `upstream` for review. Tarballs can be checked again with `python3 tools/verify_pi_sri.py`, which downloads but never executes dependency code.

Operator details: [usage](docs/USAGE.md), [threat model](docs/THREAT_MODEL.md). This distribution adds no repository-wide license grant.
