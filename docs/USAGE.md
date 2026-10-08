# Operator guide

For this v25-r3 distribution, first follow `../SERVER_STEPS.txt`, including independent ZIP/SRI checks and preservation of the failed v25-r2 directories. Use the delivered package rather than the still-published v25-r2 GitHub checkout. Current validation evidence lives in `../evidence/v25-r3`.

## Before installation

Use a dedicated fresh Ubuntu 24.04 x86_64 server. Review the scripts, source pins and threat model. Keep access to the provider console or a persistent terminal session during downloads and builds. Prepare backups outside the managed workspace.

Run `python3 tools/verify_release.py` from the checkout, then `bash preflight-server.sh`. A basic preflight pass is not installation or isolation proof. It checks the OS, architecture, AVX2, visible RAM and basic disk space. Additional installer gates remain authoritative.

Run `bash setup-cybertiel.sh --plan` to inspect the plan and verify the paired scripts. Do not edit one pinned script and expect the existing setup/checker to accept it. A release change needs updated byte bindings and validation.

## Install and inspect

```bash
sudo bash setup-cybertiel.sh --install --accept-official-q8
sudo bash check-cybertiel-server.sh --installer ./install-cybertiel.sh
```

Installation changes host packages, managed directories and Docker state. It can require a reboot after updates. Investigate a failed gate and follow its message; do not silently weaken the requirements. Existing unmanaged files and conflicting installations can be rejected.

The coordinator records `setup-result.json` and checker output at the locations it reports. Review results locally before sharing them. `UNTESTED` does not mean success. Runtime probes are explicit:

```bash
sudo bash check-cybertiel-server.sh --installer ./install-cybertiel.sh --deep-model-hash --runtime
```

Deep hashing and runtime checks can be expensive. They inspect/read large assets and perform runtime probes; they are not equivalent to a cheap passive status check.

## Use the installed launcher

`generated-config/cybertiel-launcher` is the installer-emitted source of `/usr/local/bin/cybertiel`. Do not run that generated copy as a standalone installer.

```bash
sudo cybertiel import /path/to/project
sudo cybertiel                 # foreground coding-agent session
sudo cybertiel status
sudo cybertiel logs
sudo cybertiel stop
sudo cybertiel start
sudo cybertiel import-log /path/to/debug.log
```

Project import is intended for a one-time import into an empty managed directory. It refuses an occupied destination and rejects incomplete verification. Review the imported tree, including repository metadata, for secrets. Start with a disposable project copy.

Coordination locks may refuse stop/import/check operations while an agent session owns the lock. End the foreground session from its own terminal before a conflicting operation. Do not bypass the lock to force concurrent mutation.

## Windows acceptance

Cross-compilation and Linux PowerShell checks do not certify Windows runtime behavior. Test the exact Windows artifact in a clean Windows VM, record its SHA-256 and build identity, and retain a sanitized result. A debug log alone is insufficient unless its origin is bound to that artifact and source generation.

## Offline tests

The included suites are scripts, not one universal test runner. Run them in a disposable Linux checkout with GNU tools, Python, Bash, Node and the relevant build tools. Some suites require root; permission-sensitive tests require an ordinary user. Tests can write report JSONs next to themselves. Do not run the root-required suites on a personal workstation without reviewing their fixtures and filesystem operations.

Examples that do not install CyberTiel:

```bash
python3 -B test-installer.py
python3 -B checker/test_checker_v3.py
python3 -B test_log_import_safety.py  # ordinary user
```

Historical comparison suites that require omitted parent archives are excluded from this distribution. The retained suite count therefore differs from the historical 15-suite source report.
