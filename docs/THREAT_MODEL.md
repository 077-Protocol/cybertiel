# Threat model

The central risk is an agent executing commands against project content that may be hostile. Model instructions are not a security boundary. The implementation tries to make the host boundary enforceable and its state inspectable.

## Assets and trust boundaries

Protect the host, Docker control plane, model API credential, pinned configuration and other projects. The imported workspace is writable by the agent; its files and debug logs are untrusted inputs. The host administrator and installer execution are trusted. Root on the host can change the implementation and its evidence.

The launcher runs with host privileges to manage containers. That is distinct from the agent process, which runs as a non-root container user. The model container and coding container have separate roles. The default agent network is intended to reach the model without providing internet access or an isolated bridge gateway to the host.

## Controls to inspect on the target

- No Docker socket or host SSH-key mount in the agent; restricted capabilities, no-new-privileges, read-only container root and required AppArmor/seccomp checks.
- Internal IPv4 Docker network with isolated gateway mode, minimum Engine version and explicit IPv6 handling. No public host port for the model API.
- Read-only baseline templates; private per-run writable Pi configuration and temporary HOME/session storage. Project work remains persistent and visible.
- Immutable source/model pins, hash verification and readiness receipts. Setup reads and verifies all core scripts before executing private staged copies.
- Host coordination locks around conforming installer, checker and launcher operations, plus checks for an already running agent container.
- Project import through private staging, safe-link handling, hardlink preservation, a second comparison and atomic publication. Debug-log import has separate bounded input handling.

These controls are implemented and inspected by local tests. Their combined enforcement has not been demonstrated on the target host. Test actual connectivity, mounts, identities, profiles and escape resistance before trusting them.

## Residual risk

Docker shares the host kernel. Container isolation is not a VM boundary and does not eliminate kernel or engine vulnerabilities. Offline operation does not prevent destructive edits, malicious outputs, misleading model answers or resource exhaustion inside permitted scope. Prompt injection can still influence what the agent does within that scope.

The installer needs internet access for dependency acquisition. Pinned source inputs do not make every OS package or build output reproducible. An internal checksum manifest detects changes relative to that manifest; it is not a signed publisher identity.

Windows acceptance requires a separate clean VM. Debug-log provenance is still incomplete: bind a returned log to the exact artifact hash, build identity and source generation before treating it as end-to-end proof.

## Handling findings

Use disposable copies of projects and an isolated test host. Preserve a minimal reproduction and classify its evidence level. For sensitive findings, contact the maintainer through the GitHub profile before posting exploit details or private evidence publicly. Never include credentials in reports.
