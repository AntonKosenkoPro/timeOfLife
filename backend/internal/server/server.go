// Package server provides the HTTP server with chi router and middleware.
package server

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"github.com/antonkosenko/time-of-life/backend/internal/apple"
	"github.com/antonkosenko/time-of-life/backend/internal/auth"
	"github.com/antonkosenko/time-of-life/backend/internal/config"
	"github.com/antonkosenko/time-of-life/backend/internal/db"
	"github.com/antonkosenko/time-of-life/backend/internal/email"
	"github.com/antonkosenko/time-of-life/backend/internal/handlers"
	"github.com/antonkosenko/time-of-life/backend/internal/ratelimit"
)

// Dependencies holds all dependencies for the server.
type Dependencies struct {
	Store          db.Store
	TokenService   *auth.TokenService
	OTPService     *auth.OTPService
	EmailSender    email.Sender
	RateLimiter    *handlers.RateLimiterGroup
	AppleVerifier  apple.Verifier
	HandlerCfg     handlers.HandlerConfig
	RequestTimeout time.Duration
}

// defaultAccessTokenTTL and defaultRefreshTokenTTL mirror the config defaults
// so a literally-constructed Config (tests) behaves like a loaded one.
const (
	defaultAccessTokenTTL  = 15 * time.Minute
	defaultRefreshTokenTTL = 7 * 24 * time.Hour
	defaultRequestTimeout  = 30 * time.Second
)

// NewDefaultDependencies creates a default set of dependencies from config and store.
func NewDefaultDependencies(cfg *config.Config, store db.Store) Dependencies {
	logger := slog.Default()

	accessTTL := cfg.AccessTokenTTL
	if accessTTL <= 0 {
		accessTTL = defaultAccessTokenTTL
	}
	refreshTTL := cfg.RefreshTokenTTL
	if refreshTTL <= 0 {
		refreshTTL = defaultRefreshTokenTTL
	}
	tokenService := auth.NewTokenService(cfg.JWTSecret, accessTTL, refreshTTL)

	otpService := auth.NewOTPService(
		cfg.OTPExpiry,
		cfg.OTPMaxAttempts,
	)

	emailSender, err := email.NewSender(email.SenderConfig{
		Backend:              cfg.EmailBackend,
		AWSAccessKeyID:       cfg.AWSAccessKeyID,
		AWSSecretAccessKey:   cfg.AWSSecretAccessKey,
		AWSRegion:            cfg.AWSRegion,
		SESFrom:              cfg.SESFrom,
		OTPEmailTextTemplate: cfg.OTPEmailTemplate,
		OTPEmailHTMLTemplate: cfg.OTPEmailHTMLTemplate,
		Logger:               logger,
	})
	if err != nil {
		// Explicit fallback: the service stays up on console delivery, but
		// the misconfiguration is surfaced here instead of inside the
		// factory. Fail fast (return error) is the follow-up once
		// EMAIL_BACKEND=ses misconfigurations are proven loud enough.
		logger.Error("email sender misconfigured, using console fallback", "error", err)
	}

	rateLimiter := &handlers.RateLimiterGroup{
		OTPRequest: ratelimit.OTPRequestLimit,
		OTPVerify:  ratelimit.OTPVerifyLimit,
	}

	trustedProxies, err := handlers.ParseTrustedProxies(cfg.TrustedProxies)
	if err != nil {
		// Explicit continue with the safe default (trust nobody): forwarded
		// headers are ignored, so a typo here fails closed for rate
		// limiting rather than open. The raw value is not secret.
		logger.Error("invalid TRUSTED_PROXIES, ignoring forwarded headers",
			"error", err, "value", cfg.TrustedProxies)
	}

	handlerCfg := handlers.HandlerConfig{
		TrustedProxies: trustedProxies,
	}

	// Sign in with Apple is config-gated: only construct the JWKS verifier
	// (and register its route) when APPLE_CLIENT_ID is set.
	var appleVerifier apple.Verifier
	if cfg.AppleClientID != "" {
		v, err := apple.NewVerifier(context.Background(), cfg.AppleClientID, cfg.AppleJWKSURL)
		if err != nil {
			logger.Error("failed to create apple verifier; feature disabled", "error", err)
		} else {
			appleVerifier = v
			rateLimiter.Apple = ratelimit.AppleLimit
		}
	}

	return Dependencies{
		Store:          store,
		TokenService:   tokenService,
		OTPService:     otpService,
		EmailSender:    emailSender,
		RateLimiter:    rateLimiter,
		AppleVerifier:  appleVerifier,
		HandlerCfg:     handlerCfg,
		RequestTimeout: cfg.RequestTimeout,
	}
}

