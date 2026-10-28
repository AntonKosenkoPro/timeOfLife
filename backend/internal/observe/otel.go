// Package observe — OTel pipeline (observability Stage 1).
//
// InitOTel wires traces, metrics, and the slog→OTLP log bridge to the
// VM-local Collector. It mirrors the SENTRY_DSN empty-means-off contract:
// OTel stays fully disabled unless OTEL_ENABLED=1 AND
// OTEL_EXPORTER_OTLP_ENDPOINT is set, in which case the default posture is
// exactly Stage 0 (no spans, no request metrics, no OTLP log export).
//
// HTTP instrumentation reuses the Stage-0 templating (routeTemplate() /
// operationForRoute()) — never raw paths with IDs. The middleware order is
// Recoverer → observe.Middleware (Sentry + OTel span start) → RequestID →
// requestLogger → Timeout → CORS; /health skips span creation, stays out of
// access logs (server.go), and contributes no per-request metric series — a
// single health-check series (no per-request labels) increments instead.
//
// Loki labels stay ~5 boring keys (D3): service.name and
// deployment.environment.name arrive as resource attributes (environment is
// injected by the Collector's resource processor, not by app code); the
// bridge emits only level (+ operation on the error stream only,
// trace_id/span_id for trace↔log jumps, and a single fields payload).
// Identifiers (user_id, device_id), tokens, emails, entry text, and category
// names ride inside payloads only — never as metric/log labels (R1). The
// closed key sets live in MetricLabelAllowlist / LogLabelAllowlist and are
// enforced by CI (CheckLabelAllowlist + the cardinality-guard test).
package observe

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	otlploggrpc "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	otlpmetricgrpc "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace"
	otlptracegrpc "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	otellog "go.opentelemetry.io/otel/log"
	"go.opentelemetry.io/otel/metric"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/trace/noop"
)

// otelScopeName identifies this instrumentation in all three signals.
const otelScopeName = "github.com/antonkosenko/time-of-life/backend/internal/observe"

// MetricLabelAllowlist is the closed set of attribute keys the OTel
// middleware may attach to metrics. CI fails on any other key.
var MetricLabelAllowlist = []string{"http.method", "http.route", "http.status_class", "operation"}

// LogLabelAllowlist is the closed set of attribute keys the slog→OTLP bridge
// may emit. service.name / deployment.environment.name travel as resource
// attributes (not record attributes); everything else from the slog record
// folds into the single fields payload. CI fails on any other key.
var LogLabelAllowlist = []string{"level", "operation", "trace_id", "span_id", "fields"}

// CheckLabelAllowlist reports whether key may be used on kind
// ("metric" or "log"). Unknown kinds and unknown keys fail closed with the
// offending key named, so the cardinality-guard test (and any future
// admission check) names exactly what broke the build.
func CheckLabelAllowlist(kind, key string) error {
	var allow []string
	switch kind {
	case "metric":
		allow = MetricLabelAllowlist
	case "log":
		allow = LogLabelAllowlist
	default:
		return fmt.Errorf("observability: unknown label kind %q (want metric or log)", kind)
	}
	for _, k := range allow {
		if k == key {
			return nil
		}
	}
	return fmt.Errorf("observability: unknown %s label key %q (not in allowlist)", kind, key)
}

// OTelConfig carries the Stage-1 env plumbing. Enabled is OTEL_ENABLED;
// Endpoint is OTEL_EXPORTER_OTLP_ENDPOINT (the VM-local Collector OTLP/gRPC
// address). ServiceVersion is the stamped build identity.
type OTelConfig struct {
	Enabled        bool
	Endpoint       string
	ServiceName    string
	ServiceVersion string
}

// otelEnabled reports whether the OTel pipeline is active.
var otelEnabled atomic.Bool

// OTelEnabled reports whether OTel tracing/metrics/log-export is active.
func OTelEnabled() bool {
	return otelEnabled.Load()
}

// otelHealthCount backs the single health-check series (no per-request
// labels): /health increments it instead of emitting per-request telemetry.
var otelHealthCount atomic.Int64

