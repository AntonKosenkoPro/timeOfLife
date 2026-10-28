package observe

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/go-chi/chi/v5"
	"go.opentelemetry.io/otel/codes"
	otellog "go.opentelemetry.io/otel/log"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/metric/metricdata"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

// captureLogProcessor is an in-memory sdk/log Processor for tests: it keeps
// every emitted record so the suite can assert on the exact attribute keys
// and trace correlation the bridge produces.
type captureLogProcessor struct {
	mu      sync.Mutex
	records []*sdklog.Record
}

func (p *captureLogProcessor) Enabled(context.Context, sdklog.EnabledParameters) bool {
	return true
}

func (p *captureLogProcessor) OnEmit(_ context.Context, r *sdklog.Record) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	cp := r.Clone()
	p.records = append(p.records, &cp)
	return nil
}

func (p *captureLogProcessor) Shutdown(context.Context) error   { return nil }
func (p *captureLogProcessor) ForceFlush(context.Context) error { return nil }

func (p *captureLogProcessor) all() []*sdklog.Record {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]*sdklog.Record(nil), p.records...)
}

// testTelemetry bundles the in-memory providers installed for one test.
type testTelemetry struct {
	spans   *tracetest.SpanRecorder
	metrics *sdkmetric.ManualReader
	logs    *captureLogProcessor
}

// newTestTelemetry installs in-memory trace/metric/log providers and restores
// every global it touches on cleanup, so OTel-enabled contract tests cannot
// leak into the Sentry-only suites.
func newTestTelemetry(t *testing.T) *testTelemetry {
	t.Helper()
	prevEnabled := otelEnabled.Load()
	prevTracer := otelTracer
	prevCounter := httpRequestCounter
	prevLogger := otelLogger
	prevShutdown := otelShutdownFn
	prevHealth := otelHealthCount.Load()
	prevDefault := slog.Default()
	t.Cleanup(func() {
		otelEnabled.Store(prevEnabled)
		otelTracer = prevTracer
		httpRequestCounter = prevCounter
		otelLogger = prevLogger
		otelShutdownFn = prevShutdown
		otelHealthCount.Store(prevHealth)
		slog.SetDefault(prevDefault)
	})

	sr := tracetest.NewSpanRecorder()
	tp := sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(sr))
	reader := sdkmetric.NewManualReader()
	mp := sdkmetric.NewMeterProvider(sdkmetric.WithReader(reader))
	clp := &captureLogProcessor{}
	lp := sdklog.NewLoggerProvider(sdklog.WithProcessor(clp))
	otelHealthCount.Store(0)
	if err := initTelemetry(tp, mp, lp); err != nil {
		t.Fatalf("initTelemetry: %v", err)
	}
	// Mirror production wiring (InitOTel → BridgeSlog): the default slog
	// handler fans out to the OTLP bridge, so InfoContext in handlers picks
	// up the in-flight span for trace_id/span_id correlation.
	slog.SetDefault(slog.New(FanoutHandler(slog.NewTextHandler(io.Discard, nil))))
	return &testTelemetry{spans: sr, metrics: reader, logs: clp}
}

// spanAttrValues flattens a span's attributes for allowlist/UUID assertions.
func spanAttrValues(s sdktrace.ReadOnlySpan) map[string]string {
	out := make(map[string]string, len(s.Attributes()))
	for _, kv := range s.Attributes() {
		out[string(kv.Key)] = kv.Value.Emit()
	}
	return out
}

// collectMetrics drains the manual reader into name → datapoints.
func collectMetrics(t *testing.T, r *sdkmetric.ManualReader) map[string][]metricdata.DataPoint[int64] {
	t.Helper()
	var rm metricdata.ResourceMetrics
	if err := r.Collect(context.Background(), &rm); err != nil {
		t.Fatalf("Collect: %v", err)
	}
	out := map[string][]metricdata.DataPoint[int64]{}
	for _, sm := range rm.ScopeMetrics {
		for _, m := range sm.Metrics {
			sum, ok := m.Data.(metricdata.Sum[int64])
			if !ok {
				continue
			}
			out[m.Name] = append(out[m.Name], sum.DataPoints...)
		}
	}
	return out
}

// logAttrValues flattens a captured log record's attributes.
func logAttrValues(r *sdklog.Record) map[string]string {
	out := map[string]string{}
	r.WalkAttributes(func(kv otellog.KeyValue) bool {
		out[kv.Key] = kv.Value.String()
		return true
	})
	return out
}

