// Package email provides an interface and implementations for sending
// transactional emails (OTP verification, and future emails).
package email

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"text/template"

	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/sesv2"
	"github.com/aws/aws-sdk-go-v2/service/sesv2/types"
)

// Message is a transactional email. From, when non-empty, overrides the
// sender's default From address.
type Message struct {
	To      string
	Subject string
	Text    string // plain-text body; required (iOS reads the OTP from here)
	HTML    string // optional HTML body
	From    string // optional From override
}

// Sender sends a transactional email.
type Sender interface {
	Send(ctx context.Context, msg Message) error
}

// otpTemplateData is the data passed to the OTP email templates.
type otpTemplateData struct {
	Code      string
	MagicLink string
}

const otpEmailSubject = "Your verification code"

// defaultOTPTemplate is the plain-text OTP body. The code MUST be on its own
// line so iOS .oneTimeCode autofill detects it.
const defaultOTPTextTemplate = `Your verification code is:
{{.Code}}

Or tap this link on your iPhone:
{{.MagicLink}}
`

// defaultOTPHTMLTemplate is a simple, unbranded HTML OTP body.
const defaultOTPHTMLTemplate = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;color:#111;">
  <p>Your verification code is:</p>
  <p style="font-size:32px;letter-spacing:4px;font-family:monospace;">{{.Code}}</p>
  <p>Or tap this link on your iPhone:</p>
  <p><a href="{{.MagicLink}}">{{.MagicLink}}</a></p>
