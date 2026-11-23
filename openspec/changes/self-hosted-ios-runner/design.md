## Context

See `proposal.md` for motivation and scope. Public Lifio currently runs the iOS lane and panels tests on `macos-15`; Ubuntu jobs perform path detection and always-reporting gates. Cloud remains signed-tag archive/upload only. No self-hosted runner, Tart installation, or image exists on the laptop.

Read-only host observations during planning: arm64, 10 logical CPUs, 32 GiB RAM (34.36 decimal GB), approximately 162 GiB available, macOS 27.2.1, Xcode 27.2 (27B52). These observations are not a capacity guarantee or VM test result.

This is CI tooling, so specs are deliberately skipped. Common S1/S3/S5/S6 remain the quality constraints; mandatory public checks remain authoritative. The stale active Cloud-migration change is noted in the proposal, not edited or archived here.

## Goals / Non-Goals

**Goals:** reproducible image inputs, one clean VM per GitHub job, bounded owner-operated lifecycle, tested separation from laptop data/network, full iOS verification, and honest pilot evidence.

**Non-Goals:** production CI replacement, arbitrary/untrusted PR execution, cross-job mutable cache reuse, release signing, screenshot capture, and any claim of escape-proof isolation.

## Decisions

### 1. Private control plane; manual pilot rather than public runner routing

The owner approved a private pilot repository during planning. Suggested name: `AntonKosenkoPro/lifio-runner-pilot` (availability and setup verified later). Register runners there only; it has no public forks, external collaborators, PR-triggered workflows, deploy environments, or production secrets. Verify repository visibility and access before each session; refuse a public repository or unexpected authorized actor.

Store the reviewed workflow template as `infra/self-hosted-runner/pilot-workflow.yml` in Lifio, **outside `.github/workflows/`**. An explicitly approved setup copies a pinned template revision to the private repository's protected default branch. Record template commit/hash and reject drift.

Owner-only `workflow_dispatch` on that trusted control branch accepts a full 40-hex Lifio SHA and a unique session runner label. The owner reviews the target SHA before dispatch. Hosted preflight resolves the SHA in the fixed public Lifio repository, validates inputs as data (never shell interpolation), and logs control revision/target SHA. Guest checkout must verify `HEAD` equals the requested SHA with persisted Git credentials disabled. Never accept an arbitrary source repository or automatically execute PR heads.

The host driver is invoked for an explicit private workflow run ID. It verifies repository, workflow identity/revision, actor, event, target SHA, queue state, and labels before registration. Unique labels prevent accidental assignment, **not** malicious-workflow authorization. Private repository access is the scheduling boundary; do not register an equivalent runner in public Lifio or advertise generic public-runner availability.

Alternative rejected: modifying public `ios.yml` with a label or job `if:` guard. PRs can alter workflows; labels alone are not a security boundary. Hosted gates and public rulesets remain byte-for-byte unchanged. Pilot evidence links back to the reviewed PR/SHA but cannot satisfy its required checks.

### 2. Stopped golden image plus ordinary APFS clones

Use ordinary `tart clone` from a stopped, validated image; no resumed RAM snapshots, experimental stacked disks, or long-lived guest. APFS copy-on-write reduces initial clone cost but does not bound later disk growth. Never promote a job-used clone to the base.

Versioned `infra/self-hosted-runner/` contains the image recipe, lock manifest, host driver, guest checks, private workflow template, and tests. Start from an owner-approved Apple IPSW with recorded OS/build and SHA-256; document any required first-boot UI/license steps rather than claiming fully unattended restoration. Install a lawfully obtained, hash-verified Xcode archive via an explicit owner-provided path; no Apple ID session, iCloud, personal Keychain, or signing identity in the image.

Initial targets: guest macOS 27.2.1, Xcode **27.2 (27B52)**, iOS **27.0** simulator runtime, Tart **2.42.0**, Softnet **0.26.0**, runner **2.338.2** (`osx-arm64`). OS/runtime availability and compatibility must pass the image smoke gate; any necessary pin change is reviewed and recorded before publishing the lock. These are pilot pins, not changes to the public hosted image or local capture pipeline.