// TestInitOTelDisabledByDefault proves the empty-means-off contract: without
// OTEL_ENABLED=1 + endpoint, init is a no-op and the middleware passes
// requests through with zero OTel behavior change (Stage-0 posture).
func TestInitOTelDisabledByDefault(t *testing.T) {
	if err := InitOTel(OTelConfig{}); err != nil {
		t.Fatalf("InitOTel(empty) returned error: %v", err)
	}
	if err := InitOTel(OTelConfig{Enabled: true}); err != nil {
		t.Fatalf("InitOTel(enabled, no endpoint) returned error: %v", err)
	}
	if OTelEnabled() {
		t.Error("expected OTel to stay disabled without an endpoint")
	}

	h := Middleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/entries/550e8400-e29b-41d4-a716-446655440000", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200 with OTel disabled, got %d", w.Code)
	}
}

// TestOTelRouteTemplateInAllSignals is the §3.4 contract test: an authed GET
// on a UUID path exports http.route=/api/v1/entries/{id} in traces, metrics,
// and logs — and the raw UUID appears in no label or span name.
func TestOTelRouteTemplateInAllSignals(t *testing.T) {
	tt := newTestTelemetry(t)
	const uuid = "550e8400-e29b-41d4-a716-446655440000"

	r := chi.NewRouter()
	// Production shape (server.go): the middleware is registered via Use, so
	// it runs after chi matches the route and RoutePattern is populated.
	r.Use(Middleware)
	r.Get("/api/v1/entries/{id}", func(w http.ResponseWriter, r *http.Request) {
		// Identifier rides in the payload (fields), never as a label.
		slog.InfoContext(r.Context(), "get entry", "user_id", "user-123", "op", "get_entry")
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/entries/"+uuid, nil)
	r.ServeHTTP(httptest.NewRecorder(), req)

	// Trace signal.
	ended := tt.spans.Ended()
	if len(ended) != 1 {
		t.Fatalf("expected exactly 1 span, got %d", len(ended))
	}
	span := ended[0]
	wantName := "GET /api/v1/entries/{id}"
	if span.Name() != wantName {
		t.Errorf("expected span name %q, got %q", wantName, span.Name())
	}
	sattrs := spanAttrValues(span)
	for _, kv := range [][2]string{
		{"http.method", http.MethodGet},
		{"http.route", "/api/v1/entries/{id}"},
		{"http.status_class", "2xx"},
		{"operation", "GET /api/v1/entries/{id}"},
	} {
		if sattrs[kv[0]] != kv[1] {
			t.Errorf("expected span attr %s=%q, got %q", kv[0], kv[1], sattrs[kv[0]])
		}
	}
	if strings.Contains(span.Name(), uuid) {
		t.Errorf("span name leaks raw UUID: %q", span.Name())
	}
	for k, v := range sattrs {
		if strings.Contains(v, uuid) {
			t.Errorf("span attr %s leaks raw UUID: %q", k, v)
		}
		if err := CheckLabelAllowlist("metric", k); err != nil {
			t.Errorf("span attr key guard: %v", err)
		}
	}

	// Metric signal.
	metrics := collectMetrics(t, tt.metrics)
	points, ok := metrics["http.server.requests"]
	if !ok || len(points) != 1 {
		t.Fatalf("expected 1 http.server.requests datapoint, got %v", metrics)
	}
	mattrs := map[string]string{}
	for _, kv := range points[0].Attributes.ToSlice() {
		mattrs[string(kv.Key)] = kv.Value.Emit()
	}
	for _, kv := range [][2]string{
		{"http.method", http.MethodGet},
		{"http.route", "/api/v1/entries/{id}"},
		{"http.status_class", "2xx"},
		{"operation", "GET /api/v1/entries/{id}"},
	} {
		if mattrs[kv[0]] != kv[1] {
			t.Errorf("expected metric attr %s=%q, got %q", kv[0], kv[1], mattrs[kv[0]])
		}
	}
	for k, v := range mattrs {
		if strings.Contains(v, uuid) {
			t.Errorf("metric attr %s leaks raw UUID: %q", k, v)
		}
		if err := CheckLabelAllowlist("metric", k); err != nil {
			t.Errorf("metric label guard: %v", err)
		}
	}

	// Log signal: one record, trace-correlated, PII in payload only.
	records := tt.logs.all()
	if len(records) != 1 {
		t.Fatalf("expected exactly 1 log record, got %d", len(records))
	}
	lattrs := logAttrValues(records[0])
	if lattrs["trace_id"] != span.SpanContext().TraceID().String() {
		t.Errorf("expected log trace_id %s, got %q", span.SpanContext().TraceID(), lattrs["trace_id"])
	}
	if lattrs["span_id"] != span.SpanContext().SpanID().String() {
		t.Errorf("expected log span_id %s, got %q", span.SpanContext().SpanID(), lattrs["span_id"])
	}
	if lattrs["level"] != "INFO" {
		t.Errorf("expected log level INFO, got %q", lattrs["level"])
	}
	if _, ok := lattrs["user_id"]; ok {
		t.Errorf("user_id must never be a log label, got keys %v", keysOf(lattrs))
	}
	if _, ok := lattrs["operation"]; ok {
		t.Errorf("operation must ride the error stream only; INFO record has keys %v", keysOf(lattrs))
	}
	fields := map[string]any{}
	if err := json.Unmarshal([]byte(lattrs["fields"]), &fields); err != nil {
		t.Fatalf("expected fields JSON payload: %v", err)
	}
	if fields["user_id"] != "user-123" || fields["op"] != "get_entry" {
		t.Errorf("expected identifiers in fields payload, got %v", fields)
	}
	for k := range lattrs {
		if err := CheckLabelAllowlist("log", k); err != nil {
			t.Errorf("log label guard: %v", err)
		}
	}
}

// TestOTelHealthEmitsNothing proves the quiet-health contract (§3.4): /health
// creates no span and no per-request metric series — only the single
// label-free health series increments.
func TestOTelHealthEmitsNothing(t *testing.T) {
	tt := newTestTelemetry(t)

	h := Middleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	before := otelHealthCount.Load()
	for range 3 {
		req := httptest.NewRequest(http.MethodGet, "/health", nil)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200 for /health, got %d", w.Code)
		}
	}

	if ended := tt.spans.Ended(); len(ended) != 0 {
		t.Errorf("expected no spans for /health, got %d", len(ended))
	}
	if records := tt.logs.all(); len(records) != 0 {
		t.Errorf("expected no log records for /health, got %d", len(records))
	}
	metrics := collectMetrics(t, tt.metrics)
	if points, ok := metrics["http.server.requests"]; ok && len(points) != 0 {
		t.Errorf("expected no http.server.requests series for /health, got %d", len(points))
	}
	health, ok := metrics["lifio.health.checks"]
	if !ok || len(health) != 1 {
		t.Fatalf("expected single health-check series, got %v", metrics)
	}
	if got := health[0].Value; got != before+3 {
		t.Errorf("expected health series %d, got %d", before+3, got)
	}
	if attrs := health[0].Attributes.ToSlice(); len(attrs) != 0 {
		t.Errorf("expected no per-request labels on health series, got %v", attrs)
	}
}

// TestOTel500GenericEnvelopeWithTrace proves the error contract (§3.4): a
// handled 500 keeps the generic {error:{code:internal_error}} envelope while
// the span is marked Error and the bridged log record carries the same
// trace_id.
func TestOTel500GenericEnvelopeWithTrace(t *testing.T) {
	tt := newTestTelemetry(t)

	r := chi.NewRouter()
	r.Use(Middleware)
	r.Get("/api/v1/entries/{id}", func(w http.ResponseWriter, r *http.Request) {
		slog.ErrorContext(r.Context(), "get entry failed", "op", "get_entry", "error", "dial tcp: connection refused")
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"error": map[string]string{"code": "internal_error", "message": "An internal error occurred"},
		})
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/entries/550e8400-e29b-41d4-a716-446655440000", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	var body struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Error.Code != "internal_error" {
		t.Errorf("expected generic internal_error envelope, got %q", body.Error.Code)
	}

	ended := tt.spans.Ended()
	if len(ended) != 1 {
		t.Fatalf("expected exactly 1 span, got %d", len(ended))
	}
	span := ended[0]
	if span.Status().Code != codes.Error {
		t.Errorf("expected span status Error on 500, got %v", span.Status())
	}
	sattrs := spanAttrValues(span)
	if sattrs["http.route"] != "/api/v1/entries/{id}" || sattrs["http.status_class"] != "5xx" {
		t.Errorf("expected templated route + 5xx class, got %v", sattrs)
	}

	records := tt.logs.all()
	if len(records) != 1 {
		t.Fatalf("expected exactly 1 log record, got %d", len(records))
	}
	lattrs := logAttrValues(records[0])
	if lattrs["trace_id"] != span.SpanContext().TraceID().String() {
		t.Errorf("expected error log linked to span trace %s, got %q", span.SpanContext().TraceID(), lattrs["trace_id"])
	}
	if lattrs["operation"] != "get_entry" {
		t.Errorf("expected operation label on the error stream, got %v", keysOf(lattrs))
	}
	for k := range lattrs {
		if err := CheckLabelAllowlist("log", k); err != nil {
			t.Errorf("log label guard: %v", err)
		}
	}
}

