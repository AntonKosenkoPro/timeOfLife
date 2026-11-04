## Purpose

Produce repeatable App Store screenshot evidence efficiently under limited macOS runner capacity, without sacrificing native rendering, session isolation, or truthful capture and approval status.

## ADDED Requirements

### Requirement: Capture work is scheduled by device

The workflow SHALL create exactly one capture worker per selected supported device, process the selected locales sequentially in the requested order on that worker, and run at most five capture workers concurrently. A worker SHALL use only its own simulator and SHALL reuse that simulator and app installation across its locales and passes. The workflow MUST validate non-empty, unique device and locale selections against supported catalogs before expensive macOS work, without evaluating input values as executable source. Its build, capture, and packaging stages SHALL share the five-macOS-job ceiling rather than treat each stage as having a separate quota.

#### Scenario: Default matrix uses three device workers
- **WHEN** the operator selects `iphone69`, `iphone63`, and `ipad13` with all five locales
- **THEN** three workers each process five locales and two passes per locale without creating separate locale jobs
- **AND** each worker creates, boots, installs on, and eventually deletes only its own simulator

#### Scenario: More devices or less capacity are available
- **WHEN** the supported device catalog grows beyond five entries or fewer runner slots are available
- **THEN** device workers queue without exceeding the concurrency limit or duplicating work for a device
- **AND** the timing report records the actual delays and workload rather than promising the default workload's runtime

#### Scenario: Unsupported or duplicate input is rejected
- **WHEN** a device or locale selection is empty, unsupported, duplicated, or malformed
- **THEN** the workflow rejects the selection before building or booting a simulator

#### Scenario: Build and packaging use the same constrained runner pool
- **WHEN** a default run executes its build, device workers, and packaging stage
- **THEN** those stages respect their dependencies and the shared macOS capacity ceiling
- **AND** waiting for a slot in any stage contributes to the end-to-end timing report

### Requirement: Workers consume one verified Screenshot build

All workers in a run SHALL consume the same simulator-only, Release-optimized Screenshot build for the selected commit, configuration, toolchain, and simulator architecture. Build transfer MUST preserve executable permissions and embedded resources, including the Live Activity extension. Workers MUST reject incompatible or mismatched provenance. A cache miss SHALL rebuild correctly rather than substitute a stale artifact or silently skip work.

#### Scenario: One binary serves all devices and locales
- **WHEN** a default run builds the Screenshot artifact for the arm64 simulator fleet
- **THEN** every worker records the same app and extension binary hashes and source commit
- **AND** no worker rebuilds the app for a locale or pass

#### Scenario: Artifact or toolchain does not match
- **WHEN** the received artifact has a mismatched digest, source commit, configuration, architecture, or toolchain
- **THEN** that worker fails before installing or exporting screenshots and records the mismatch

### Requirement: App screens share a fresh locale-pass session

For each device-locale pair, the runner SHALL execute r1 and then r2 as independent fresh passes. Each pass SHALL have a stable device-locale-pass run identity and distinct fresh session identities for its pinned and real-time clock domains. Each pass SHALL capture Track running, Insights, History top, and Add entry in order within one pinned-clock app session, clean that session, and then execute the real-time session. The session SHALL seed its isolated fixture once, preserve its declared locale/calendar/timezone and fixture identity, and reset navigation, search, selection, and sheet state for each requested frame. Entering Add entry MUST NOT commit an entry or alter the fixture totals. Changing locale, starting the second pass, or switching between pinned and real-time clock domains MUST start a fresh process and isolated session.

#### Scenario: Four frames reuse one fixture without state leakage
- **WHEN** a fresh pinned-clock pass advances through the four app frames
- **THEN** each frame shows the native requested surface with its declared inputs and independently checked totals
- **AND** the fixture entry count and committed contents remain unchanged throughout the pass

#### Scenario: Another locale or pass begins
- **WHEN** the runner finishes one locale-pass session and starts a different locale or the second pass
- **THEN** the previous session is cleaned before a new process and freshly seeded fixture begin
- **AND** no localization, navigation, draft-form edits, or fixture state carries over

### Requirement: Every frame command is bound to the active session

Frame transitions SHALL be ordered and bound to the run identity, active fresh session identity, monotonically increasing command sequence, exact request hash, frame, clock mode, and immutable session inputs. Only one frame transition SHALL be in flight. A stale acknowledgement MUST NOT authorize an export. Invalid, explicitly resubmitted, out-of-order, cross-session, or session-input-changing commands and unsupported command/state formats MUST fail closed without exporting a frame or falling back to defaults. Re-observing an unchanged already-consumed command SHALL be a no-op, not a new transition or a session failure; this is distinct from explicitly publishing that command again.

