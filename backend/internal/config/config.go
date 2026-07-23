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
	MailgunDomain        string
	MailgunAPIKey        string
	MailgunFrom          string
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
		panic("JWT_SECRET must be at least 32 bytes long")
	}

	// Required: EMAIL_BACKEND
	cfg.EmailBackend = os.Getenv("EMAIL_BACKEND")
	if cfg.EmailBackend == "" {
		return nil, requiredFieldError("EMAIL_BACKEND")
	}
	cfg.EmailBackend = strings.ToLower(cfg.EmailBackend)
	if cfg.EmailBackend != "console" && cfg.EmailBackend != "mailgun" && cfg.EmailBackend != "ses" {
		return nil, invalidFieldError("EMAIL_BACKEND", "console, mailgun or ses")
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

	// Optional: MAILGUN_DOMAIN, MAILGUN_API_KEY, MAILGUN_FROM.
	cfg.MailgunDomain = os.Getenv("MAILGUN_DOMAIN")
	cfg.MailgunAPIKey = os.Getenv("MAILGUN_API_KEY")
	cfg.MailgunFrom = os.Getenv("MAILGUN_FROM")

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

	// Optional: Sign in with Apple. Empty APPLE_CLIENT_ID leaves the feature
	// disabled (the /auth/apple route is not registered). When enabled, the
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
