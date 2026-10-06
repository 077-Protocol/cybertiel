# Audit notes and evidence

## Method

The audit approach is to turn a suspected boundary failure into a minimal reproduction, check the actual emitted implementation, attempt to falsify the hypothesis, and add both positive and negative regression cases when a defect is established. A source-pattern assertion, a mocked command and a real filesystem test answer different questions; none alone demonstrates a working target installation.

Development used AI assistance. This repository preserves inspectable code and evidence rather than presenting generated audit narratives as an independent professional certification. Publication validation is separate from the earlier audit results.

## Selected cases

**Hardlink identity (CT-BUG-033).** The supplied evidence records that a project copy without rsync `-H` split two linked paths into independent files, while a verifier without `-H` missed the difference. The v25 implementation adds hardlink handling to both copy and verification. `test_run10_regressions.py` contains positive preservation and negative split-tree detection cases. Re-run these with the intended Linux tools; the historical reproduction is not a new run on this workstation.

**Stale trust metadata (CT-BUG-034).** The supplied evidence records that v25-r1 metadata still identified older installer/checker releases. Hashing that metadata did not make its meaning correct. The v25-r2 source binds the current three scripts and identifies the current release/checker. This is a useful distinction between byte integrity and semantic consistency.

**Rejected hypothesis: special files.** Historical FIFO/socket probes reported that import already failed closed. No runtime change was justified by that hypothesis. The selected evidence includes this falsification rather than counting it as an additional fixed bug.

## Publication review

The supplied directory identifies itself as `2026-10-06.v25-r2`. All 173 entries of its manifest matched file hashes, sizes and permissions. Current script bindings matched. The source ZIP was not supplied, so its claimed hash, archive structure and sealed test rerun cannot be independently verified here. No archive hash is advertised as newly verified.

A remaining source error was found: `SOURCE_LOCK.json` contains a 65-character `lineage.parent_checker_sha256`. The source regression had asserted that malformed literal, illustrating how a test can preserve a metadata error. It is not a valid digest and is not accepted as parent authentication. The original lock is preserved byte for byte; correcting it and requalifying a new release is future work. The current checker binding is valid. `lineage.parent_retained` describes the source package context; parent archives are intentionally not part of this curated distribution.

The original `MANIFEST.json` and `SHA256SUMS` cover the larger source package, including omitted history. They are not published as if they described this repository. A new `SHA256SUMS` covers this curated distribution. The local source-verification receipt records the scope of the original checks.

## Reading the evidence

`docs/evidence/RUN11_PRESEAL_TEST_REPORT.json` reports 473/0 historically. Its report names describe the original package layout; not every referenced report or comparison suite is included here. The final sealed report and package-validation report mentioned in the conversation were absent from the supplied directory and are not fabricated.

`SOURCE_VERIFICATION.json` and `PUBLICATION_VALIDATION.json` are fresh receipts from this publication task. They distinguish new checks from source claims. Runtime scripts, paired helper, checker baselines and generated configs remain unchanged. Selected self-contained tests are retained; comparison tests requiring old archives are omitted. Temporary caches, audit session logs, patch dumps and repetitive historical reports are excluded.

## Required target work

Before increasing qualification, collect evidence for:

1. Ubuntu host gates, reboot/patch lifecycle, Docker build and actual security-profile enforcement.
2. Agent egress/host reachability, mounts, runtime identity and concurrent-operation rejection.
3. Real pinned Pi install, CLI/SDK loading and tool-authority behavior.
4. Complete model/projector hashes, inference and sustained CPU/memory behavior at the configured context.
5. A real project build, artifact/source identity and clean Windows-VM execution.
6. Machine-readable linkage between artifact, build, source generation and returned debug log.

This repository claims none of those as completed.