// TestCardinalityGuardAllowlist (§5.1) pins the exact key sets the backend
// may emit: the OTel middleware label set plus the Loki label set. Any new
// key breaks the build here before it can explode series cardinality.
func TestCardinalityGuardAllowlist(t *testing.T) {
	tt := newTestTelemetry(t)

	r := chi.NewRouter()
	r.Use(Middleware)
	r.Get("/api/v1/entries/{id}", func(w http.ResponseWriter, r *http.Request) {
		slog.InfoContext(r.Context(), "ok")
		w.WriteHeader(http.StatusOK)
	})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/entries/123e4567-e89b-12d3-a456-426614174000", nil)
	r.ServeHTTP(httptest.NewRecorder(), req)

	metricKeys := map[string]bool{}
	for _, s := range tt.spans.Ended() {
		for _, kv := range s.Attributes() {
			metricKeys[string(kv.Key)] = true
		}
	}
	for _, points := range collectMetrics(t, tt.metrics) {
		for _, p := range points {
			for _, kv := range p.Attributes.ToSlice() {
				metricKeys[string(kv.Key)] = true
			}
		}
	}
	wantMetric := map[string]bool{"http.method": true, "http.route": true, "http.status_class": true, "operation": true}
	for k := range metricKeys {
		if err := CheckLabelAllowlist("metric", k); err != nil {
			t.Errorf("cardinality guard (metric): %v", err)
		}
	}
	for k := range wantMetric {
		if !metricKeys[k] {
			t.Errorf("expected metric label key %q to be emitted, got %v", k, keysOfBool(metricKeys))
		}
	}

	logKeys := map[string]bool{}
	for _, rec := range tt.logs.all() {
		rec.WalkAttributes(func(kv otellog.KeyValue) bool {
			logKeys[kv.Key] = true
			return true
		})
	}
	for k := range logKeys {
		if err := CheckLabelAllowlist("log", k); err != nil {
			t.Errorf("cardinality guard (log): %v", err)
		}
	}
}

