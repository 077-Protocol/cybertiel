# CyberTiel

A local coding-agent environment for a dedicated Ubuntu CPU server, with a pinned installer, an independent checker and explicit readiness gates.

CyberTiel brings together Cyber-Tiel-Coder-35B-A3B, llama.cpp and the Pi coding agent. The agent works inside a restricted Docker container with a C/C++ and Windows cross-compilation toolchain. This repository focuses on the boundary around that agent: what it can access, how projects enter the workspace, and what evidence is needed before an installation can be trusted.

I am publishing this as part of my cybersecurity portfolio. The useful part is not a claim that the system is “secure”; it is a reviewable implementation, concrete failure cases and an honest account of what remains untested.

**Status: candidate for a controlled target trial.** This is not a production certification or proof of a working end-to-end deployment.

## Who this is for

People comfortable reviewing shell and Python code, managing a dedicated Linux host and testing container isolation. The intended target is a fresh **Ubuntu 24.04 LTS x86_64 CPU server**, with AVX2 and at least **110 GiB of visible RAM** (the original profile targets a 128 GB Xeon server). The preflight also requires at least 90 GiB free for `/srv` and 5 GiB for `/`; installation performs additional storage checks.

The profile requires Docker Engine 28 or newer and checks AppArmor/seccomp enforcement. It is not a macOS installer, an ARM deployment or an unattended migration of an existing server. Review the pinned dependencies before using it on a current host.

The model is the official **UD-Q8_K_XL**, not BF16 and not a Q4/Q5 fallback. The source lock records approximately 38.5 GB for the model plus a BF16 vision projector. No model weights are included. The configured 262,144-token context is a requested setting, not a demonstrated memory or throughput result.

## What is included

- `setup-cybertiel.sh`: coordinator that verifies the installer/checker bytes before staging and running them.
- `install-cybertiel.sh`: host gates, pinned downloads, container builds and installation checks.
- `check-cybertiel-server.sh` and `checker/`: independent inspection with PASS, FAIL, WARN and UNTESTED results.
- `generated-config/`: the 18 files emitted by the installer, including the installed `cybertiel` launcher, policies and validation helpers.
- Offline regression tests and selected historical evidence, with their scope explained in [audit notes](docs/AUDIT.md).

## Try it on the intended server

Read [the threat model](docs/THREAT_MODEL.md) and [the operator guide](docs/USAGE.md) first. Use scripts from one checkout; mixing versions defeats the byte pins.

```bash
git clone https://github.com/077-Protocol/cybertiel.git
cd cybertiel
python3 tools/verify_release.py
bash preflight-server.sh
bash setup-cybertiel.sh --plan
```

A blocked preflight is a reason to investigate, not to remove a gate. `--plan` does not install the system. Installation is a separate, deliberate step that changes the host, downloads large assets and builds containers:

```bash
sudo bash setup-cybertiel.sh --install --accept-official-q8
sudo bash check-cybertiel-server.sh --installer ./install-cybertiel.sh
```

After installation and successful checks:

```bash
sudo cybertiel import /path/to/project
sudo cybertiel
sudo cybertiel status
```

Import expects an empty managed project directory. Review the source project for credentials before importing it. The agent can edit and execute files in that workspace.

## Evidence and limitations

The supplied package contains a historical pre-seal report of **473 PASS / 0 FAIL across 15 suites**. That is reported source evidence, not a fresh result for this Git checkout. The separate final sealed-ZIP report was not present in the supplied directory.

During preparation for publication, all **173 source-manifest entries** matched their hashes, sizes and modes. The three current script bindings also matched. Fresh local checks are recorded separately in [publication validation](docs/evidence/PUBLICATION_VALIDATION.json); they must not be confused with the earlier Linux regressions or a target installation.

**Fresh local suite results:** checker contracts 39/0; installer tests 106/4 on macOS. Two failures involve GNU `realpath -m`; two download-mock assertions also failed and need Linux reproduction. The local result is not all green.

Still required: a real Ubuntu installation, Docker builds and runtime isolation tests, Pi dependency/CLI/SDK checks, complete model/projector download and inference, CPU memory/soak measurements, a real project build and execution in a clean Windows VM. A cross-compiled Windows executable is not proof that it runs correctly on Windows.

## Version and provenance

| Component | Source identity |
|---|---|
| Package | `2026-10-06.v25-r2` |
| Installer | `2026-10-06.v25` |
| Checker | `CT-CHECK-2.8.0` |
| Parent recorded by source | `2026-10-06.v25-r1` |

This repository is a curated distribution of the supplied directory, not the original sealed ZIP. Runtime scripts and generated configuration are preserved byte for byte. Older archives, temporary logs and repetitive audit narratives are omitted. Its own `SHA256SUMS` describes the published files.

There is a known source metadata error: `SOURCE_LOCK.json` records a **65-character parent checker hash**, which is not a valid SHA-256. It is retained for transparency and must not be used to authenticate the parent. Current script bindings are valid and verified. See [audit notes](docs/AUDIT.md) for the consequences.

## Contributing

A useful issue includes the exact checkout, a minimal reproduction, expected and actual behavior, and sanitized evidence. Please distinguish static checks, mocked execution and real target results. Do not attach API keys, private project code or raw machine logs.

Model weights and upstream dependencies are not redistributed here. Their respective licenses and terms still apply. This initial publication does not add a repository-wide license grant.