// Package-level instruments, installed by initTelemetry. The tracer and
// logger default to global no-ops so the middleware and bridge are safe
// before init; the counter stays nil until instruments exist (it is only
// touched on the enabled path).
var (
	otelTracer         trace.Tracer = noop.NewTracerProvider().Tracer(otelScopeName)
	httpRequestCounter metric.Int64Counter
	otelLogger         otellog.Logger
	otelShutdownFn     func(context.Context) error
)

// InitOTel initializes the OTel pipeline: OTLP/gRPC exporters to the local
// Collector, trace + meter + logger providers, and the slog fan-out bridge.
// Empty endpoint (or Enabled=false) is a no-op returning nil — the server
// runs exactly as Stage 0. Exporter construction failure is non-fatal to the
// caller contract: it returns the error so main.go can log it and continue
// without OTel.
func InitOTel(cfg OTelConfig) error {
	endpoint := cfg.Endpoint
	if !cfg.Enabled || endpoint == "" {
		return nil
	}
	name := cfg.ServiceName
	if name == "" {
		name = sentryServiceName
	}
	ctx := context.Background()
	custom, err := resource.New(ctx,
		resource.WithAttributes(
			attribute.String("service.name", name),
			attribute.String("service.version", cfg.ServiceVersion),
		),
	)
	if err != nil {
		return fmt.Errorf("otel: resource: %w", err)
	}
	// Custom attributes win on service.name; the default contributes the
	// telemetry.sdk.* identification only.
	res, err := resource.Merge(resource.Default(), custom)
	if err != nil {
		return fmt.Errorf("otel: resource: %w", err)
	}

	traceExp, err := newTraceExporter(ctx, endpoint)
	if err != nil {
		return fmt.Errorf("otel: trace exporter: %w", err)
	}
	metricExp, err := newMetricExporter(ctx, endpoint)
	if err != nil {
		return fmt.Errorf("otel: metric exporter: %w", errors.Join(err, traceExp.Shutdown(ctx)))
	}
	logExp, err := newLogExporter(ctx, endpoint)
	if err != nil {
		return fmt.Errorf("otel: log exporter: %w", errors.Join(err, traceExp.Shutdown(ctx), metricExp.Shutdown(ctx)))
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExp),
		sdktrace.WithResource(res),
	)
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExp,
			sdkmetric.WithInterval(30*time.Second))),
		sdkmetric.WithResource(res),
	)
	lp := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExp)),
		sdklog.WithResource(res),
	)
	if err := initTelemetry(tp, mp, lp); err != nil {
		return err
	}
	otelShutdownFn = func(ctx context.Context) error {
		return errors.Join(tp.Shutdown(ctx), mp.Shutdown(ctx), lp.Shutdown(ctx))
	}
	// Fan-out: the existing stderr/stdout handler stays the lifeline during
	// migration; OTLP export is additive until dashboards prove parity.
	BridgeSlog()
	return nil
}

// ShutdownOTel flushes and shuts down the OTel providers. It is a no-op when
// OTel was never enabled.
func ShutdownOTel(ctx context.Context) error {
	if !otelEnabled.Load() || otelShutdownFn == nil {
		return nil
	}
	return otelShutdownFn(ctx)
}

// initTelemetry installs already-built providers and creates the
// instruments. Production passes OTLP-backed providers via InitOTel; tests
// pass in-memory ones. It returns an error only for invalid instrument
// definitions (a programming bug, not a runtime condition).
// grpcEndpointOpts accepts a bare host:port (compose default) or a URL
// (the shape operators copy from OTel docs): a scheme selects WithEndpointURL,
// otherwise WithEndpoint. Plain-HTTP URLs stay insecure (the Collector serves
// plaintext OTLP; TLS terminates at nginx on 443).
func traceEndpointOpts(endpoint string) []otlptracegrpc.Option {
	if strings.HasPrefix(endpoint, "http://") || strings.HasPrefix(endpoint, "https://") {
		return []otlptracegrpc.Option{otlptracegrpc.WithEndpointURL(endpoint)}
	}
	return []otlptracegrpc.Option{otlptracegrpc.WithEndpoint(endpoint), otlptracegrpc.WithInsecure()}
}

func metricEndpointOpts(endpoint string) []otlpmetricgrpc.Option {
	if strings.HasPrefix(endpoint, "http://") || strings.HasPrefix(endpoint, "https://") {
		return []otlpmetricgrpc.Option{otlpmetricgrpc.WithEndpointURL(endpoint)}
	}
	return []otlpmetricgrpc.Option{otlpmetricgrpc.WithEndpoint(endpoint), otlpmetricgrpc.WithInsecure()}
}