// Server holds the HTTP server and its dependencies.
type Server struct {
	router http.Handler
}

// New creates a new Server with all routes configured.
func New(deps Dependencies) *Server {
	logger := slog.Default()

	h := handlers.NewHandler(
		deps.Store,
		deps.TokenService,
		deps.OTPService,
		deps.EmailSender,
		deps.RateLimiter,
		deps.AppleVerifier,
		deps.HandlerCfg,
		logger,
	)

	s := &Server{}

	r := chi.NewRouter()

	// Middleware
	r.Use(chimw.Recoverer)
	r.Use(chimw.RequestID)
	r.Use(requestLogger)
	r.Use(chimw.Timeout(deps.requestTimeout()))
	r.Use(corsMiddleware)

	// Health check
	r.Get("/health", s.handleHealth)

	// API v1 routes
	r.Route("/api/v1", func(r chi.Router) {
		r.Route("/auth", func(r chi.Router) {
			r.Post("/otp/request", h.RequestOTP)
			r.Post("/otp/verify", h.VerifyOTP)
			r.Post("/refresh", h.RefreshToken)
			// Sign in with Apple is always registered: the handler returns
			// 503 (apple_not_configured) when the verifier is nil, surfacing
			// the contract instead of a 404.
			r.Post("/apple", h.AppleSignIn)
			r.With(h.AuthMiddleware).Post("/logout", h.Logout)
			r.With(h.AuthMiddleware).Get("/me", h.Me)
		})

		// Categories, entries, and deletion tombstones. All protected.
		r.Group(func(r chi.Router) {
			r.Use(h.AuthMiddleware)
			r.Get("/categories", h.ListCategories)
			r.Post("/categories", h.CreateCategory)
			r.Get("/categories/{id}", h.GetCategory)
			r.Patch("/categories/{id}", h.UpdateCategory)
			r.Delete("/categories/{id}", h.DeleteCategory)
			r.Get("/entries", h.ListEntries)
			r.Post("/entries", h.CreateEntry)
			r.Get("/entries/recents", h.ListRecents)
			r.Get("/entries/{id}", h.GetEntry)
			r.Patch("/entries/{id}", h.UpdateEntry)
			r.Delete("/entries/{id}", h.DeleteEntry)
			// Deletion tombstones (cross-device delete propagation).
			r.Get("/deletions", h.ListDeletions)
		})
	})

	s.router = r
	return s
}

// ServeHTTP implements http.Handler.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.router.ServeHTTP(w, r)
}

// requestTimeout resolves the chi request timeout, defaulting for a
// literally-constructed Dependencies (tests) the same way config.Load does.
func (d Dependencies) requestTimeout() time.Duration {
	if d.RequestTimeout <= 0 {
		return defaultRequestTimeout
	}
	return d.RequestTimeout
}

// --- Middleware ---

// requestLogger logs each request using slog.
func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ww := chimw.NewWrapResponseWriter(w, r.ProtoMajor)

		defer func() {
			slog.Info("request",
				"method", r.Method,
				"path", r.URL.Path,
				"status", ww.Status(),
				"duration", time.Since(start).String(),
				"remote", r.RemoteAddr,
				"request_id", chimw.GetReqID(r.Context()),
			)
		}()

		next.ServeHTTP(ww, r)
	})
}

// corsMiddleware allows development origins.
//
// NOTE (residual risk, follow-up candidate): any presented Origin is
// reflected with Allow-Credentials, so any website can make credentialed
// calls. The proper fix is an allowlist from config. The one combo changed
// here is the missing-Origin case: "*" is no longer paired with
// Allow-Credentials (browsers reject that combo outright).
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		} else {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Add("Vary", "Origin")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// --- Health ---

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}