Keep XcodeGen **2.46.0** and SwiftLint **0.65.1**, deriving versions from the existing Cloud scripts and comparing release SHA-256 values with `ios.yml`. Preserve XcodeGen's `share/xcodegen` presets and explicit `/usr/local/bin` precedence. The lock also records actual Python, `xcpretty`, Pillow **13.0.0**, runtime identifiers/builds, and source/archive digests. Resolve missing exact auxiliary-tool pins during image preparation; no floating `latest` in a ready image.

Runner archive metadata currently reports SHA-256 `25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388`; re-download/verify before use, not merely trust this proposal. All other archive digests are populated and verified during implementation. Record image identity + recipe revision after a successful build.

Start with 6 vCPUs / 16 GiB guest RAM, max one active clone, and a configurable **40 GiB host free-space reserve**. Preflight estimates base + installation scratch + clone growth and refuses over-budget work; the earlier informal 70 GB estimate is not a guarantee. Use a dedicated `TART_HOME`, disable automatic pruning, and touch only owned image/run IDs. Image rebuilds never overwrite the working base before replacement validation.

Only clean OS/tool/runtime contents persist. No host-shared DerivedData/SPM caches, source workspace, credentials, or job-created files persist between jobs. Optimize cache strategy only after clean-run measurements.

Alternative rejected: persistent VM or writable shared cache (state leakage); pulling a mutable prebuilt `latest` image (unreviewable drift).

### 3. Prove the boundary before introducing credentials

Run the host driver as a dedicated local CI account with its own login Keychain and home directory, not the developer's normal account. Installation, any privileged Softnet helper configuration, license acceptance, and CI-account creation require explicit owner approval; never grant blanket passwordless host sudo.

Use pinned Softnet with explicit policy, not default NAT or bridged networking. Deny guest-initiated host, gateway-service, LAN, link-local/metadata, VPN/private-network, and other-VM connections while allowing necessary public GitHub/package/Apple traffic and essential DHCP/DNS. Disable or block IPv6 bypass. Softnet documentation and Tart FAQ differ on gateway reachability: **do not assume `--net-softnet` alone is sufficient**.

Before JIT registration, use a credential-free clone to test blocked canary services on the host and a controlled LAN peer, IPv4/IPv6 behavior, and successful public HTTPS/DNS. Confirm host-initiated SSH bootstrap/diagnostic return traffic works without opening guest-initiated host sessions. Revalidate on network/VPN changes; unknown policy, unavailable canary, or failed isolation blocks registration. Never silently fall back to NAT.

No `--dir` host mounts, additional host disks, clipboard sharing (`--no-clipboard`), audio/USB passthrough, host SSH agent, Docker socket, or personal environment forwarding. SSH keys are CI-specific, host-key verification is scoped to the owned clone, and management credentials never enter the guest. Test with guest administrator privileges: guest firewalls alone are not the boundary.

The iOS Simulator is not a Linux nested VM: do **not** enable Tart's Linux-only `--nested` on the assumption that Simulator requires it. Validate simulator boot, framework/Metal availability, and actual XCTest execution inside this macOS guest. A successful macOS boot alone proves no iOS compatibility.

Alternative rejected: treating NAT or a guest-side deny rule as host isolation.

### 4. Host-controlled, single-job JIT lifecycle

Use a host-only credential restricted to the private pilot repository (fine-grained token, Administration write for runner management and Actions read for run/job inspection; verify endpoint permissions at setup). Store in the CI account's Keychain, retrieve without echoing, and never inherit the developer's broad `gh` session. Workflow dispatch remains an owner action. No management token in git, VM images, Actions secrets, command logs, or guest environment.

The host calls repository `generate-jitconfig` with a unique runner name, verified runner-group ID (not an assumed `1`), work folder, and exact labels. The guest receives only the short-lived encoded JIT configuration over the private bootstrap channel and executes `run.sh --jitconfig ...`. Avoid trace logging; never write JIT material to durable host files. Assert actual JIT one-job behavior; no persistent runner service.

Lifecycle, with an atomic host lock:

