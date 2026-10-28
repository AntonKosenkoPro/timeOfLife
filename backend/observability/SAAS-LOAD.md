# SaaS load procedure — observability Stage 1 (§4.1/§4.2/§4.3 SaaS halves)

Run AFTER the merged deploy forwards data (`OTEL_ENABLED=1` on the VM).
Operator machine only. Secrets come from the environment — never paste them
into chat, never commit them.

```bash
export GRAFANA_STACK="https://bronzeporcupine1580.grafana.net"
export GRAFANA_CLOUD_OTLP_KEY="<base64(instanceID:apiToken)>"  # same shape as the secret
```

## 1. Dashboards (§4.2)

For each file in `backend/observability/dashboards/*.json`, resolve the
`LOAD-TIME CHECK` header first (Explore → verify OTLP label/metric naming,
dots vs underscores; fix the file, commit the fix), then load:

```bash
for f in backend/observability/dashboards/*.json; do
  # inject stack datasources: replace ${DS_PROMETHEUS}/${DS_LOKI}/${DS_TEMPO}
  # with the stack's datasource UIDs (Stack → Connections → datasources)
  curl -s -o /dev/null -w "$f %{http_code}\n" \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic $GRAFANA_CLOUD_OTLP_KEY" \
    "$GRAFANA_STACK/api/dashboards/db" -d @"$f"
done
```

Expect `200` per file. Then open each dashboard, confirm panels render
(no "no data" after 5 min of relay traffic), and fix naming drift in the
repo files (never in the console).

## 2. Series-budget check (§4.1)

```text
grafanacloud_instance_active_series   → must stay < 7000 (70% of 10k free)
```

If it crosses 7000: Telegram ping fires (tripwire), and the 90% shed-load
(cut `operation`, coarsen `http.status_class`) is pre-agreed — see
`alerts/README.md`. Histograms stay OFF until this check clears with headroom.

## 3. Recording rules + alerts (§4.4/§4.3)

`slis/recording-rules.yaml` and `alerts/*.yaml` are intent files. Until the
terraform-provider-grafana job exists, apply the threshold crossings as
Grafana managed-alert rules ONCE from these files, and note any drift back
here immediately. Plan-only CI wiring is the follow-up that ends hand-apply.
