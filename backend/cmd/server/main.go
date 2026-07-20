// Command server is the entry point for the Time of Life backend API server.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/antonkosenko/time-of-life/backend/internal/config"
	"github.com/antonkosenko/time-of-life/backend/internal/db"
	"github.com/antonkosenko/time-of-life/backend/internal/migrations"
	"github.com/antonkosenko/time-of-life/backend/internal/server"
)

func main() {
	os.Exit(run())
}

func run() int {
	// Set up structured logging
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})))

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		slog.Error("failed to load configuration", "error", err)
		return 1
	}

	slog.Info("configuration loaded",
		"port", cfg.Port,
		"email_backend", cfg.EmailBackend,
		"otp_expiry", cfg.OTPExpiry.String(),
		"otp_max_attempts", cfg.OTPMaxAttempts,
	)

	// Create database store
	ctx := context.Background()

	store, err := db.NewPostgresStore(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		return 1
	}
	defer func() {
		if err := store.Close(); err != nil {
			slog.Error("failed to close database connection", "error", err)
		}
	}()

	slog.Info("connected to database")

	// Run migrations
	if err := migrations.RunPostgres(ctx, store.Pool()); err != nil {
		slog.Error("failed to run migrations", "error", err)
		return 1
	}

	slog.Info("migrations applied successfully")

	// Create dependencies and server
	deps := server.NewDefaultDependencies(cfg, store)
	srv := server.New(cfg, deps)

	// Create HTTP server
	httpServer := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Port),
		Handler:      srv,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in a goroutine
	go func() {
		slog.Info("starting server", "addr", httpServer.Addr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	// Wait for shutdown signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit

	slog.Info("shutting down server", "signal", sig.String())

	// Graceful shutdown with timeout
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		slog.Error("server forced to shutdown", "error", err)
		return 1
	}

	slog.Info("server stopped gracefully")
	return 0
}