1. Validate trusted run metadata, complete lock/image manifest, free space, network policy, and no owned unresolved prior run; acquire single-run lock.
2. Journal owned VM name, run/attempt ID, and later runner ID (never credentials); clone and boot with bounded waits.
3. Validate guest image/tool versions and network canaries before requesting JIT config. Start runner, record actual job assignment, reject unexpected identity, and monitor private run/job state.
4. On success, failure, cancellation, bootstrap/SSH failure, timeout, or signal: preserve bounded diagnostics where possible, stop the owned VM, delete its disk/state, remove stale registration if present, and verify absence.
5. On process kill/reboot, next invocation reconciles the journal and refuses new work until owned leftovers are cleaned. Cleanup errors fail loudly; never report successful teardown on a failed delete.

Set separate configurable limits for boot/SSH (initially 5 minutes), idle assignment (10 minutes), and total session (75 minutes); the private guest job has a 60-minute execution timeout. Host deadlines include queue/cancel handling that GitHub job timeout does not cover. Laptop sleep/offline yields a failed or cancelled **pilot**, never a blocked public PR gate. No persistent daemon or launchd registration in the pilot.

At most one pilot VM/job runs at a time; all build/test invocations inside it are serial. Coordinate with local iOS verification under the repo's one-`xcodebuild` policy rather than using the guest as an excuse to oversubscribe the laptop. Keep host awake only for the active session; no global power-setting changes.

### 5. Full verification in one disposable guest job

Run the same quality bar as `ios.yml`, against the explicit checkout SHA:

- Verify all pinned tool versions and archive provenance; fail before project generation on mismatch.
- `xcodegen generate`, `swiftlint lint --strict`, release stamp harness, unsigned Debug build, Debug tests, Screenshot build, Screenshot tests.
- Dedicated guest simulator selected/created using the pinned available runtime; boot and address by UDID. Explicit guest-only DerivedData and serial invocations; no global warnings-as-errors overrides that conflict with GRDB.
- Panels Python suites using Pillow 13.0.0 and `/System/Library/Fonts/Helvetica.ttc`; record guest font/OS identity. Also run stdlib tooling suites and deny-screenshot-install tests for cross-script parity.

The manual pilot runs both configurations and script suites unconditionally, intentionally exceeding public path-filter coverage. Compare the applicable public checks on the **same SHA**, recording hosted/pilot Xcode, runtime, architecture, and font differences; this is quality-bar parity, not identical binaries or timings.

Do not change public workflow commands just to share implementation. Keep a tested mapping from guest checks to the current hosted steps, including stamp history/tag requirements; clone with required history/tags. Control/template revisions and guest-check script source are pinned/reviewed; PR-controlled text must never execute on the host.

Archive redacted lifecycle records and runner diagnostics outside the doomed VM before normal teardown (restricted CI-owned storage, default 7-day retention and size cap); mark lost logs honestly on hard crash. Use fixed diagnostic paths, bounded copies, and no symlink traversal/untrusted archive extraction on host. Publish only sanitized text summaries/run links; keep binaries/xcresults/images outside git. Guest logs never authorize cleanup or declare a successful job.

## Risks / Trade-offs

- [Public repository scheduling attack] → Private pilot registration only; owner-only access and trusted control revision verified; labels/`if:` are not authorization.
- [VM escape or exposed host service] → Dedicated CI account, no sharing, explicit tested network isolation, patched host/Tart; residual hypervisor/helper risk remains.
- [Softnet privilege/policy or SSH-return incompatibility] → Credential-free boundary test first; stop rather than weaken isolation.
- [RAM/disk/thermal contention] → One job, adjustable 6-CPU/16-GiB start, reserve checks, measure build peak; no promised speedup.
- [Fresh clone cold-build cost] → Measure clean runs first; immutable tool image only. No cross-job mutable caches in this pilot.
- [Tool/OS drift or runner expiry] → Complete lock + startup assertions, reviewed rebuilds, current runner deprecation/security checks before provisioning; no indefinite frozen runner.
- [Interrupted cleanup or stale registration] → Owned-resource journal, idempotent reconciliation, stop-on-cleanup-error; never broad `rm`, `pkill`, simulator shutdown, or Tart cache pruning.
- [Licensing/install access] → Owner confirms applicable Apple macOS/Xcode agreements and pinned Tart/Softnet terms before install; no redistribution of Apple images or assumption that a public release grants redistribution rights.
- [Pilot repository overhead] → One private workflow template, explicit sync/hash check; no second product repo or required checks. Future production routing is a separate decision.

