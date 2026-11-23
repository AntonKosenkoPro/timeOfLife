## 1. Reconfirm Research and Prerequisites

- [ ] 1.1 Refresh the research bundle before implementation: Tart lifecycle/isolation topic and GitHub JIT best practices via Context7 within command limits, primary-source verification against pinned releases, and explicit HIG/native-Apple-API waivers; update design citations and verify current runner support/deprecation.
- [ ] 1.2 Rebase this worktree onto fresh `origin/main`; recheck Common S1/S3/S5/S6 and unchanged app/API/Cloud scope, and record that stale `migrate-ios-ci-to-xcode-cloud` deletion tasks are not part of this change.
- [ ] 1.3 Obtain explicit owner approval for external setup (private repository, dedicated local CI account, credential permissions, Tart/Softnet/helper installation, and image storage); confirm applicable Apple/Tart/Softnet licensing and available capacity before any such action.

## 2. Versioned Image and Credential-Free Feasibility

- [ ] 2.1 Add `infra/self-hosted-runner/` image recipe and fail-closed lock schema covering OS/IPSW, Xcode build/archive, simulator runtime/build, Tart, Softnet, arm64 runner, Python, xcpretty, Pillow, and all downloaded artifact digests; reuse existing XcodeGen/SwiftLint pin and digest sources without altering public workflows.
- [ ] 2.2 Implement bounded, owned-resource image preparation with owner-provided Apple inputs, documented first-boot/license steps, isolated `TART_HOME`, automatic pruning disabled, and free-space reserve checks; no floating ready-image inputs or personal account/signing material.
- [ ] 2.3 Implement explicit Softnet network policy and no-sharing boot configuration; prove guest-admin host/gateway/LAN/link-local/VPN/IPv6 rejection with controlled canaries, working public HTTPS/DNS, and host-initiated SSH return traffic before runner credentials are introduced. Stop if the pinned tools cannot provide this boundary.
- [ ] 2.4 Build and validate the stopped golden image: exact version assertions, no identities/credentials/workspace residue, available pinned simulator, real serial unsigned build/test smoke, and font/Pillow availability; record image identity, resource use, and complete lock only after success.

## 3. Private Manual Pilot Workflow

- [ ] 3.1 Add the private workflow template outside public `.github/workflows/`, with owner-only manual dispatch on a trusted control revision, fixed Lifio source repository, validated immutable SHA/session-label inputs, read-only job token, and no production secrets/PR triggers.
- [ ] 3.2 Add hosted preflight plus guest checkout verification for requested SHA, full history/tags, trusted control/template version, and disabled credential persistence; distinguish actual hosted checkout SHA from PR head/merge SHA when collecting paired evidence.
- [ ] 3.3 Add serial guest verification covering pin assertions, project generation, strict lint, stamp harness, full Debug and Screenshot builds/tests by owned simulator UDID, panels, tooling suites, and deny-install tests; preserve per-target warnings-as-errors and unsigned configuration.
- [ ] 3.4 Add parity/contract tests mapping guest commands to current hosted quality gates and checks that public `ios.yml`, filters, gate/ruleset names, Cloud scripts, backend workflows, and product files are untouched.
- [ ] 3.5 After setup approval, create or confirm the owner-only private pilot repository, install the pinned reviewed template on its trusted default branch, and verify visibility/access/workflow hash before use; do not register any runner in public Lifio.

## 4. Single-Job Host Lifecycle

- [ ] 4.1 Implement host-only private-repository credential lookup from the dedicated CI Keychain with verified API permissions, no broad developer `gh` inheritance, secret-safe bootstrap, explicit run-ID metadata checks, and fail-closed visibility/actor/control-revision validation.
- [ ] 4.2 Implement atomic single-session lock, resource journal, stopped-base clone, bounded boot/SSH and isolation preflight, repository JIT config generation, and one-job runner start with unique names/labels and validated group ID.
- [ ] 4.3 Implement host monitoring for assignment, success/failure/cancellation, idle/session deadlines, network changes, and signals; capture bounded sanitized diagnostics without host mounts, symlink traversal, untrusted archive extraction, or guest-controlled cleanup authority.
- [ ] 4.4 Implement idempotent owned-resource teardown and next-start reconciliation for kill/reboot: stop/delete clone state, remove stale runner registration, verify absence, and reject new work on cleanup failure; never prune unrelated VMs, simulators, files, or other sessions.

## 5. Automated Failure and Safety Tests

- [ ] 5.1 Add fake Tart/SSH/GitHub tests for lifecycle order and exactly-one-job registration, secret redaction, immutable input handling, wrong/public repository, untrusted actor/workflow/control revision, unexpected assignment, and missing permission failures.
- [ ] 5.2 Add failure-injection tests for clone/boot/JIT/SSH failure, pin or digest drift, low disk, network-policy failure/change, idle/session timeout, cancellation/signals, stale registration, cleanup failure, and journal recovery; prove no fallback to unsafe NAT.
- [ ] 5.3 Add filesystem/diagnostic safety tests for unowned resources, path injection/symlinks, log size/retention, base mutation, and cross-run sentinel residue; verify no credential-bearing data enters image locks, journals, git, or public summaries.
- [ ] 5.4 Run new script tests and applicable shell/Python/YAML lint checks; exercise deliberately broken guest checks to prove failure is reported rather than a green pilot.

## 6. Live Pilot Acceptance

- [ ] 6.1 With owner-approved setup and reviewed SHA, run two consecutive complete green private dispatches on new VM clones/JIT registrations; record private run IDs, Lifio checkout SHA, template/image IDs, all suite results, and cleanup receipts.
- [ ] 6.2 Prove a sentinel written outside job A's workspace is absent in job B, the stopped base is unchanged, guest host/LAN canaries fail as intended, no host mount/credential/signing identity is exposed, and both run registrations/disks are removed.
- [ ] 6.3 Exercise live cancellation and an injected bounded timeout/driver interruption, reconcile only owned resources, and prove the next session can run cleanly; label hard-crash missing diagnostics honestly.
- [ ] 6.4 Pair results with actual GitHub-hosted checks on the same checkout SHA; record tool/runtime/architecture/font differences, cold VM boot/build/test/teardown time, peak disk/RAM, and availability limits without asserting unmeasured savings or replacing required checks.

## 7. Documentation and Handoff

- [ ] 7.1 Update `docs/ci.md` and a focused host runbook for private-repo setup, CI account/Keychain/helper approvals, image pins/rebuilds, dispatch/review flow, lifecycle deadlines, offline/cancel recovery, diagnostic retention, and owned-resource rollback.
- [ ] 7.2 Add concise pilot pointers to `README.md` and `docs/project-context.md`; explicitly retain hosted required checks, local-only screenshot capture, Cloud-only signed archives, and unchanged OpenAPI/design/locales.
- [ ] 7.3 Run backend verification and iOS verification on separate parallel agents per repo policy, serialize all Xcode/simulator work with the pilot, and run the new tooling checks; record actual results and any owner-blocked live acceptance instead of ticking unperformed tasks.
- [ ] 7.4 Rebase again before PR handoff, rerun affected validation, run `openspec validate --all --strict`, and update this same proposal PR with evidence and truthful checklists; stop for human review, with no automatic production switch, merge, or archive.