#### Scenario: An old ready acknowledgement is present
- **WHEN** a new frame command is issued while an acknowledgement for an earlier command remains on disk
- **THEN** no screenshot is exported until readiness matches the new session, sequence, frame, mode, and exact request hash

#### Scenario: A command tries to change the locale or clock mode
- **WHEN** an active pinned session receives a command for a different locale, fixture identity, or clock domain
- **THEN** the command is rejected explicitly and its requested frame remains uncaptured

#### Scenario: Duplicate or cancelled work is replayed
- **WHEN** a previously accepted command is replayed or a command targets an ended session
- **THEN** the runner cannot treat a prior acknowledgement as fresh evidence or advance the session

#### Scenario: An unchanged command is observed again
- **WHEN** the active session observes the same already-consumed command without a new publication
- **THEN** it neither re-executes the transition nor invalidates the session

#### Scenario: Another domain's command or an unsupported format is supplied
- **WHEN** a command targets another session within the same pass or uses an unsupported command/state format
- **THEN** it fails explicitly without silently upgrading, resetting to defaults, or exporting a frame

### Requirement: Session reuse preserves native per-frame validation

Before each export, the workflow MUST verify the current frame's request-bound state, expected fixture totals, native view mounting, and settled presentation. It SHALL capture at native device geometry, hash the resulting PNG, and record frame and build provenance. Faster execution MUST NOT replace native rendering with headless totals, cached readiness, stretched images, or automatically approved pixel variance. Existing timer tolerances and failure deadlines SHALL NOT be reduced to meet the runtime target.

#### Scenario: State is ready but the requested surface is not mounted
- **WHEN** valid fixture data exists but the current requested surface has not mounted and settled
- **THEN** the frame is not exported as successful and a bounded readiness failure remains visible

#### Scenario: Captured geometry or totals are wrong
- **WHEN** exported dimensions differ from the selected native geometry or frame totals differ from the locale's independent pins
- **THEN** the frame fails validation and cannot contribute to a complete set

### Requirement: Two-pass comparison preserves semantic inputs

The runner SHALL compare both passes using frame-level semantic input identities, expected contents, and totals independently of volatile run/session identifiers and command counters. A change to locale, fixture, treatment, reference clock, frame, or geometry MUST remain detectable. Pixel variance SHALL remain reviewable evidence rather than be silently auto-approved or substituted for semantic validation.

#### Scenario: Fresh session identifiers differ between passes
- **WHEN** both passes use fresh session identities but identical semantic frame inputs and expected contents/totals
- **THEN** the semantic comparison recognizes the same intended frame without requiring matching volatile identifiers or byte-identical screenshots

#### Scenario: A meaningful input changes between passes
- **WHEN** a locale, fixture, treatment, clock, frame, geometry, or expected content/total differs
- **THEN** two-pass validation rejects the mismatch even if volatile identifiers were excluded from comparison

### Requirement: Live Activity evidence retains its clock and availability semantics

Live Activity work SHALL use a separate real-time session with one activity identity and start anchor shared by that pass's applicable Lock Screen and Island states. Genuine frames MUST retain screenshot-hash-bound numeric timer validation within the existing two-second tolerance. When the capture environment cannot produce genuine system pixels, the workflow SHALL retain an explicit pending or blocked reason and SHALL NOT mark the set complete or approved. On a device without a Dynamic Island, those states SHALL be recorded as not applicable with a capability probe; the Lock Screen state remains required.

#### Scenario: Three genuine system states are supplied
- **WHEN** Lock Screen, compact Island, and expanded Island evidence is registered for one iPhone pass
- **THEN** all three frames bind to the same real activity anchor and pass their own numeric and geometry checks
- **AND** the real-time session does not reuse the pinned-clock app session

#### Scenario: CI cannot provide genuine system surfaces
- **WHEN** a CI worker can export only app-surface or placeholder pixels for a Live Activity state
- **THEN** that state and the enclosing set remain explicitly pending or blocked
- **AND** a successful job or fast ZIP creation does not promote them to genuine, complete, or approved evidence

#### Scenario: iPad Island states are unavailable
- **WHEN** the device capability probe confirms that no Dynamic Island exists
- **THEN** compact and expanded Island states are recorded as not applicable without fabricated screenshots
- **AND** the real-time session still runs for required Lock Screen evidence, retaining its own captured or pending status, without separate Island frame sessions

### Requirement: Session cleanup gates every dependent frame

