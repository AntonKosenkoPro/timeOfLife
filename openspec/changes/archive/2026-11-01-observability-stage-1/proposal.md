# Proposal — observability-stage-1

## Why

Stage 0 bought "is it alive + what crashed" (off-box `/health` watch, Sentry pillar, bounded log retention). We still fly blind on *why it is slow or degrading*: no request traces, no latency/throughput metrics, no per-sync visibility, no SLOs, and log lines without trace correlation. Issue #150 tracks this Stage 1 as the follow-up to `2026-10-14-observability-stage-0` (whose `design.md` holds the full direction). Now is the right time because the Stage-0 seam decisions (OTLP-to-Collector, allowlist, Sentry-stays) are settled and free-tier quotas need dashboards + tripwire automation before real traffic arrives.

## What Changes

- **OTel Collector on the VM (forwarding only)**: new compose service running the Collector (OTLP receivers, batch processor, SaaS exporters). Seconds of buffer, no storage on the box — history must never live on the app VM. Exporter address is the only migration seam to Stage 2.
- **Go OTel SDK + `slog` bridge**: backend emits traces, metrics, and trace-correlated logs via OTLP to the local Collector. Chi route templating (`routeTemplate()` reuse — never raw UUIDs) is configured in the OTel middleware; `/health` stays quiet in all three signals.
- **SaaS backend on free tiers**: Grafana Cloud free (metrics + logs + traces) via exporter address; Sentry stays the errors/crashes pillar (unchanged, DSN flip later).
- **~5 Grafana dashboards max**, built from stable semantic attributes (rebuild for Kibana one day is accepted and bounded): relay health, sync life, auth funnel, logs (trace-linked), quota/tripwire board.
- **Alert rules as repo-kept files**: alert intent lives in git (not SaaS click-ops) and ports to Stage 2; 70% tripwire crossings route to the existing Telegram channel.
- **iOS session-level telemetry**: one `sync.session` span per sync cycle (outcome, durations, pushed/pulled/conflict counts, outbox depth) with buffer-and-forward; distress signals (crashes, N consecutive sync failures, store-open failures) stay on a separate channel from volume telemetry (Sentry today).
- **MetricKit investigation + collection endpoint decision**: launch/hang/battery telemetry; decide whether payloads forward via our Collector or stay in Sentry — investigation first, pipeline second.
- **First SLOs**: SLIs collected from day one (uptime %, 5xx rate, sync success + p95 cycle duration); SLO numbers only once real traffic sets a baseline.
- **CI cardinality guard**: a check failing on unknown metric/log labels (allowlist enforcement), so a new label can never silently explode series count.

## Capabilities

### New Capabilities

(none — this change extends the existing observability contract)

### Modified Capabilities

- `observability`: Stage-0 contract (uptime watch, bounded logs, quiet `/health`, Sentry pillar) extended with the OTel pipeline (Collector + SDK + `slog` bridge + chi templating), dashboard/alert/SLO coverage, iOS `sync.session` spans with distress/volume separation, MetricKit decision, and the CI label-allowlist guard.

## Impact

- **Backend** (`backend/`): new OTel SDK dependency (must declare `go < 1.25` compat — repo toolchain is Go 1.24, cf. Stage-0 `sentry-go v0.45.1` lesson), new `internal/observe/otel*` or equivalent wiring, `server.go` middleware order, `config.go` env (`OTEL_*` / exporter endpoint), `docker-compose.prod.yml` Collector service, contract tests for templating + quiet `/health` across signals.
- **iOS** (`ios/TimeOfLife/`): OTel Swift dependency (evaluation), `SyncController` cycle instrumentation, buffer-and-forward store, `SentryReporter` untouched (distress stays), MetricKit subscriber spike.
- **Infra/deploy**: Collector config file + compose wiring, Grafana Cloud provisioning (free tier), repo-kept alert files, Telegram routing reuse, Supabase/quota tripwires unchanged.
- **API contract**: no endpoint changes; `backend/api/openapi.yaml` untouched (S10).

## Non-goals

- Self-hosted ELK/Sentry (Stage 2; gets its own box when quotas force it).
- More than ~5 dashboards; per-entry/per-user drill-downs (identifiers stay in payloads, never labels).
- Event-level iOS spans (session-level only — telemetry must cost less than the feature).
- SLO numbers without a traffic baseline (SLIs now, objectives later).
- Log-shipper coverage of nginx/pg/sys beyond what the Collector forwarder already handles (panic/catch-all stays as-is).

## Research bundle (ctx7 — mandatory)

Pin: Go 1.24 toolchain (repo CI `setup-go 1.24`); new Go deps must declare `go < 1.25` compat. iOS 18 SDK via Xcode 16+.

- Topic/span-naming: `/open-telemetry/opentelemetry-go-contrib` — `otelchi chi router instrumentation span name` (server span `{method} {route}` from request pattern; custom formatter is the only reliable fixed-name path).
- Topic/pipeline: `/open-telemetry/opentelemetry-go` — `chi HTTP middleware route templating traces metrics` + `/open-telemetry/opentelemetry-collector` — `OTLP receiver batch exporter forwarding pipeline` (receivers → batch → exporters; fanout delivery semantics).
- Apple API: `/websites/developer_apple_metrickit` — `MXMetricManager payload diagnostics collection` (`MXMetricManagerSubscriber.didReceive`, daily delivery, `pastDiagnosticPayloads` session-scoped).
- Best-practice/setup: Collector forwarding + Grafana Cloud free-tier provisioning verified at implement time against current SaaS docs (exporter endpoint + auth are the only migration seam; re-confirm before coding).
- HIG: N/A — no user-facing app UI changes in this change (Grafana dashboards are operator consoles; iOS telemetry is background). Evidence: no SwiftUI view/locale diff in scope.

## Affected baselines + docs

- Baseline: `openspec/specs/observability/spec.md` (Stage-0 contract — extended by this change's delta).
- Direction: `openspec/changes/archive/2026-10-14-observability-stage-0/design.md` (pillars, seam, allowlist, tripwires — all preserved).
- Issue: #150 (scope + exit-ramp constraints + tripwire triggers).
