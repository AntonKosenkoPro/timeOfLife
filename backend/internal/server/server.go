// Package server provides the HTTP server with chi router and middleware.
package server

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
	"github.com/antonkosenko/time-of-life/backend/internal/config"
	"github.com/antonkosenko/time-of-life/backend/internal/db"
	"github.com/antonkosenko/time-of-life/backend/internal/email"
	"github.com/antonkosenko/time-of-life/backend/internal/handlers"
	"github.com/antonkosenko/time-of-life/backend/internal/ratelimit"
)

// Dependencies holds all dependencies for the server.
type Dependencies struct {
	Store        db.Store
	TokenService *auth.TokenService
	OTPService   *auth.OTPService
	EmailSender  email.Sender
	RateLimiter  *handlers.RateLimiterGroup
	HandlerCfg   handlers.HandlerConfig
}

// NewDefaultDependencies creates a default set of dependencies from config and store.
func NewDefaultDependencies(cfg *config.Config, store db.Store) Dependencies {
	logger := slog.Default()

	tokenService := auth.NewTokenService(
		cfg.JWTSecret,
		15*time.Minute, // access token TTL
		7*24*time.Hour, // refresh token TTL
	)

	otpService := auth.NewOTPService(
		cfg.OTPExpiry,
		cfg.OTPMaxAttempts,
	)

	emailSender := email.NewSender(logger)

	rateLimiter := &handlers.RateLimiterGroup{
		OTPRequest: ratelimit.OTPRequestLimit,
		OTPVerify:  ratelimit.OTPVerifyLimit,
	}

	handlerCfg := handlers.HandlerConfig{
		AppURL: "timeoflife://",
	}

	return Dependencies{
		Store:        store,
		TokenService: tokenService,
		OTPService:   otpService,
		EmailSender:  emailSender,
		RateLimiter:  rateLimiter,
		HandlerCfg:   handlerCfg,
	}
}

// Server holds the HTTP server and its dependencies.
type Server struct {
	router  http.Handler
	handler *handlers.Handler
}

// New creates a new Server with all routes configured.
func New(_ *config.Config, deps Dependencies) *Server {
	logger := slog.Default()

	h := handlers.NewHandler(
		deps.Store,
		deps.TokenService,
		deps.OTPService,
		deps.EmailSender,
		deps.RateLimiter,
		deps.HandlerCfg,
		logger,
	)

	s := &Server{
		handler: h,
	}

	r := chi.NewRouter()

	// Middleware
	r.Use(chimw.Recoverer)
	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(requestLogger)
	r.Use(chimw.Timeout(30 * time.Second))
	r.Use(corsMiddleware)

	// Health check
	r.Get("/health", s.handleHealth)

	// API v1 routes
	r.Route("/api/v1", func(r chi.Router) {
		r.Route("/auth", func(r chi.Router) {
			r.Post("/otp/request", h.RequestOTP)
			r.Post("/otp/verify", h.VerifyOTP)
			r.Post("/refresh", h.RefreshToken)
			r.With(h.AuthMiddleware).Post("/logout", h.Logout)
			r.With(h.AuthMiddleware).Get("/me", h.Me)
		})
	})

	s.router = r
	return s
}

// ServeHTTP implements http.Handler.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.router.ServeHTTP(w, r)
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
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" {
			origin = "*"
		}

		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Credentials", "true")

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