func logEndpointOpts(endpoint string) []otlploggrpc.Option {
	if strings.HasPrefix(endpoint, "http://") || strings.HasPrefix(endpoint, "https://") {
		return []otlploggrpc.Option{otlploggrpc.WithEndpointURL(endpoint)}
	}
	return []otlploggrpc.Option{otlploggrpc.WithEndpoint(endpoint), otlploggrpc.WithInsecure()}
}

func newTraceExporter(ctx context.Context, endpoint string) (*otlptrace.Exporter, error) {
	return otlptracegrpc.New(ctx, traceEndpointOpts(endpoint)...)
}

func newMetricExporter(ctx context.Context, endpoint string) (*otlpmetricgrpc.Exporter, error) {
	return otlpmetricgrpc.New(ctx, metricEndpointOpts(endpoint)...)
}

func newLogExporter(ctx context.Context, endpoint string) (*otlploggrpc.Exporter, error) {
	return otlploggrpc.New(ctx, logEndpointOpts(endpoint)...)
}

// initTelemetry installs already-built providers and creates the
// instruments. Production passes OTLP-backed providers via InitOTel; tests
// pass in-memory ones. It returns an error only for invalid instrument
// definitions (a programming bug, not a runtime condition).
func initTelemetry(tp *sdktrace.TracerProvider, mp *sdkmetric.MeterProvider, lp *sdklog.LoggerProvider) error {
	otelTracer = tp.Tracer(otelScopeName)
	meter := mp.Meter(otelScopeName)
	counter, err := meter.Int64Counter("http.server.requests",
		metric.WithDescription("Count of HTTP requests by templated route and outcome."),
		metric.WithUnit("{request}"),
	)
	if err != nil {
		return fmt.Errorf("otel: request counter: %w", err)
	}
	health, err := meter.Int64ObservableCounter("lifio.health.checks",
		metric.WithDescription("Count of /health requests served (single series, no per-request labels)."),
		metric.WithUnit("{request}"),
	)
	if err != nil {
		return fmt.Errorf("otel: health counter: %w", err)
	}
	if _, err := meter.RegisterCallback(func(_ context.Context, o metric.Observer) error {
		o.ObserveInt64(health, otelHealthCount.Load())
		return nil
	}, health); err != nil {
		return fmt.Errorf("otel: health callback: %w", err)
	}
	httpRequestCounter = counter
	otelLogger = lp.Logger(otelScopeName)
	otelEnabled.Store(true)
	return nil
}

// boundedMethod normalizes the HTTP method for labels: known verbs pass
// through, anything else (scanner tokens, garbage) becomes "HTTP" — the
// same fallback the OTel semconv server helper uses — so the method label
// can never explode series cardinality. Route and operation are already
// bounded (templated route / closed operation map).
func boundedMethod(method string) string {
	switch method {
	case http.MethodGet, http.MethodPost, http.MethodPut, http.MethodPatch,
		http.MethodDelete, http.MethodHead, http.MethodOptions, http.MethodTrace,
		http.MethodConnect:
		return method
	default:
		return "HTTP"
	}
}

// otelRequestAttrs builds the span-start attributes. Only http.method is
// known before routing (chi matches the route inside next.ServeHTTP); the
// templated route, status class, and operation land in finishOTelSpan once
// the WrapResponseWriter has seen the outcome.
func otelRequestAttrs(r *http.Request) []attribute.KeyValue {
	return []attribute.KeyValue{attribute.String("http.method", boundedMethod(r.Method))}
}

