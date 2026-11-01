# Design — observability-stage-1

## Context

See `proposal.md` (Why) and `openspec/changes/archive/2026-10-14-observability-stage-0/design.md` (pillars, seam, allowlist, tripwires). Current state constraining this design:

- Backend (`backend/internal/observe/observe.go`): Sentry-only, allowlist already encoded (`service.name`, `http.method`, templated `http.route` via `chi.RouteContext`, `http.status_class`, `operation`); `server.go` middleware order `Recoverer → observe.Middleware → RequestID → requestLogger`; `/health` quiet with `healthCheckCount` counter. `slog` everywhere. Go 1.24 toolchain; `sentry-go v0.45.1` pinned (v0.46+ needs Go 1.25).
- iOS: `SentryReporter` DSN-gated, user-id-only, `tracesSampleRate` deliberately unset; `SyncController` single-flight cycle is the natural `sync.session` span boundary; distress breadcrumbs are static strings only.
- Infra: `docker-compose.prod.yml` (backend + local pg + nginx, log rotation done, `SENTRY_DSN` plumbed). Supabase is the system of record (500 MB read-only tripwire, 350 MB alert). Telegram interrupt/digest routing exists (Stage-0 tasks 1.2/4.x).

Invariants preserved (from `docs/project-context.md`): no PII in labels (R1 — identifiers in payloads only); `LocalStore` stays the only mutation chokepoint (telemetry reads, never writes); OpenAPI untouched (S10 — no endpoint changes); no on-disk format compat branches (pre-release).

## Goals / Non-Goals

**Goals:** OTLP traces + metrics + trace-correlated logs from backend through a VM Collector to Grafana Cloud free; session-level iOS sync spans with distress/volume split; ≤5 dashboards; repo-kept alert intent; SLIs from day one; CI cardinality guard; MetricKit endpoint decision.

**Non-Goals (design-level):** no shared OTel Collector library between backend/iOS (each SDK talks OTLP to the Collector independently); no tail-based sampling in Stage 1 (head sampling only, drop-tail); no log-shipper for nginx/pg/sys beyond Collector filelog fallback — panic/catch-all stays as-is; no histogram rollout before series-budget math is done (counters + traces first).

## Decisions

### D1 — Collector: `otelcol-contrib` single compose service, OTLP gRPC+HTTP in, batch + Grafana Cloud exporters out

Config shape (~40 lines YAML in `backend/otelcol-config.yaml`, mounted into the compose service): `otlp` receiver (both protocols — Go SDK gRPC, future Swift HTTP), `batch` processor, `otlphttp` exporters with Grafana Cloud endpoint + Basic auth from env, plus a `filelog`-free posture (no host-log mounts in Stage 1). Memory limiter caps buffer to seconds.

- *Alternative (sidecar per-signal)*: rejected — one more moving part for zero quota benefit at our volume.
- *Alternative (Gateway on separate box now)*: rejected — Stage 2 owns the second box; same-VM forwarding is the accepted design.
- ctx7: `/open-telemetry/opentelemetry-collector` — `OTLP receiver batch exporter forwarding pipeline`.

### D2 — Go SDK wiring reuses `routeTemplate()`, sits inside `observe.Middleware`

New `internal/observe/otel.go` (init from `OTEL_EXPORTER_OTLP_ENDPOINT` defaulting to localhost Collector; empty = disabled, mirroring the `SENTRY_DSN` empty-means-off pattern). Version pin (verified 2026-10-28): OTel **`v1.41.0` train** (otel + SDK + exporters) with contrib `1.41.0/2.3.0/0.66.0` — the last train supporting Go 1.24; anything newer needs a toolchain-bump change of its own. Trace provider + meter provider + `slog` bridge handler (fan-out: existing stderr handler kept during migration, OTLP handler added — stdout stays the lifeline until dashboards prove parity). HTTP instrumentation is a thin wrapper around the existing `routeTemplate()`/`operationForRoute()` — the OTel middleware MUST call the same functions, not reimplement templating (ctx7 `/open-telemetry/opentelemetry-go-contrib` — server span `{method} {route}` from request pattern; custom formatter is the only reliable fixed-name path — our formatter is `routeTemplate()`).

- *Alternative (`otelchi` drop-in)*: rejected — it derives names from `r.Pattern` (Go 1.22+) while our routes rely on `chi.RouteContext`; unifying on our tested function keeps Sentry and OTel labels identical.
- Middleware order: `Recoverer → observe.Middleware (Sentry+OTel span start) → RequestID → requestLogger → Timeout → CORS`, with `/health` short-circuit skipping span creation entirely.
- ctx7: `/open-telemetry/opentelemetry-go` — `chi HTTP middleware route templating traces metrics`.

### D3 — Loki labels stay at ~5 boring keys; everything else is a payload field

Loki labels: `{service, environment, level}` (+ `operation` only on the error stream — bounded values). `trace_id`/`span_id` ride as structured fields for trace↔log jumps. This doubles as the privacy rule (R1) and the cardinality rule.