// TestCardinalityGuardNegative (§5.2) proves the guard itself bites: a
// user_id label fails the build with the offending key named.
func TestCardinalityGuardNegative(t *testing.T) {
	for _, kind := range []string{"metric", "log"} {
		err := CheckLabelAllowlist(kind, "user_id")
		if err == nil {
			t.Fatalf("expected %s guard to reject user_id", kind)
		}
		if !strings.Contains(err.Error(), "user_id") {
			t.Errorf("expected guard error to name user_id, got %q", err.Error())
		}
	}
	if err := CheckLabelAllowlist("trace", "http.route"); err == nil {
		t.Error("expected unknown label kind to fail closed")
	}
}

// TestSlogBridgeFanout proves stderr is kept (the kept handler still gets
// every record) and OTLP export is additive — including that the bridge is
// a no-op while OTel is disabled.
func TestSlogBridgeFanout(t *testing.T) {
	tt := newTestTelemetry(t)

	keptHandler := &sliceHandler{}
	fanout := FanoutHandler(keptHandler)
	logger := slog.New(fanout)
	logger.Info("hello", "k", "v")
	if len(keptHandler.records) != 1 {
		t.Fatalf("expected kept handler to receive the record, got %d", len(keptHandler.records))
	}
	if records := tt.logs.all(); len(records) != 1 {
		t.Fatalf("expected 1 OTLP record, got %d", len(records))
	}

	// Disabled pipeline: fan-out degrades to the kept handler only.
	otelEnabled.Store(false)
	defer otelEnabled.Store(true)
	before := len(tt.logs.all())
	logger.Info("quiet")
	if len(keptHandler.records) != 2 {
		t.Errorf("expected kept handler to keep receiving, got %d", len(keptHandler.records))
	}
	if got := len(tt.logs.all()); got != before {
		t.Errorf("expected no OTLP export while disabled, got %d new records", got-before)
	}
}

// sliceHandler captures records for fan-out assertions.
type sliceHandler struct {
	mu      sync.Mutex
	records []slog.Record
}

func (h *sliceHandler) Enabled(context.Context, slog.Level) bool { return true }
func (h *sliceHandler) Handle(_ context.Context, r slog.Record) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.records = append(h.records, r.Clone())
	return nil
}
func (h *sliceHandler) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h *sliceHandler) WithGroup(string) slog.Handler      { return h }

func keysOf(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func keysOfBool(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
