// Package email provides an interface and implementations for sending OTP emails.
package email

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"text/template"
)

// Sender sends OTP emails to users.
type Sender interface {
	SendOTP(ctx context.Context, to, code, magicLink string) error
}

// ConsoleSender prints OTP emails to stdout (for development/testing).
type ConsoleSender struct {
	logger *slog.Logger
}

// NewConsoleSender creates a new ConsoleSender.
func NewConsoleSender(logger *slog.Logger) *ConsoleSender {
	return &ConsoleSender{logger: logger}
}

// SendOTP prints the OTP email to stdout.
func (s *ConsoleSender) SendOTP(_ context.Context, to, code, magicLink string) error {
	// The code MUST be on its own line for iOS .oneTimeCode autofill detection.
	msg := fmt.Sprintf("To: %s\nYour code:\n%s\n\nMagic link: %s\n", to, code, magicLink)
	s.logger.Info("sending OTP email", "to", to)
	fmt.Print(msg)
	return nil
}

// MailgunSender sends OTP emails via the Mailgun API.
type MailgunSender struct {
	apiKey      string
	domain      string
	from        string
	templateStr string
	tmpl        *template.Template
	client      *http.Client
	logger      *slog.Logger
}

// MailgunSenderConfig holds configuration for MailgunSender.
type MailgunSenderConfig struct {
	APIKey      string
	Domain      string
	From        string
	TemplateStr string
	Logger      *slog.Logger
}

// NewMailgunSender creates a new MailgunSender.
func NewMailgunSender(cfg MailgunSenderConfig) (*MailgunSender, error) {
	templateStr := cfg.TemplateStr
	if templateStr == "" {
		templateStr = defaultOTPTemplate
	}

	tmpl, err := template.New("otp").Parse(templateStr)
	if err != nil {
		return nil, fmt.Errorf("parse OTP email template: %w", err)
	}

	return &MailgunSender{
		apiKey:      cfg.APIKey,
		domain:      cfg.Domain,
		from:        cfg.From,
		templateStr: templateStr,
		tmpl:        tmpl,
		client:      &http.Client{},
		logger:      cfg.Logger,
	}, nil
}

const defaultOTPTemplate = `Your verification code is:
{{.Code}}

Or tap this link on your iPhone:
{{.MagicLink}}
`

// otpTemplateData is the data passed to the OTP email template.
type otpTemplateData struct {
	Code      string
	MagicLink string
}

// SendOTP sends an OTP email via the Mailgun API.
func (s *MailgunSender) SendOTP(ctx context.Context, to, code, magicLink string) error {
	var bodyBuf bytes.Buffer
	if err := s.tmpl.Execute(&bodyBuf, otpTemplateData{Code: code, MagicLink: magicLink}); err != nil {
		return fmt.Errorf("execute OTP template: %w", err)
	}

	form := url.Values{}
	form.Set("from", s.from)
	form.Set("to", to)
	form.Set("subject", "Your verification code")
	form.Set("text", bodyBuf.String())

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		fmt.Sprintf("https://api.mailgun.net/v3/%s/messages", s.domain),
		strings.NewReader(form.Encode()),
	)
	if err != nil {
		return fmt.Errorf("create mailgun request: %w", err)
	}
	req.SetBasicAuth("api", s.apiKey)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("send mailgun request: %w", err)
	}
	_ = resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("mailgun API error: %s", resp.Status)
	}

	s.logger.Info("OTP email sent via Mailgun", "to", to)
	return nil
}

// NewSender creates the appropriate Sender based on the EMAIL_BACKEND
// environment variable. Supported values: "console" (default), "mailgun".
func NewSender(logger *slog.Logger) Sender {
	backend := os.Getenv("EMAIL_BACKEND")
	switch strings.ToLower(backend) {
	case "mailgun":
		cfg := MailgunSenderConfig{
			APIKey:      os.Getenv("MAILGUN_API_KEY"),
			Domain:      os.Getenv("MAILGUN_DOMAIN"),
			From:        os.Getenv("MAILGUN_FROM"),
			TemplateStr: os.Getenv("OTP_EMAIL_TEMPLATE"),
			Logger:      logger,
		}
		s, err := NewMailgunSender(cfg)
		if err != nil {
			logger.Error("failed to create Mailgun sender, falling back to console", "error", err)
			return NewConsoleSender(logger)
		}
		return s
	default:
		return NewConsoleSender(logger)
	}
}
