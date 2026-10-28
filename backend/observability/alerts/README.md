# Alert intent — README
#
# Intent lives HERE (git), not in the SaaS console.
# The Grafana/Sentry/Supabase rules converge FROM backend/observability/alerts/*.yaml:
#   - plan-only CI job renders the SaaS rules from these files on PRs
#     (terraform-provider-grafana once the token/endpoint is provisioned);
#   - apply is MANUAL (maintainer dispatch) — alert files never gate backend deploys;
#   - rules are NEVER console-edited: console drift is unreviewable and violates
#     "intent ports to Stage 2" (D4 — console-export alternative explicitly rejected).
#
# Schema: lifio.alert/v1 (schema_version: 1). Each file pins threshold (fraction
# of quota + absolute where the quota is fixed), evaluation window, route, and
# the pre-agreed 90% shed-load action from the tripwire table (70% alert ->
# 90% shed load -> 100% migrate). All 70% crossings route to Telegram
# (existing channel; INTERRUPT lane for quota-burn per Stage-0 routing).
#
# Tripwire files:
#   - sentry-events.yaml     — Sentry events/mo, 70% burn -> Telegram ping;
#                              90% -> errors-only SDK, drop breadcrumbs/perf.
#   - grafana-series.yaml    — Grafana Cloud active series, 70% of 10k (7,000)
#                              sustained 1h -> Telegram ping;
#                              90% (9,000) -> cut `operation`, coarsen status.
#   - grafana-logs.yaml      — Grafana Cloud logs ingest GB, 70% of plan quota
#                              -> Telegram ping;
#                              90% -> retention 30d->7d, drop DEBUG.
#   - supabase-db-size.yaml  — Supabase DB size, ~350 MB (70% of the 500 MB
#                              read-only line) via backend/scripts/supabase-size-check.sh
#                              -> Telegram ping; 90% -> paid-tier upgrade first
#                              (already specced, unchanged).
#
# Panel/alert query discipline (D4, Stage-0 allowlist): queries may group/filter
# by allowlisted attributes ONLY —
#   service.name, service.version, environment, http.method,
#   http.route (templated, never raw UUIDs), http.status_class, operation.
# Identifiers (user_id, device_id), route params, category names, entry text,
# emails, tokens ride inside payloads/span attributes — never in labels.
# Loki discipline: stream selection stays boring (service_name only —
# `level` is structured metadata filtered post-selector, e.g.
# `{service_name="lifio-backend"} | level="error"`, NOT a stream label) +
# `operation` on the error stream only; trace_id/span_id are structured fields.
#
# Dashboard inventory (fixed at 5 — rebuild for Stage 2 stays bounded):
#   1. relay health        (uptime, 5xx rate, latency from allowlisted metrics)
#   2. sync life           (sync.session span outcomes, durations, outbox depth)
#   3. auth funnel         (otp_request -> otp_verify -> session, by operation)
#   4. trace-linked logs   (Loki streams with trace_id/span_id jumps)
#   5. quota board         (all four tripwires above + weekly quota trend)
# Stage-2 rebuild note: dashboards do NOT migrate (Grafana != Kibana) — keep to
# these 5, built from stable semantic attributes, so the rebuild is bounded.
# SLI recording rules live next door in ../slis/recording-rules.yaml
# (thresholds UNSET until >=2 weeks stable traffic — SLO gate stays open).