### D4 — Dashboards query allowlisted attributes only; alerts-as-files via Terraform-lite

Dashboard inventory fixed at 5 (proposal list). Alert files: `backend/observability/alerts/*.yaml` (threshold, window, route) applied via `grafana/terraform-provider-grafana` in a non-blocking CI job (plan-only on PRs, apply on manual dispatch — no SaaS token in PR logs). Telegram webhook reuse from Stage 0.

- *Alternative (Grafana UI alerts + export)*: rejected — violates "intent ports to Stage 2"; console drift is unreviewable.
- *Alternative (Grafana MCP for agent-driven SaaS reads/writes)*: deliberately not installed (decided 2026-10-28) — verification runs via API/Terraform plan instead; one fewer token and stdio process, and no path for agent-driven console drift. Revisit only if ad-hoc querying becomes painful.

### D5 — iOS: hand-rolled `sync.session` spans over OTLP/HTTP, no OTel Swift SDK in Stage 1

Rationale: the OTel Swift SDK is a large dependency for one span type; `SyncController` already owns cycle start/end + all counters, so a ~100-line span builder + existing `URLSession` + buffer-and-forward file (JSON-lines, cap ~200 spans, tail-drop) delivers the spec with zero new SPM deps. Distress stays on Sentry (existing breadcrumbs + crash handler). Revisit the SDK when event-level spans or propagation are wanted.

- *Alternative (OTel Swift SDK now)*: deferred — cost exceeds the observed span shape; revisit trigger recorded as an open question.

### D6 — MetricKit: decide Collector-vs-Sentry after a 2-week on-device spike

Spike shape: `MXMetricManagerSubscriber` in a debug-only harness logging payload classes/sizes/frequency (no upload). Decision criteria: daily volume × retention need × dashboard home. Prior: launch/hang/battery stay in Sentry if under 1 MB/day/device (sentry-cocoa already consumes MetricKit); forward via Collector only if the team wants cross-signal correlation. No user content leaves the device either way.

- ctx7: `/websites/developer_apple_metrickit` — `MXMetricManager payload diagnostics collection` (daily `didReceive`, session-scoped `pastDiagnosticPayloads`).

### D7 — SLIs as recording rules from day one; SLO thresholds deferred

Recording rules (not alerts): `uptime_pct`, `http_5xx_rate{operation}`, `sync_success_rate`, `sync_cycle_p95`. Weekly digest reads them. SLO numbers land only after ≥2 weeks of stable traffic — a tasks.md gate, not a judgment call in review.

## Risks / Trade-offs

- [Risk] OTel Go SDK version demands Go ≥1.25 (Stage-0 `sentry-go` precedent) → Mitigation: pin SDK to the newest release declaring `go 1.24` support; verify `go.mod` toolchain line in CI before any other Stage-1 task; toolchain bump is its own change.
- [Risk] Histogram buckets explode the 10k free-tier series budget → Mitigation: counters + traces first; histograms behind the series-budget math task with explicit bucket choices; 90% shed-load (cut `operation`, coarsen status) is pre-agreed.
- [Risk] Double-emit (stdout + OTLP) doubles log volume during migration → Mitigation: time-boxed overlap (one release), then stdout drops to ERROR-only; `/health` excluded in both paths.
- [Risk] iOS span buffer grows on long-offline devices → Mitigation: hard cap + tail-drop + `dropped_spans` counter span; buffer file lives outside the account DB (telemetry is not user data).
- [Risk] Grafana Cloud free-tier auth token leaks via compose env → Mitigation: token in VM `.env` + GitHub `stage`-env secret only, never in repo; Collector config references `${GRAFANA_CLOUD_OTLP_KEY}`.
- [Risk] Alert-file apply job becomes a second deploy path → Mitigation: plan-only on PRs, manual apply; alert files never gate backend deploys.

## Migration Plan

1. Land Collector service (disabled exporters → verify no crash, no series) behind `OTEL_ENABLED=0` default.
2. Enable backend traces+logs to local Collector, stdout overlap; verify trace↔log jumps in Grafana.
3. Enable metrics; run series-budget check against the 10k tripwire; dashboards 1–4.
4. Ship alert files (plan-only first), wire 70% Telegram routes; quota board (dashboard 5).
5. iOS `sync.session` spans behind a build flag; TestFlight soak; MetricKit spike in parallel → endpoint decision.
6. SLIs recording; SLO gate task stays open until baseline traffic exists.
7. Rollback at every step: `OTEL_ENABLED=0` / Collector service stop restores Stage-0 posture exactly (Sentry + logs + pings untouched).

## Open Questions

- O1: OTel Swift SDK revisit trigger — answer when event-level spans or W3C propagation are requested (does not change specs/tasks now).
- O2: Exact Grafana Cloud free-tier OTLP endpoint shape at implement time (console detail, re-confirm — does not change the exporter-seam design).