## Migration Plan

1. After human proposal approval, implement versioned tooling/tests/docs in this worktree; refresh current external docs and rebase first. Do not change public workflows.
2. Obtain explicit owner setup approval, create/confirm the private repository and CI account, configure narrowly scoped host credentials, verify license/access boundaries, install pinned tools, and build the image within measured capacity.
3. Pass credential-free network + simulator smoke gates, then provision one JIT runner for an owner-approved dispatch. Run two consecutive full green pilots on the same reviewed SHA, each with a new clone/registration.
4. Prove marker absence outside the workspace in the second clone, unchanged base, host-canary rejection, pin-drift rejection, cancellation/timeout recovery, and clean registrations/disks after teardown. Compare with actual hosted evidence on that SHA and record timing/peak storage/memory.
5. Document remaining limitations and owner decision to retain or stop the advisory pilot. A green pilot never automatically switches required checks.

Rollback: stop/reconcile the owned session, revoke the private management credential, disable/remove the private workflow/runner configuration, and remove only explicitly approved owned images. Hosted CI and Cloud require no rollback because they were never switched.

## Research and Evidence Limits

Fetched 2026-11-23. Exactly three Context7 commands: resolve `Tart` using query `ephemeral macOS virtual machines GitHub Actions runners on Apple Silicon using Tart clone isolation networking`; select `/openai/tart` (official repository, high-reputation result); then:

- Topic/lifecycle query: `Ephemeral GitHub Actions runners using a fresh macOS VM clone for each job with Tart: VM isolation, networking, cleanup, licensing, and running iOS Simulators`.
- Related isolation/resource query: `macOS guest iOS Simulator Metal graphics support Tart VM resource sizing golden image APFS clones shared folders network isolation --net-softnet --net-softnet-block`.

Results establish APFS clones, CLI resource controls, explicit host sharing, Softnet IPv4 policy options, and paravirtualized Mac graphics, not a working Lifio runner.

Primary references also fetched directly (not inferred from training):

- [Tart quick start](https://github.com/openai/tart/blob/main/docs/quick-start.md), [FAQ](https://github.com/openai/tart/blob/main/docs/faq.md), [run implementation](https://github.com/openai/tart/blob/main/Sources/tart/Commands/Run.swift), [license](https://github.com/openai/tart/blob/main/LICENSE): IPSW/manual setup, NAT host reachability, Keychain requirement, flags, and license conditions. Reconfirm behavior against pinned 2.42.0 before implementation; `main` can contain unreleased behavior.
- [Softnet README](https://github.com/openai/softnet/blob/main/README.md): gateway exception, privileged setup, filtering; reconfirm against pinned 0.26.0, especially SSH return traffic and IPv6.
- [GitHub self-hosted reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners): one-job ephemerality, queue behavior, outbound access, log retention and software updates.
- [GitHub runner REST API](https://docs.github.com/en/rest/actions/self-hosted-runners): repository JIT endpoint, labels/group/work-folder fields, encoded config and registration management. Current docs specify API version `2026-03-10`; confirm supported API/permissions during setup.
- [GitHub secure use](https://docs.github.com/en/actions/reference/security/secure-use): public-repo warning, JIT one-job semantics, privileged-trigger hazards; primary justification for private control plane.
- GitHub release APIs returned [Tart 2.42.0](https://github.com/openai/tart/releases/tag/2.42.0), [Softnet 0.26.0](https://github.com/openai/softnet/releases/tag/0.26.0), [runner 2.338.2](https://github.com/actions/runner/releases/tag/v2.338.2) and runner asset digest. These are observed metadata, not installed/verified executables.
- [Apple SLA index](https://www.apple.com/legal/sla/): applicable installed-product agreements must be reviewed by owner; index alone is not a virtualization-license conclusion.

HIG waiver: no UI/design changes. Native Apple API documentation waiver: tooling invokes Tart/Xcode CLIs; no Swift/Virtualization SDK code is introduced, so applicable framework limitations are researched through Tart's implementation/FAQ, with real simulator smoke required. Additional GitHub/Apple Context7 resolves waived to respect the three-command limit; current primary documentation was fetched directly instead. Reconfirm external behavior at apply time.