The runner SHALL hold exclusive device ownership for each capture session, snapshot clean chrome before changing it, and restore the exact owned settings on every exit path. Cleanup SHALL be scoped to the session's fixture store, preferences, files, and activity identity. Its success, mismatch, or failure receipt MUST bind the run/session identities, accepted final command, and covered command transcript, combining app cleanup with runner-verified chrome restoration, process termination, and ownership release. App cleanup alone MUST NOT attest to host-side restoration. A failed, mismatched, incomplete, or missing cleanup receipt SHALL prevent every frame depending on that session from being finalized as complete. Partial artifacts and diagnostics SHALL remain available after failure, and work on later locales SHALL NOT proceed on a contaminated simulator.

#### Scenario: A later frame fails after earlier frames were exported
- **WHEN** a session fails or is cancelled partway through its story
- **THEN** cleanup and chrome restoration are attempted for that owned session
- **AND** the earlier PNGs remain available with their session dependency and failure status
- **AND** no dependent frame becomes complete without a verified cleanup receipt

#### Scenario: Existing overrides or an ownership mismatch are detected
- **WHEN** the worker encounters preexisting chrome overrides or a cleanup request for another session
- **THEN** it fails closed without clearing another session's settings or deleting unrelated simulator data

#### Scenario: Cleanup covers a different command transcript
- **WHEN** an app cleanup acknowledgement exists but its session/transcript differs from the exported frames or runner restoration is missing
- **THEN** the combined receipt cannot finalize any uncovered frame as complete

### Requirement: Capture optimization remains isolated from the shipping app

Session transport and fixture orchestration MUST remain available only in the simulator-only Screenshot configuration, with production accounts, Keychain, App Group data, and network synchronization inaccessible. Fixture mutations SHALL continue through the existing storage mutation boundary and normal schema initialization. Ordinary Debug/Release behavior and device/archive guards SHALL remain unchanged.

#### Scenario: Capture commands reach a shipping build
- **WHEN** ordinary Release receives capture launch arguments or session files
- **THEN** they cannot activate fixture orchestration or bypass the normal sign-in gate

#### Scenario: A capture session initializes its store
- **WHEN** a fresh locale-pass session is created
- **THEN** it uses a distinct fixture store initialized through the normal schema path
- **AND** it cannot mutate production storage or activate network synchronization

### Requirement: Per-locale artifacts and evidence status survive worker batching

The workflow SHALL retain independent artifacts for every attempted device-locale pair, including both passes, frame records, session cleanup receipts, timings, and failures. The packaging stage SHALL preserve the selected matrix, locale/device paths, exact runtime/build provenance, and captured-versus-approved distinctions in the ZIP manifest and README. It MUST distinguish a CI handoff/debug bundle with missing evidence from a complete App Store panel bundle; empty or blocked panel cells MUST NOT be hidden by a green packaging job.

#### Scenario: One locale fails on a device worker
- **WHEN** one locale fails but earlier locale captures exist
- **THEN** those earlier artifacts remain downloadable independently and failed or unattempted pairs are listed explicitly
- **AND** packaging records missing cells instead of claiming a full matrix

### Requirement: Runtime claims are supported by complete timing evidence

The optimization SHALL target less than 1,200 seconds from dispatch to final CI ZIP availability for the current default three-device, five-locale, two-pass workload. The acceptance capacity SHALL be declared as availability for one build job, then three overlapping device workers, then one packaging job, within the shared account ceiling; actual overlap and queueing MUST be reported. Acceptance MUST include a cold-cache full run and a warm-cache full run of the same implementation, with all selected work attempted and artifact/evidence status disclosed. Reports SHALL include queueing for every stage, build/cache, runtime download if any, boot/install, per-session and per-frame phases, packaging, observed concurrency, and known competing jobs (or an explicit unknown); queue/download time MUST NOT be subtracted from an end-to-end claim. Human evidence/approval time SHALL be identified separately, not presented as automated completion. Cache misses, reduced capacity, or expanded device matrices MUST NOT silently narrow the workload to meet the target.

#### Scenario: Cold and warm default runs meet the target
- **WHEN** full cold-cache and warm-cache default runs each make their final CI ZIP available in less than 1,200 seconds
- **THEN** the report includes both run URLs, exact commit/toolchain, cache status, capacity, all phase timings, and missing-evidence status
- **AND** only the measured CI runtime target is marked achieved, without granting screenshot or panel approval

#### Scenario: Queueing or execution exceeds the target
- **WHEN** the end-to-end elapsed time reaches or exceeds 1,200 seconds
- **THEN** the runtime target is reported as unmet with the queue and execution breakdown
- **AND** no frames, locales, passes, cleanup checks, or evidence requirements are dropped to produce a passing claim
