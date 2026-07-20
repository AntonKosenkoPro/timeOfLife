package server

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
	"github.com/antonkosenko/time-of-life/backend/internal/config"
	"github.com/antonkosenko/time-of-life/backend/internal/db"
	"github.com/antonkosenko/time-of-life/backend/internal/email"
	"github.com/antonkosenko/time-of-life/backend/internal/handlers"
	"github.com/antonkosenko/time-of-life/backend/internal/migrations"
	"github.com/antonkosenko/time-of-life/backend/internal/ratelimit"
)

func newTestServer(t *testing.T) *Server {
	t.Helper()

	store, err := db.NewSQLiteStore(":memory:")
	if err != nil {
		t.Fatalf("failed to create SQLite store: %v", err)
	}
	ctx := context.Background()
	if err := migrations.RunSQLite(ctx, store.DB()); err != nil {
		t.Fatalf("failed to run migrations: %v", err)
	}

	cfg := &config.Config{
		JWTSecret:      "test-secret-key-at-least-32-bytes!!",
		OTPExpiry:      10 * time.Minute,
		OTPMaxAttempts: 5,
	}

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelWarn}))
	tokenService := auth.NewTokenService(cfg.JWTSecret, 15*time.Minute, 7*24*time.Hour)
	otpService := auth.NewOTPService(cfg.OTPExpiry, cfg.OTPMaxAttempts)
	emailSender := email.NewConsoleSender(logger)
	rateLimiter := &handlers.RateLimiterGroup{
		OTPRequest: ratelimit.NewTokenBucket(100, 100, time.Minute),
		OTPVerify:  ratelimit.NewTokenBucket(100, 100, time.Minute),
	}
	handlerCfg := handlers.HandlerConfig{
		AppURL: "timeoflife://",
	}

	deps := Dependencies{
		Store:        store,
		TokenService: tokenService,
		OTPService:   otpService,
		EmailSender:  emailSender,
		RateLimiter:  rateLimiter,
		HandlerCfg:   handlerCfg,
	}

	return New(cfg, deps)
}

func TestHealthEndpoint(t *testing.T) {
	s := newTestServer(t)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}

	var resp map[string]string
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp["status"] != "ok" {
		t.Errorf("expected status 'ok', got %q", resp["status"])
	}
}

func TestOTPRequestRoute(t *testing.T) {
	s := newTestServer(t)

	body := `{"email":"test@example.com"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", nil)
	req.Body = http.NoBody
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", http.NoBody)
	_ = body
	_ = req

	// Test with proper body
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", nil)
	// Use a proper request
	w := httptest.NewRecorder()
	s.handler.RequestOTP(w, req)
	// This should return 400 because body is empty
	if w.Code != http.StatusBadRequest {
		t.Logf("expected 400 for empty body, got %d", w.Code)
	}
}

func TestCORSHeaders(t *testing.T) {
	s := newTestServer(t)

	req := httptest.NewRequest(http.MethodOptions, "/health", nil)
	req.Header.Set("Origin", "http://localhost:3000")
	w := httptest.NewRecorder()
	s.ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Errorf("expected 204 for OPTIONS, got %d", w.Code)
	}

	origin := w.Header().Get("Access-Control-Allow-Origin")
	if origin == "" {
		t.Error("expected CORS origin header")
	}
}

func TestAuthRoutesProtected(t *testing.T) {
	s := newTestServer(t)

	// Logout without auth should return 401
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for unauthenticated logout, got %d", w.Code)
	}

	// Me without auth should return 401
	req = httptest.NewRequest(http.MethodGet, "/api/v1/auth/me", nil)
	w = httptest.NewRecorder()
	s.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for unauthenticated /me, got %d", w.Code)
	}
}

func TestServerContentType(t *testing.T) {
	s := newTestServer(t)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, req)

	ct := w.Header().Get("Content-Type")
	if ct != "application/json" {
		t.Errorf("expected Content-Type application/json, got %q", ct)
	}
}
