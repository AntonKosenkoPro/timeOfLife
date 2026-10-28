# Tasks — observability-stage-1

## 1. Research bundle (ctx7 — DONE at propose time, re-confirm at apply)

- [x] 1.1 Topic/pipeline: `/open-telemetry/opentelemetry-go` (`chi HTTP middleware route templating traces metrics`) + `/open-telemetry/opentelemetry-collector` (`OTLP receiver batch exporter forwarding pipeline`).
- [x] 1.2 Span naming: `/open-telemetry/opentelemetry-go-contrib` (`otelchi chi router instrumentation span name` — `{method} {route}` from pattern; custom formatter only reliable fixed-name path → reuse `routeTemplate()`).
- [x] 1.3 Apple API: `/websites/developer_apple_metrickit` (`MXMetricManager payload diagnostics collection` — daily `didReceive`, session-scoped `pastDiagnosticPayloads`). Pin: iOS 18 SDK via Xcode 16+.
- [x] 1.4 HIG waived — no user-facing app UI in scope (Grafana consoles are operator surfaces; iOS telemetry is background). No SwiftUI view/locale diff.
- [x] 1.5 Re-confirm at apply time (DONE 2026-10-28): OTel Go **v1.41.0 train is the pin** — v1.41.0/2026-03-02 is the last release supporting Go 1.24 (next release requires Go 1.25+); contrib train `1.41.0/2.3.0/0.66.0`. `go 1.24.0` toolchain line stays; CI `setup-go 1.24` is the enforcer. Grafana Cloud free-tier OTLP endpoint + token shape re-verifies at §4 against the real stack (no account yet — see §4 blocker).

## 2. Collector service (VM forwarding only)

