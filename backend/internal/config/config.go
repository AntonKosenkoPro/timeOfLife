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
	DatabaseURL          string
	JWTSecret            string
	EmailBackend         string
	Port                 int
	OTPExpiry            time.Duration
	OTPMaxAttempts       int
	OTPEmailTemplate     string
	OTPEmailHTMLTemplate string
	// Token TTLs (zero = compiled defaults below).
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	// HTTP timeouts (zero = compiled defaults below).
	ReadTimeout     time.Duration
	WriteTimeout    time.Duration
	IdleTimeout     time.Duration
	RequestTimeout  time.Duration
	ShutdownTimeout time.Duration
	// AWS SES (real mail sender). Required when EMAIL_BACKEND=ses.
	AWSAccessKeyID     string
	AWSSecretAccessKey string
	AWSRegion          string
	SESFrom            string
	// Sign in with Apple (F2). Optional: empty AppleClientID disables the
	// /auth/apple route and the iOS button. When set, it must be the app's
	// Bundle ID — the `aud` claim Apple puts in the identity token for a
	// native iOS app.
	AppleClientID string
	AppleJWKSURL  string
	// TrustedProxies is a comma-separated list of IPs/CIDRs of reverse proxies
	// that are allowed to set the X-Forwarded-For / X-Real-IP headers used for
	// per-client rate limiting. Empty (default) = trust nobody: forwarded
	// headers are ignored and the direct TCP peer is used. This prevents
	// rate-limit bypass via spoofed headers. (FURPS R1/S5)
	TrustedProxies string
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
		return nil, &configError{msg: "JWT_SECRET must be at least 32 bytes long"}
	}

	// Required: EMAIL_BACKEND
	cfg.EmailBackend = os.Getenv("EMAIL_BACKEND")
	if cfg.EmailBackend == "" {
		return nil, requiredFieldError("EMAIL_BACKEND")
	}
	cfg.EmailBackend = strings.ToLower(cfg.EmailBackend)
	if cfg.EmailBackend != "console" && cfg.EmailBackend != "ses" {
		return nil, invalidFieldError("EMAIL_BACKEND", "console or ses")
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

	// Optional: OTP_EMAIL_TEMPLATE (text body) and OTP_EMAIL_HTML_TEMPLATE (HTML body).
	// When empty, package-level defaults are used.
	cfg.OTPEmailTemplate = os.Getenv("OTP_EMAIL_TEMPLATE")
	cfg.OTPEmailHTMLTemplate = os.Getenv("OTP_EMAIL_HTML_TEMPLATE")

	// Optional: token TTLs (defaults 15m access / 168h refresh).
	var err error
	if cfg.AccessTokenTTL, err = durationOrDefault("ACCESS_TOKEN_TTL", 15*time.Minute); err != nil {
		return nil, err
	}
	if cfg.RefreshTokenTTL, err = durationOrDefault("REFRESH_TOKEN_TTL", 7*24*time.Hour); err != nil {
		return nil, err
	}

	// Optional: HTTP timeouts (defaults match the previous hardcoded values).
	if cfg.ReadTimeout, err = durationOrDefault("HTTP_READ_TIMEOUT", 15*time.Second); err != nil {
		return nil, err
	}
	if cfg.WriteTimeout, err = durationOrDefault("HTTP_WRITE_TIMEOUT", 30*time.Second); err != nil {
		return nil, err
	}
	if cfg.IdleTimeout, err = durationOrDefault("HTTP_IDLE_TIMEOUT", 60*time.Second); err != nil {
		return nil, err
	}
	if cfg.RequestTimeout, err = durationOrDefault("HTTP_REQUEST_TIMEOUT", 30*time.Second); err != nil {
		return nil, err
	}
	if cfg.ShutdownTimeout, err = durationOrDefault("SHUTDOWN_TIMEOUT", 30*time.Second); err != nil {
		return nil, err
	}

	// Optional: AWS SES. Required when EMAIL_BACKEND=ses.
	cfg.AWSAccessKeyID = os.Getenv("AWS_ACCESS_KEY_ID")
	cfg.AWSSecretAccessKey = os.Getenv("AWS_SECRET_ACCESS_KEY")
	cfg.AWSRegion = os.Getenv("AWS_REGION")
	cfg.SESFrom = os.Getenv("SES_FROM")
	if cfg.EmailBackend == "ses" {
		var missing []string
		if cfg.AWSAccessKeyID == "" {
			missing = append(missing, "AWS_ACCESS_KEY_ID")
		}
		if cfg.AWSSecretAccessKey == "" {
			missing = append(missing, "AWS_SECRET_ACCESS_KEY")
		}
		if cfg.AWSRegion == "" {
			missing = append(missing, "AWS_REGION")
		}
		if cfg.SESFrom == "" {
			missing = append(missing, "SES_FROM")
		}
		if len(missing) > 0 {
			return nil, requiredFieldError(strings.Join(missing, ", "))
		}
	}

	// Optional: Sign in with Apple. Empty APPLE_CLIENT_ID leaves verification
	// disabled; the registered /auth/apple route returns 503. When enabled, the
	// Apple identity token's `aud` claim for a native iOS app is the Bundle ID.
	cfg.AppleClientID = os.Getenv("APPLE_CLIENT_ID")
	cfg.AppleJWKSURL = os.Getenv("APPLE_JWKS_URL")
	if cfg.AppleJWKSURL == "" {
		cfg.AppleJWKSURL = "https://appleid.apple.com/auth/keys"
	}

	// Optional: TRUSTED_PROXIES — comma-separated IPs/CIDRs allowed to set
	// forwarded IP headers for rate limiting. Empty = trust nobody.
	cfg.TrustedProxies = os.Getenv("TRUSTED_PROXIES")

	return cfg, nil
}

func requiredFieldError(name string) error {
	return &configError{msg: "required environment variable is not set: " + name}
}

func invalidFieldError(name, expected string) error {
	return &configError{msg: "invalid " + name + ": expected " + expected}
}

// durationOrDefault reads an optional duration env var, falling back to
// def when unset. A present-but-unparseable value is a config error.
func durationOrDefault(name string, def time.Duration) (time.Duration, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return def, nil
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		return 0, invalidFieldError(name, "valid duration (e.g. 15m)")
	}
	return d, nil
}

type configError struct {
	msg string
}

func (e *configError) Error() string { return e.msg }