// finishOTelSpan completes a server span after the handler ran: it fixes the
// span name to "{method} {route template}" (the only reliable fixed-name
// path — routeTemplate() over chi.RouteContext), attaches the allowlisted
// attributes, marks 5xx, and records the request counter. All attribute keys
// come from MetricLabelAllowlist — never identifiers. The method is bounded
// (see boundedMethod) so scanner traffic cannot mint new series.
func finishOTelSpan(span trace.Span, r *http.Request, status int) {
	method := boundedMethod(r.Method)
	pattern := routeTemplate(r)
	op := operationForRoute(r.Method, pattern)
	class := statusClass(status)
	span.SetName(method + " " + pattern)
	span.SetAttributes(
		attribute.String("http.method", method),
		attribute.String("http.route", pattern),
		attribute.String("http.status_class", class),
		attribute.String("operation", op),
	)
	if status >= 500 {
		span.SetStatus(codes.Error, fmt.Sprintf("HTTP %d", status))
	}
	if httpRequestCounter == nil {
		return
	}
	httpRequestCounter.Add(r.Context(), 1, metric.WithAttributes(
		attribute.String("http.method", method),
		attribute.String("http.route", pattern),
		attribute.String("http.status_class", class),
		attribute.String("operation", op),
	))
}

// otlpHandler is the slog→OTLP bridge: it converts each record to an OTel
// log record on the provider installed by initTelemetry. Attribute keys are
// exactly LogLabelAllowlist; trace/span correlation rides as trace_id/span_id
// attributes taken from the in-flight span context, and everything else
// folds into the single fields JSON payload.
type otlpHandler struct {
	logger otellog.Logger
	attrs  []slog.Attr
	prefix string
}

// Enabled gates on the pipeline, not the level: once enabled the bridge
// forwards every record that reaches it (fan-out decides overall level via
// the kept handler), so error-stream promotion and trace correlation apply
// uniformly during migration.
func (h *otlpHandler) Enabled(context.Context, slog.Level) bool {
	return otelEnabled.Load() && h.logger != nil
}

// Handle converts the slog record: fixed label keys only, identifiers stay
// in the fields payload.
func (h *otlpHandler) Handle(ctx context.Context, rec slog.Record) error {
	if !h.Enabled(ctx, rec.Level) {
		return nil
	}
	var lr otellog.Record
	lr.SetTimestamp(rec.Time)
	lr.SetObservedTimestamp(time.Now())
	lr.SetSeverity(slogToOTelSeverity(rec.Level))
	lr.SetSeverityText(rec.Level.String())
	lr.SetBody(otellog.StringValue(rec.Message))

	attrs := []otellog.KeyValue{otellog.String("level", rec.Level.String())}
	if sc := trace.SpanContextFromContext(ctx); sc.IsValid() {
		attrs = append(attrs,
			otellog.String("trace_id", sc.TraceID().String()),
			otellog.String("span_id", sc.SpanID().String()),
		)
	}
	fields := make(map[string]any)
	var operation string
	hasOperation := false
	collect := func(key string, v slog.Value) {
		v = v.Resolve()
		if key == "operation" || key == "op" {
			if s, ok := v.Any().(string); ok {
				operation, hasOperation = s, true
			}
		}
		fields[key] = slogValueForPayload(v)
	}
	for _, a := range h.attrs {
		// Already prefixed at bind time (WithAttrs snapshots h.prefix then),
		// so use the key as-is: re-prefixing here would double-apply groups
		// (g.g.k) and drag pre-group attrs into later groups.
		collect(a.Key, a.Value)
	}
	rec.Attrs(func(a slog.Attr) bool {
		collectGroup(h.prefix, a, collect)
		return true
	})
	// operation rides as a label on the error stream only (bounded values);
	// below Error it stays inside the fields payload.
	if rec.Level >= slog.LevelError && hasOperation {
		attrs = append(attrs, otellog.String("operation", operation))
	}
	if len(fields) > 0 {
		if b, err := json.Marshal(fields); err == nil {
			attrs = append(attrs, otellog.String("fields", string(b)))
		}
	}
	lr.AddAttributes(attrs...)
	h.logger.Emit(ctx, lr)
	return nil
}

// collectGroup flattens slog groups with dot prefixes so group structure
// survives inside the single fields payload without new label keys.
func collectGroup(prefix string, a slog.Attr, collect func(string, slog.Value)) {
	if a.Value.Kind() == slog.KindGroup {
		for _, sub := range a.Value.Group() {
			collectGroup(prefix+a.Key+".", sub, collect)
		}
		return
	}
	collect(prefix+a.Key, a.Value)
}

