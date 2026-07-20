// Package config loads application configuration from environment variables.
package config

import (
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

// Config holds all application configuration.
type Config struct {
	DatabaseURL      string
	JWTSecret        string
	EmailBackend     string
	Port             int
	OTPExpiry        time.Duration
	OTPMaxAttempts   int
	OTPEmailTemplate string
	MailgunDomain    string
	MailgunAPIKey    string
}

// Load reads configuration from environment variables.
// It attempts to load .env first (non-fatal if missing).
func Load() (*Config, error) {
	// Best-effort load of .env file
	_ = godotenv.Load()

	cfg := &Config{}

	// Required: DATABASE_URL
	cfg.DatabaseURL = os.Getenv("DATABASE_URL")
	if cfg.DatabaseURL == "" {
		return nil, requiredFieldError("DATABASE_URL")
	}

	// Required: JWT_SECRET
	cfg.JWTSecret = os.Getenv("JWT_SECRET")
	if cfg.JWTSecret == "" {
		return nil, requiredFieldError("JWT_SECRET")
	}
	if len(cfg.JWTSecret) < 32 {
		panic("JWT_SECRET must be at least 32 bytes long")
	}

	// Required: EMAIL_BACKEND
	cfg.EmailBackend = os.Getenv("EMAIL_BACKEND")
	if cfg.EmailBackend == "" {
		return nil, requiredFieldError("EMAIL_BACKEND")
	}
	cfg.EmailBackend = strings.ToLower(cfg.EmailBackend)
	if cfg.EmailBackend != "console" && cfg.EmailBackend != "mailgun" {
		return nil, invalidFieldError("EMAIL_BACKEND", "console or mailgun")
	}

	// Optional: PORT (default 8080)
	portStr := os.Getenv("PORT")
	if portStr == "" {
		cfg.Port = 8080
	} else {
		p, err := strconv.Atoi(portStr)
		if err != nil {
			return nil, invalidFieldError("PORT", "valid integer")
		}
		cfg.Port = p
	}

	// Optional: OTP_EXPIRY (default 10m)
	expiryStr := os.Getenv("OTP_EXPIRY")
	if expiryStr == "" {
		cfg.OTPExpiry = 10 * time.Minute
	} else {
		d, err := time.ParseDuration(expiryStr)
		if err != nil {
			return nil, invalidFieldError("OTP_EXPIRY", "valid duration (e.g. 10m)")
		}
		cfg.OTPExpiry = d
	}

	// Optional: OTP_MAX_ATTEMPTS (default 5)
	attemptsStr := os.Getenv("OTP_MAX_ATTEMPTS")
	if attemptsStr == "" {
		cfg.OTPMaxAttempts = 5
	} else {
		a, err := strconv.Atoi(attemptsStr)
		if err != nil || a < 1 {
			return nil, invalidFieldError("OTP_MAX_ATTEMPTS", "positive integer")
		}
		cfg.OTPMaxAttempts = a
	}

	// Optional: OTP_EMAIL_TEMPLATE
	cfg.OTPEmailTemplate = os.Getenv("OTP_EMAIL_TEMPLATE")

	// Optional: MAILGUN_DOMAIN, MAILGUN_API_KEY
	cfg.MailgunDomain = os.Getenv("MAILGUN_DOMAIN")
	cfg.MailgunAPIKey = os.Getenv("MAILGUN_API_KEY")

	return cfg, nil
}

func requiredFieldError(name string) error {
	return &configError{field: name, msg: "required environment variable is not set: " + name}
}

func invalidFieldError(name, expected string) error {
	return &configError{field: name, msg: "invalid " + name + ": expected " + expected}
}

type configError struct {
	field string
	msg   string
}

func (e *configError) Error() string { return e.msg }