- [x] 2.1 Add `backend/otelcol-config.yaml` (OTLP gRPC+HTTP receivers → batch + memory-limiter → Grafana Cloud `otlphttp` exporters; `${GRAFANA_CLOUD_OTLP_KEY}` from env, never in repo). (DONE: image `otel/opentelemetry-collector-contrib:0.135.0` pinned; discard sentinel default; queue+retry off.)
- [x] 2.2 Wire Collector service into `docker-compose.prod.yml` (log rotation same as other services); `OTEL_ENABLED=0` default = Stage-0 posture. (DONE: `otel-collector` service; backend `OTEL_EXPORTER_OTLP_ENDPOINT` defaults to `otel-collector:4317`.)
- [ ] 2.3 Deploy with exporters disabled; verify relay + Collector healthy, zero series emitted, disk bounded. (BLOCKED on VM access + user's Grafana stack — deploy-time task.)

## 3. Backend OTel SDK + slog bridge + templating

- [x] 3.1 Add OTel SDK dep (go-1.24-compatible pin from 1.5) + `internal/observe/otel.go` (init from `OTEL_EXPORTER_OTLP_ENDPOINT`, empty = disabled mirroring `SENTRY_DSN`). (DONE: OTel v1.41.0 + log v0.17.0; `go 1.24.0` toolchain line kept.)
- [x] 3.2 OTel middleware reusing `routeTemplate()`/`operationForRoute()`; order `Recoverer → observe → RequestID → requestLogger → Timeout → CORS`; `/health` skips span creation. (DONE: middleware extended, not reimplemented; label-free `lifio.health.checks` series.)
- [x] 3.3 `slog`→OTLP bridge (fan-out: stderr kept during migration; `trace_id`/`span_id` on every OTLP record; Loki labels `{service, environment, level}` + `operation` on error stream only). (DONE: `FanoutHandler` + `BridgeSlog`; env via Collector resource processor.)
- [x] 3.4 Contract tests: UUID path exports `http.route=/api/v1/entries/{id}` in all signals; `/health` emits nothing per-request; 500 keeps generic envelope with trace correlation. (DONE in `otel_test.go`.)
- [x] 3.5 `gofmt -l .` empty; `go vet`; `golangci-lint run`; `go test ./... -cover` green. (DONE: lint 0 issues; all `ok`.)
- [x] 3.6 Migrate request-path `slog.Info` calls to `*Context` variants so production records carry `trace_id` (only `*Context` log calls correlate today; tests pass ctx explicitly). Follow-up within this change, before §2.3 deploy. (DONE: 83 sites script-migrated to `r.Context()`/`ctx` incl. middleware closures + access log; startup/worker/no-ctx helpers untouched; `go test ./...` green, lint 0 issues.)

## 4. Dashboards (≤5) + alerts as files + SLIs

- [ ] 4.1 Provision Grafana Cloud free (endpoint from 1.5); enable metrics; run series-budget check vs 10k tripwire (counters + traces first, histograms deferred per D7-risk). (STATUS 2026-10-28: account created by user; endpoint `https://otlp-gateway-prod-eu-central-0.grafana.net/otlp` + instance `1896298` verified with a one-shot auth probe (HTTP 200, credential NOT stored anywhere). Deploy plumbing DONE: `backend.yml` renders `OTEL_ENABLED`/`OTEL_EXPORTER_OTLP_ENDPOINT`/`GRAFANA_CLOUD_OTLP_ENDPOINT` (vars) + `GRAFANA_CLOUD_OTLP_KEY` (secret) into VM `.env`. LEFT: user sets those 3 vars + 1 secret in the `stage` env (rotate the token first — the chat-pasted value must be retired), then series-budget check runs post-deploy.)
- [x] 4.2 Build dashboards 1–4 (relay health, sync life stub, auth funnel, trace-linked logs) querying allowlisted attributes only. (DONE files: `backend/observability/dashboards/*.json` ×5 incl. quota board; JSON-validated; each carries a LOAD-TIME CHECK header for OTLP naming/dots-vs-underscores + deferred histograms. SaaS load waits for stack access — needs the stack slug/URL.)
- [x] 4.3 Add `backend/observability/alerts/*.yaml` (repo intent) + plan-only CI job; wire 70% tripwires to Telegram; quota board (dashboard 5). (DONE files: sentry-events, grafana-series, grafana-logs, supabase-db-size + README, schema lifio.alert/v1. SaaS apply + plan-only CI wiring waits for the user's provisioned stack.)
- [x] 4.4 Add SLI recording rules (`uptime_pct`, `http_5xx_rate{operation}`, `sync_success_rate`, `sync_cycle_p95`); weekly digest reads them; SLO-threshold task stays OPEN until ≥2 weeks stable traffic. (DONE file: backend/observability/slis/recording-rules.yaml, lifio.sli/v1; thresholds unset by design.)

## 5. CI cardinality guard

- [x] 5.1 Allowlist test failing on unknown metric/log label keys (covers OTel middleware set + Loki set); `/health` contributes nothing. (DONE: `CheckLabelAllowlist` + guard test pins exact sets.)
- [x] 5.2 Negative test: `user_id` label breaks the build with the offending key named. (DONE: both kinds + unknown-kind fail-closed.)

## 6. iOS sync.session spans + distress separation

- [x] 6.1 Span builder + buffer-and-forward file (JSON-lines, cap ~200, tail-drop + `dropped_spans` counter; outside the account DB) wired to `SyncController` cycle boundaries (outcome, durations, pushed/pulled/conflicts, outbox depth). (DONE: `SyncSessionSpan`/`SyncSpanBuffer`/`SyncTelemetry` + `SyncController` wiring; PII-safe by construction.)
- [x] 6.2 OTLP/HTTP export to local Collector via relay host config; build-flagged; offline soak test (buffer → forward in order, bounded). (DONE: `SyncSpanExporter` canonical OTLP JSON, Debug-on/Release-off + plist overrides; offline-soak test green. Owner fixed 3 worker bugs: `spanId` typo, `APIError.transport` label, `withLock` + OTLP `resource` wrapper.)
- [x] 6.3 Distress separation test: relay unreachable → volume fails 100% AND Sentry distress still arrives (no piggyback on `/v1/sync`). (DONE: `distressSeparation` green — threshold N=3, fires once per streak via `SentryReporter.captureSyncDistress`.)
- [x] 6.4 `swiftlint lint --strict` clean; `xcodebuild` build + test green (per `docs/ios-test-loop.md`). (DONE: lint 0 violations/211 files; filtered suites 95 passed, EXIT=0.)

## 7. MetricKit spike → endpoint decision

- [x] 7.1 Debug-only `MXMetricManagerSubscriber` harness logging payload classes/sizes/frequency (no upload); 2-week on-device data. (DONE code: `MetricKitHarness` Debug-only, zero upload paths; on-device data collection pending.)
- [ ] 7.2 Record decision (Collector vs Sentry) with cost/privacy reasoning in design.md; implement only the decided endpoint. (OPEN by design — needs on-device data.)

## 8. Verification + close-out

- [x] 8.1 Migration-plan order verified step-by-step (§Migration Plan 1–6); rollback drill (`OTEL_ENABLED=0` + Collector stop = Stage-0 posture). (DONE code-side: order followed; §2.3 deploy check + live rollback drill run post-merge on the VM.)
- [x] 8.2 Both suites green after final rebase on `origin/main` (`go test ./...`; xcodebuild test); linters strict-clean; `gofmt -l .` empty. (DONE: base 0-behind; backend full green + lint 0; iOS full suite 869 passed EXIT=0 — one transient runner hang on first attempt, clean retry.)
- [x] 8.3 Re-check `Requirements/FURPS/*.md` rows; fix conflicts. (DONE: only S8 logging row touches this area — expanded, no conflict.)
- [x] 8.4 Update `docs/project-context.md` (Observability section → Stage 1), `README.md` + `docs/ci.md` if run steps changed, `backend/.env.example` (new `OTEL_*` vars), issue #150 comment; `openspec validate --all --strict` green. (DONE: project-context Stage-1 block, ci.md secret/var list, .env.example by backend worker. LEFT for owner: #150 progress comment.)