// slogValueForPayload converts a resolved slog value to JSON-marshalable
// form: primitives pass through, times/durations keep their shape, errors
// become strings, and anything else falls back to its %v rendering so a
// exotic value can never fail the marshal. Long strings are bounded (driver
// errors can echo unbounded request input — same truncation as Sentry).
func slogValueForPayload(v slog.Value) any {
	switch v.Kind() {
	case slog.KindString:
		return truncateSentryMessage(v.String())
	case slog.KindInt64:
		return v.Int64()
	case slog.KindUint64:
		return v.Uint64()
	case slog.KindFloat64:
		return v.Float64()
	case slog.KindBool:
		return v.Bool()
	case slog.KindDuration:
		return v.Duration().String()
	case slog.KindTime:
		return v.Time()
	case slog.KindAny:
		a := v.Any()
		if err, ok := a.(error); ok {
			return truncateSentryMessage(err.Error())
		}
		if b, err := json.Marshal(a); err == nil {
			var back any
			if err := json.Unmarshal(b, &back); err == nil {
				return back
			}
		}
		return truncateSentryMessage(fmt.Sprintf("%v", a))
	default:
		return truncateSentryMessage(fmt.Sprintf("%v", v.Any()))
	}
}

// slogToOTelSeverity maps slog levels onto OTel severities.
func slogToOTelSeverity(l slog.Level) otellog.Severity {
	switch {
	case l < slog.LevelDebug:
		return otellog.SeverityTrace
	case l < slog.LevelInfo:
		return otellog.SeverityDebug
	case l < slog.LevelWarn:
		return otellog.SeverityInfo
	case l < slog.LevelError:
		return otellog.SeverityWarn
	default:
		return otellog.SeverityError
	}
}

// WithAttrs returns a handler with pre-formatted attrs merged at Handle.
func (h *otlpHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	cp := *h
	prefixed := make([]slog.Attr, 0, len(h.attrs)+len(attrs))
	prefixed = append(prefixed, h.attrs...)
	for _, a := range attrs {
		a.Key = h.prefix + a.Key
		prefixed = append(prefixed, a)
	}
	cp.attrs = prefixed
	return &cp
}

// WithGroup returns a handler prefixing subsequent keys with name+".".
func (h *otlpHandler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}
	cp := *h
	cp.prefix = h.prefix + name + "."
	return &cp
}

// fanoutHandler keeps the existing stderr/stdout handler as the lifeline
// during migration and adds OTLP export. Enabled is the union so the bridge
// sees every record the kept handler would drop for level reasons.
type fanoutHandler struct {
	kept slog.Handler
	otlp *otlpHandler
}

// FanoutHandler combines kept (stderr/stdout lifeline) with the OTLP bridge.
func FanoutHandler(kept slog.Handler) slog.Handler {
	return &fanoutHandler{kept: kept, otlp: &otlpHandler{logger: otelLogger}}
}

// Enabled reports the union: a record flows if either side wants it.
func (f *fanoutHandler) Enabled(ctx context.Context, l slog.Level) bool {
	return f.kept.Enabled(ctx, l) || f.otlp.Enabled(ctx, l)
}

// Handle writes to both sides; OTLP failure never drops the stderr line.
// Each side is gated on its own Enabled: the stdlib contract only calls
// Handle when Enabled is true, and the kept handler (Level: Info) must not
// inherit the bridge's always-true gate, or sub-Info records would print.
func (f *fanoutHandler) Handle(ctx context.Context, rec slog.Record) error {
	var keptErr error
	if f.kept.Enabled(ctx, rec.Level) {
		keptErr = f.kept.Handle(ctx, rec)
	}
	return errors.Join(keptErr, f.otlp.Handle(ctx, rec))
}

// WithAttrs fans out to both handlers.
func (f *fanoutHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &fanoutHandler{kept: f.kept.WithAttrs(attrs), otlp: f.otlp.WithAttrs(attrs).(*otlpHandler)}
}

// WithGroup fans out to both handlers.
func (f *fanoutHandler) WithGroup(name string) slog.Handler {
	return &fanoutHandler{kept: f.kept.WithGroup(name), otlp: f.otlp.WithGroup(name).(*otlpHandler)}
}

// BridgeSlog installs the fan-out as the process default: the current
// default handler is kept, OTLP export is added. Call once, after InitOTel.
func BridgeSlog() {
	slog.SetDefault(slog.New(FanoutHandler(slog.Default().Handler())))
}
