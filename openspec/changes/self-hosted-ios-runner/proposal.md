## Why

Lifio's iOS PR checks consume GitHub-hosted macOS capacity while this Apple-Silicon laptop could run them in disposable macOS VMs. An opt-in pilot will establish isolation, correctness, resource use, and timings before considering any migration of required checks.

## What Changes

- Add a versioned Tart image recipe and a single-job host lifecycle driver under `infra/self-hosted-runner/`: clean stopped image → disposable clone → repository-scoped JIT runner → one job → diagnostics → destruction.
- Register runners **only in a private, owner-controlled pilot repository**, not public `AntonKosenkoPro/timeOfLife`. The owner approved this boundary during planning; creating/configuring that repository requires a later explicit setup action.
- Supply a versioned workflow template for that private repository. Owner-only manual dispatch selects a reviewed, immutable Lifio commit SHA; a single guest job runs the unsigned Debug and Screenshot builds/tests, stamp harness, and panels tests.
- Require tested host/LAN network isolation, no host mounts/clipboard/SSH-agent forwarding, no signing identities, no management credentials in the guest, and clean state between jobs. A VM is risk reduction, not an absolute sandbox guarantee.
- Document setup, exact tool/image pins, credential handling, failure recovery, rollback, and paired hosted/pilot evidence. No performance or cost saving is claimed before measurement.

### Non-goals

- No changes to public `ios.yml`, its filters, `ios-gate`, other required checks, rulesets, or default `macos-15` routing. Pilot results are advisory, not substitute required checks.
- No always-on autoscaler, webhook listener, Kubernetes/ARC, automatic hosted fallback, persistent runner, or shared writable cross-job caches.
- No backend migration/deployment, Xcode Cloud changes, signed builds, production secrets, or App Store screenshot capture in CI. Screenshot **configuration tests** are distinct from screenshot capture.
- No app/API/UI/localization changes, unrelated cleanup, or archival of other active changes.

## Capabilities

### New Capabilities

None — CI tooling only; `.openspec.yaml` declares `skip_specs: true`.

### Modified Capabilities

None — product requirements and baseline specs remain unchanged. `release-versioning` and `observability` are adjacent but unaffected: signed tag archives and dSYM uploads remain in Xcode Cloud.

## Impact

- Intended implementation: `infra/self-hosted-runner/`, `docs/ci.md`, a focused host runbook, and concise pointers in `README.md` / `docs/project-context.md`. Only planning artifacts are added in this proposal PR.
- External systems: local Tart/Softnet installation, macOS image storage, and a separately approved private pilot repository with a host-held, narrowly scoped management credential. No host installation, credential creation, repository creation, or live runner registration occurs during proposal.
- Requirements rechecked: Common S1 (standard tooling), S3 (full test coverage), S5 (verified/reviewable changes), S6 (mandatory PR checks preserved); +2 (iOS deployment floor) is unchanged. Product FURPS rows and S4 deployment topology are unaffected.
- Current `docs/ci.md` and `.github/workflows/ios.yml` are authoritative. Active `migrate-ios-ci-to-xcode-cloud` still proposes deleting `ios.yml`, but was superseded in practice by archived `2026-10-27-keep-gh-ci-cloud-archive`; do not execute its deletion tasks as part of this change. Older archive non-goals excluding self-hosted runners are deliberately revisited only for this advisory pilot.
- Research: Context7 `/openai/tart` (resolved as Tart Virtualization), queries on ephemeral GitHub Actions VM lifecycle and macOS guest resource/network isolation, plus current GitHub runner/JIT/security references. Exact queries, sources, pins, evidence limits, and waivers are recorded in `design.md`.