</body>
</html>
`

// Package-level OTP templates. Defaults are parsed at init; NewSender applies
// env overrides (OTP_EMAIL_TEMPLATE / OTP_EMAIL_HTML_TEMPLATE) at startup.
var (
	otpTextTmpl = template.Must(template.New("otp-text").Parse(defaultOTPTextTemplate))
	otpHTMLTmpl = template.Must(template.New("otp-html").Parse(defaultOTPHTMLTemplate))
)

// parseOTPTemplate returns a parsed template, using override when non-empty
// and the fallback otherwise. Returns an error if the override is malformed.
func parseOTPTemplate(name, override, fallback string) (*template.Template, error) {
	src := fallback
	if override != "" {
		src = override
	}
	return template.New(name).Parse(src)
}

// setOTPTemplates applies env-provided OTP template overrides. It is called
// once at startup from NewSender.
func setOTPTemplates(textOverride, htmlOverride string) error {
	tt, err := parseOTPTemplate("otp-text", textOverride, defaultOTPTextTemplate)
	if err != nil {
		return fmt.Errorf("parse OTP text template: %w", err)
	}
	ht, err := parseOTPTemplate("otp-html", htmlOverride, defaultOTPHTMLTemplate)
	if err != nil {
		return fmt.Errorf("parse OTP HTML template: %w", err)
	}
	otpTextTmpl = tt
	otpHTMLTmpl = ht
	return nil
}

// NewOTPMessage renders the OTP templates into a Message ready to send.
func NewOTPMessage(to, code, magicLink string) Message {
	data := otpTemplateData{Code: code, MagicLink: magicLink}

	var textBuf, htmlBuf bytes.Buffer
	_ = otpTextTmpl.Execute(&textBuf, data)
	_ = otpHTMLTmpl.Execute(&htmlBuf, data)

	return Message{
		To:      to,
		Subject: otpEmailSubject,
		Text:    textBuf.String(),
		HTML:    htmlBuf.String(),
	}
}

// ---------- ConsoleSender ----------

// ConsoleSender prints emails to stdout (for development/testing).
type ConsoleSender struct {
	logger *slog.Logger
}

// NewConsoleSender creates a new ConsoleSender.
func NewConsoleSender(logger *slog.Logger) *ConsoleSender {
	return &ConsoleSender{logger: logger}
}

// Send prints the email to stdout.
func (s *ConsoleSender) Send(_ context.Context, msg Message) error {
	s.logger.Info("sending email", "to", msg.To, "subject", msg.Subject)
	fmt.Printf("To: %s\nSubject: %s\n\n%s\n", msg.To, msg.Subject, msg.Text)
	return nil
}

// ---------- MailgunSender ----------

// MailgunSender sends emails via the Mailgun API.
type MailgunSender struct {
	apiKey string
	domain string
	from   string
	client *http.Client
	logger *slog.Logger
}

// MailgunSenderConfig holds configuration for MailgunSender.
type MailgunSenderConfig struct {
	APIKey string
	Domain string
	From   string
	Logger *slog.Logger
}

// NewMailgunSender creates a new MailgunSender.
func NewMailgunSender(cfg MailgunSenderConfig) (*MailgunSender, error) {
	return &MailgunSender{
		apiKey: cfg.APIKey,
		domain: cfg.Domain,
		from:   cfg.From,
		client: &http.Client{},
		logger: cfg.Logger,
	}, nil
}

// Send sends an email via the Mailgun API.
func (s *MailgunSender) Send(ctx context.Context, msg Message) error {
	from := msg.From
	if from == "" {
		from = s.from
	}

	form := url.Values{}
	form.Set("from", from)
	form.Set("to", msg.To)
	form.Set("subject", msg.Subject)
	form.Set("text", msg.Text)
	if msg.HTML != "" {
		form.Set("html", msg.HTML)
	}

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

	s.logger.Info("email sent via Mailgun", "to", msg.To)
	return nil
}

// ---------- SESSender ----------

// sesAPI wraps the single sesv2.Client method we use, so SESSender is
// unit-testable with a fake.
type sesAPI interface {
	SendEmail(ctx context.Context, params *sesv2.SendEmailInput, optFns ...func(*sesv2.Options)) (*sesv2.SendEmailOutput, error)
}

// SESSender sends emails via the AWS SES v2 API.
type SESSender struct {
	client sesAPI
	from   string
	logger *slog.Logger
}

// SESSenderConfig holds configuration for SESSender.
type SESSenderConfig struct {
	AccessKeyID     string
	SecretAccessKey string
	Region          string
	From            string
	Logger          *slog.Logger
}

// NewSESSender creates a new SESSender. All fields are required.
func NewSESSender(cfg SESSenderConfig) (*SESSender, error) {
	var missing []string
	if cfg.AccessKeyID == "" {
		missing = append(missing, "AWS_ACCESS_KEY_ID")
	}
	if cfg.SecretAccessKey == "" {
		missing = append(missing, "AWS_SECRET_ACCESS_KEY")
	}
	if cfg.Region == "" {
		missing = append(missing, "AWS_REGION")
	}
	if cfg.From == "" {
		missing = append(missing, "SES_FROM")
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("missing required SES config: %s", strings.Join(missing, ", "))
	}

	client := sesv2.New(sesv2.Options{
		Region:      cfg.Region,
		Credentials: credentials.NewStaticCredentialsProvider(cfg.AccessKeyID, cfg.SecretAccessKey, ""),
	})

	return &SESSender{
		client: client,
		from:   cfg.From,
		logger: cfg.Logger,
	}, nil
}

// Send sends an email via the AWS SES v2 API.
func (s *SESSender) Send(ctx context.Context, msg Message) error {
	from := msg.From
	if from == "" {
		from = s.from
	}

	input := &sesv2.SendEmailInput{
		FromEmailAddress: &from,
		Destination: &types.Destination{
			ToAddresses: []string{msg.To},
		},
		Content: &types.EmailContent{
			Simple: &types.Message{
				Subject: &types.Content{Data: &msg.Subject},
				Body: &types.Body{
					Text: &types.Content{Data: &msg.Text},
				},
			},
		},
	}
	if msg.HTML != "" {
		input.Content.Simple.Body.Html = &types.Content{Data: &msg.HTML}
	}

	if _, err := s.client.SendEmail(ctx, input); err != nil {
		return fmt.Errorf("send via SES: %w", err)
	}

	s.logger.Info("email sent via SES", "to", msg.To)
	return nil
}

// ---------- Factory ----------

// SenderConfig holds configuration for selecting and constructing a Sender.
type SenderConfig struct {
	Backend              string // "console" (default), "mailgun", "ses"
	MailgunAPIKey        string
	MailgunDomain        string
	MailgunFrom          string
	AWSAccessKeyID       string
	AWSSecretAccessKey   string
	AWSRegion            string
	SESFrom              string
	OTPEmailTextTemplate string
	OTPEmailHTMLTemplate string
	Logger               *slog.Logger
}

// NewSender creates the appropriate Sender based on Backend. Supported values:
// "console" (default), "mailgun", "ses". On construction failure it falls back
// to ConsoleSender so the service stays available.
func NewSender(cfg SenderConfig) Sender {
	logger := cfg.Logger
	if logger == nil {
		logger = slog.Default()
	}

	if err := setOTPTemplates(cfg.OTPEmailTextTemplate, cfg.OTPEmailHTMLTemplate); err != nil {
		logger.Error("failed to configure OTP templates, falling back to console", "error", err)
		return NewConsoleSender(logger)
	}

	switch strings.ToLower(cfg.Backend) {
	case "mailgun":
		s, err := NewMailgunSender(MailgunSenderConfig{
			APIKey: cfg.MailgunAPIKey,
			Domain: cfg.MailgunDomain,
			From:   cfg.MailgunFrom,
			Logger: logger,
		})
		if err != nil {
			logger.Error("failed to create Mailgun sender, falling back to console", "error", err)
			return NewConsoleSender(logger)
		}
		return s
	case "ses":
		s, err := NewSESSender(SESSenderConfig{
			AccessKeyID:     cfg.AWSAccessKeyID,
			SecretAccessKey: cfg.AWSSecretAccessKey,
			Region:          cfg.AWSRegion,
			From:            cfg.SESFrom,
			Logger:          logger,
		})
		if err != nil {
			logger.Error("failed to create SES sender, falling back to console", "error", err)
			return NewConsoleSender(logger)
		}
		return s
	default:
		return NewConsoleSender(logger)
	}
}
