## MODIFIED Requirements

### Requirement: Quiet health endpoint

Uptime-ping traffic MUST NOT emit per-request telemetry in any signal: no access-log line, no trace span, and no metric increment with per-request labels. A single health-check counter (one monotonic series, no labels beyond service/environment) increments instead.

#### Scenario: ping arrives, no log line

- GIVEN the uptime monitor pings `/health`
- WHEN the request is served 200
- THEN no access-log line is written for it
- AND the health-check counter increments instead.

#### Scenario: ping arrives, no per-request telemetry

- GIVEN the uptime monitor pings `/health`
- WHEN the request is served 200
- THEN no access-log line is written for it
- AND no trace span is exported for it
- AND the health-check counter increments instead.

#### Scenario: health stays out of the cardinality guard

- GIVEN the CI label-allowlist check runs
- WHEN it scans metric/log label keys used by the backend
- THEN `/health` contributes no per-request label set.

## ADDED Requirements

### Requirement: OTel Collector forwarding on the VM

The VM MUST run an OpenTelemetry Collector that receives OTLP from the backend (and later iOS telemetry) and forwards to the configured SaaS backend. The Collector MUST buffer only seconds of telemetry and MUST NOT be a store of record: history lives in the SaaS backend (Stage 1) or Stage-2 self-hosting, never on the app box. Changing the SaaS vendor MUST require only changing the Collector exporter address — no app deploys, no SDK swaps.

#### Scenario: SaaS outage, box survives

- GIVEN the SaaS backend is unreachable
- WHEN the backend keeps serving traffic
- THEN the Collector buffers briefly and drops (with-drop counting) rather than growing disk without bound
- AND the relay keeps serving requests.

#### Scenario: vendor swap is exporter-only

- GIVEN a new SaaS exporter endpoint + credentials
- WHEN the Collector config exporter address changes and the service restarts
- THEN telemetry arrives at the new backend with no app binary change.

### Requirement: Trace-correlated backend telemetry with templated routes

The backend MUST emit traces, metrics, and logs via OTLP to the local Collector with every record carrying the trace correlation (`trace_id`). Span and metric attributes MUST reuse the Stage-0 allowlist (`service.name`, `service.version`, `environment`, `http.method`, `http.route`, `http.status_class`, `operation`) where `http.route` is the chi route template (e.g. `/api/v1/entries/{id}`) — never raw paths with IDs. Identifiers (`user_id`, `device_id`), tokens, emails, entry text, and category names MUST ride inside span/log payloads only, never as metric/log labels.

#### Scenario: request with UUID path traced, no cardinality leak

- GIVEN an authenticated `GET /api/v1/entries/<uuid>`
- WHEN the trace and metrics export
- THEN `http.route` is `/api/v1/entries/{id}` in every signal
- AND no UUID appears in any metric label or Loki label.

#### Scenario: error log links to its trace

- GIVEN a handled 500 on an authed route
- WHEN the `slog` record bridges to OTLP
- THEN the log record carries the in-flight `trace_id`/`span_id`
- AND the client still receives the generic `{error: {code: internal_error}}` envelope.

### Requirement: Few stable dashboards

The SaaS backend MUST hold at most ~5 Grafana dashboards, built only from the stable semantic attributes above so the accepted Stage-2 Kibana rebuild stays bounded: relay health, sync life, auth funnel, trace-linked logs, and the quota/tripwire board.

#### Scenario: dashboard count audited

- GIVEN the Grafana Cloud workspace
- WHEN dashboard inventory is listed
- THEN at most 5 Stage-1 dashboards exist
- AND every panel query filters only on allowlisted attributes.

### Requirement: Alert intent lives in the repo

Alert rules MUST be kept as files in the repo (intent, thresholds, routing) and applied to the SaaS backend from those files — never SaaS click-ops. 70% tripwire crossings MUST route to the existing Telegram channel. The files MUST be vendor-neutral enough that their intent ports to Stage 2.

#### Scenario: threshold change is a PR

- GIVEN an on-call decision to move a 70% tripwire
- WHEN the change is proposed
- THEN it is a repo PR touching the alert files (not a console edit)
- AND the SaaS rule converges from the file on the next apply.

### Requirement: iOS session-level sync spans with separate distress channel

Each sync cycle MUST emit one `sync.session` span (buffered on-device and forwarded when connectivity allows) carrying outcome, wall duration, offline duration, pushed/pulled/conflict counts, and outbox depth before/after — never per-entry spans. Distress signals (crashes, N consecutive sync failures, store-open failures) MUST travel a separate channel from volume telemetry (Sentry today): volume telemetry MUST NOT be piggybacked on the API path it reports on.

#### Scenario: offline week, spans forward later

- GIVEN a week offline with daily sync attempts failing
- WHEN connectivity returns
- THEN buffered `sync.session` spans forward in order (bounded, lossy tail-drop past the cap)
- AND each span reports its offline duration without per-entry detail.

#### Scenario: API down, distress still arrives

- GIVEN the relay is unreachable (sync volume fails 100%)
- WHEN N consecutive cycles fail
- THEN a distress breadcrumb/issue still reaches Sentry (the channel that does not depend on the relay).

### Requirement: MetricKit investigation decides the collection endpoint

The change MUST investigate MetricKit (launch/hang/battery/crash diagnostics via `MXMetricManagerSubscriber`) and record a collection-endpoint decision (forward via our Collector vs. stay in Sentry) before building any MetricKit pipeline. No MetricKit payload containing user content MUST leave the device without the same identifiers-in-payloads rule.

#### Scenario: decision recorded, pipeline follows it

- GIVEN the MetricKit spike completes
- WHEN the change is reviewed
- THEN a written endpoint decision exists (Collector or Sentry) with cost/privacy reasoning
- AND only the decided endpoint is implemented.

### Requirement: SLIs now, SLO numbers after baseline

SLIs MUST be collected from day one (uptime %, 5xx rate by `operation`, sync success rate + p95 cycle duration); SLO threshold numbers MUST NOT be set until real traffic establishes a baseline. Tripwire alerts (70%/90%) operate independently of SLOs.

#### Scenario: first month has SLIs but no SLO breach pages

- GIVEN the first month of Stage-1 telemetry
- WHEN uptime % and sync success are queryable
- THEN no SLO-breach alert fires on an invented threshold
- AND the weekly digest reports the raw SLI numbers.

### Requirement: CI cardinality guard

CI MUST fail when backend or iOS telemetry code introduces a metric or log label key outside the allowlist. The allowlist test MUST cover the OTel middleware label set and the Loki label set (~5 boring labels).

#### Scenario: new label breaks the build

- GIVEN a PR adding a `user_id` metric label
- WHEN CI runs the cardinality-guard check
- THEN the check fails naming the offending label key
- AND the PR is not mergeable until the label moves into the payload.
