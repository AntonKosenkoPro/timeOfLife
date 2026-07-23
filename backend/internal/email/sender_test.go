package email

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/sesv2"
)

func quietLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelInfo}))
}

func captureStdout(fn func()) string {
	old := os.Stdout
	r, w, _ := os.Pipe()
	os.Stdout = w

	fn()

	_ = w.Close()
	os.Stdout = old

	var buf bytes.Buffer
	_, _ = io.Copy(&buf, r)
	return buf.String()
}

func sampleOTPMessage() Message {
	return NewOTPMessage("user@example.com", "482103", "timeoflife://verify?code=482103")
}

// ---------- NewOTPMessage ----------

func TestNewOTPMessage_RendersTextAndHTML(t *testing.T) {
	msg := NewOTPMessage("user@example.com", "482103", "timeoflife://verify?code=482103")

	if msg.To != "user@example.com" {
		t.Errorf("expected To set, got %q", msg.To)
	}
	if msg.Subject != otpEmailSubject {
		t.Errorf("expected subject %q, got %q", otpEmailSubject, msg.Subject)
	}
	if !strings.Contains(msg.Text, "482103") {
		t.Errorf("expected code in text body, got: %s", msg.Text)
	}
	if !strings.Contains(msg.HTML, "482103") {
		t.Errorf("expected code in HTML body, got: %s", msg.HTML)
	}
	if !strings.Contains(msg.Text, "timeoflife://verify?code=482103") {
		t.Errorf("expected magic link in text body, got: %s", msg.Text)
	}
	if !strings.Contains(msg.HTML, "timeoflife://verify?code=482103") {
		t.Errorf("expected magic link in HTML body, got: %s", msg.HTML)
	}
}

// TestNewOTPMessage_CodeOnItsOwnLine enforces the iOS .oneTimeCode autofill
// invariant: the OTP code must appear on its own line in the text body.
func TestNewOTPMessage_CodeOnItsOwnLine(t *testing.T) {
	msg := NewOTPMessage("user@example.com", "482103", "timeoflife://verify?code=482103")

	for _, line := range strings.Split(msg.Text, "\n") {
		if line == "482103" {
			return // found the code alone on a line
		}
	}
	t.Errorf("expected code 482103 alone on its own line in text body, got: %q", msg.Text)
}

// ---------- ConsoleSender ----------

func TestConsoleSender_PrintsCodeOnItsOwnLine(t *testing.T) {
	s := NewConsoleSender(quietLogger())

	ctx := context.Background()
	output := captureStdout(func() {
		if err := s.Send(ctx, sampleOTPMessage()); err != nil {
			t.Fatalf("Send returned error: %v", err)
		}
	})

	if !strings.Contains(output, "482103") {
		t.Errorf("expected code 482103 in output, got: %s", output)
	}
}

func TestConsoleSender_IncludesMagicLink(t *testing.T) {
	s := NewConsoleSender(quietLogger())

	ctx := context.Background()
	magicLink := "timeoflife://verify?code=123456"
	msg := NewOTPMessage("user@example.com", "123456", magicLink)
	output := captureStdout(func() {
		if err := s.Send(ctx, msg); err != nil {
			t.Fatalf("Send returned error: %v", err)
		}
	})

	if !strings.Contains(output, magicLink) {
		t.Errorf("expected magic link %q in output, got: %s", magicLink, output)
	}
}

func TestConsoleSender_IncludesRecipient(t *testing.T) {
	s := NewConsoleSender(quietLogger())

	ctx := context.Background()
	msg := NewOTPMessage("alice@example.com", "987654", "timeoflife://verify?code=987654")
	output := captureStdout(func() {
		if err := s.Send(ctx, msg); err != nil {
			t.Fatalf("Send returned error: %v", err)
		}
	})

	if !strings.Contains(output, "alice@example.com") {
		t.Errorf("expected recipient in output, got: %s", output)
	}
}

// ---------- MailgunSender ----------

func TestMailgunSender_NewMailgunSender_NoError(t *testing.T) {
	t.Parallel()

	s, err := NewMailgunSender(MailgunSenderConfig{
		APIKey: "test-api-key",
		Domain: "mg.example.com",
		From:   "noreply@example.com",
		Logger: quietLogger(),
	})
	if err != nil {
		t.Fatalf("NewMailgunSender returned error: %v", err)
	}
	if s == nil {
		t.Fatal("expected non-nil sender")
	}
	if s.domain != "mg.example.com" {
		t.Errorf("expected domain mg.example.com, got %q", s.domain)
	}
	if s.from != "noreply@example.com" {
		t.Errorf("expected from noreply@example.com, got %q", s.from)
	}
}

// ---------- SESSender ----------

// fakeSES captures the SendEmailInput passed to SendEmail.
type fakeSES struct {
	input *sesv2.SendEmailInput
	err   error
}

func (f *fakeSES) SendEmail(_ context.Context, params *sesv2.SendEmailInput, _ ...func(*sesv2.Options)) (*sesv2.SendEmailOutput, error) {
	f.input = params
	if f.err != nil {
		return nil, f.err
	}
	return &sesv2.SendEmailOutput{}, nil
}

func validSESSenderConfig() SESSenderConfig {
	return SESSenderConfig{
		AccessKeyID:     "AKIAEXAMPLE",
		SecretAccessKey: "secretexamplesecretexample",
		Region:          "eu-west-1",
		From:            "noreply@example.com",
		Logger:          quietLogger(),
	}
}

func TestNewSESSender_MissingConfigReturnsError(t *testing.T) {
	t.Parallel()

	_, err := NewSESSender(SESSenderConfig{Logger: quietLogger()})
	if err == nil {
		t.Fatal("expected error for missing SES config, got nil")
	}
	for _, want := range []string{"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION", "SES_FROM"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("expected error to mention %q, got: %v", want, err)
		}
	}
}

func TestNewSESSender_BuildsClientWhenConfigured(t *testing.T) {
	t.Parallel()

	s, err := NewSESSender(validSESSenderConfig())
	if err != nil {
		t.Fatalf("NewSESSender returned error: %v", err)
	}
	if s == nil || s.client == nil {
		t.Fatal("expected non-nil sender and client")
	}
	if s.from != "noreply@example.com" {
		t.Errorf("expected from noreply@example.com, got %q", s.from)
	}
}

func TestSESSender_Send_BuildsCorrectInput(t *testing.T) {
	t.Parallel()

	fake := &fakeSES{}
	s := &SESSender{client: fake, from: "noreply@example.com", logger: quietLogger()}

	msg := Message{
		To:      "user@example.com",
		Subject: "Your verification code",
		Text:    "Your code:\n482103",
		HTML:    "<p>482103</p>",
	}
	if err := s.Send(context.Background(), msg); err != nil {
		t.Fatalf("Send returned error: %v", err)
	}

	if fake.input == nil {
		t.Fatal("expected SendEmail to be called with an input")
	}
	if fake.input.FromEmailAddress == nil || *fake.input.FromEmailAddress != "noreply@example.com" {
		t.Errorf("expected FromEmailAddress noreply@example.com, got %v", fake.input.FromEmailAddress)
	}
	if fake.input.Destination == nil {
		t.Fatal("expected Destination set")
	} else if len(fake.input.Destination.ToAddresses) != 1 || fake.input.Destination.ToAddresses[0] != "user@example.com" {
		t.Errorf("expected ToAddresses [user@example.com], got %v", fake.input.Destination.ToAddresses)
	}
	if fake.input.Content == nil || fake.input.Content.Simple == nil {
		t.Fatal("expected Content.Simple set")
	}
	if got := fake.input.Content.Simple.Subject.Data; got == nil || *got != "Your verification code" {
		t.Errorf("expected subject, got %v", got)
	}
	if body := fake.input.Content.Simple.Body; body == nil || body.Text == nil || *body.Text.Data != "Your code:\n482103" {
		t.Errorf("expected text body, got %v", body)
	}
	if body := fake.input.Content.Simple.Body; body.Html == nil || *body.Html.Data != "<p>482103</p>" {
		t.Errorf("expected html body, got %v", body)
	}
}

func TestSESSender_Send_OmitsHTMLWhenEmpty(t *testing.T) {
	t.Parallel()

	fake := &fakeSES{}
	s := &SESSender{client: fake, from: "noreply@example.com", logger: quietLogger()}

	msg := Message{To: "user@example.com", Subject: "s", Text: "t"}
	if err := s.Send(context.Background(), msg); err != nil {
		t.Fatalf("Send returned error: %v", err)
	}
	if body := fake.input.Content.Simple.Body; body.Html != nil {
		t.Errorf("expected no HTML body when empty, got %v", *body.Html.Data)
	}
}

func TestSESSender_Send_UsesMessageFromOverride(t *testing.T) {
	t.Parallel()

	fake := &fakeSES{}
	s := &SESSender{client: fake, from: "default@example.com", logger: quietLogger()}

	msg := Message{To: "user@example.com", Subject: "s", Text: "t", From: "custom@example.com"}
	if err := s.Send(context.Background(), msg); err != nil {
		t.Fatalf("Send returned error: %v", err)
	}
	if got := *fake.input.FromEmailAddress; got != "custom@example.com" {
		t.Errorf("expected From override custom@example.com, got %q", got)
	}
}

func TestSESSender_Send_PropagatesClientError(t *testing.T) {
	t.Parallel()

	wantErr := errors.New("SES throttled")
	fake := &fakeSES{err: wantErr}
	s := &SESSender{client: fake, from: "noreply@example.com", logger: quietLogger()}

	msg := Message{To: "user@example.com", Subject: "s", Text: "t"}
	err := s.Send(context.Background(), msg)
	if err == nil {
		t.Fatal("expected error from SES client, got nil")
	}
	if !errors.Is(err, wantErr) {
		t.Errorf("expected wrapped %v, got %v", wantErr, err)
	}
}

// ---------- NewSender factory ----------

func TestNewSender_ReturnsConsoleSenderForConsoleBackend(t *testing.T) {
	s := NewSender(SenderConfig{Backend: "console", Logger: quietLogger()})
	if _, ok := s.(*ConsoleSender); !ok {
		t.Fatalf("expected *ConsoleSender, got %T", s)
	}
}

func TestNewSender_ReturnsConsoleSenderForEmptyBackend(t *testing.T) {
	s := NewSender(SenderConfig{Logger: quietLogger()})
	if _, ok := s.(*ConsoleSender); !ok {
		t.Fatalf("expected *ConsoleSender, got %T", s)
	}
}

func TestNewSender_ReturnsConsoleSenderForUnknownBackend(t *testing.T) {
	s := NewSender(SenderConfig{Backend: "unknown", Logger: quietLogger()})
	if _, ok := s.(*ConsoleSender); !ok {
		t.Fatalf("expected *ConsoleSender, got %T", s)
	}
}

func TestNewSender_ReturnsSESSenderWhenConfigured(t *testing.T) {
	s := NewSender(SenderConfig{
		Backend:            "ses",
		AWSAccessKeyID:     "AKIAEXAMPLE",
		AWSSecretAccessKey: "secretexamplesecretexample",
		AWSRegion:          "eu-west-1",
		SESFrom:            "noreply@example.com",
		Logger:             quietLogger(),
	})
	if _, ok := s.(*SESSender); !ok {
		t.Fatalf("expected *SESSender, got %T", s)
	}
}

func TestNewSender_SESBackendFallsBackToConsoleOnError(t *testing.T) {
	s := NewSender(SenderConfig{
		Backend: "ses", // missing AWS_* and SES_FROM
		Logger:  quietLogger(),
	})
	if _, ok := s.(*ConsoleSender); !ok {
		t.Fatalf("expected fallback *ConsoleSender, got %T", s)
	}
}

func TestNewSender_BadTemplateFallsBackToConsole(t *testing.T) {
	s := NewSender(SenderConfig{
		Backend:              "console",
		OTPEmailTextTemplate: "{{.Invalid", // malformed template
		Logger:               quietLogger(),
	})
	if _, ok := s.(*ConsoleSender); !ok {
		t.Fatalf("expected fallback *ConsoleSender, got %T", s)
	}
}

// Ensure parseOTPTemplate surfaces malformed overrides without touching globals.
func TestParseOTPTemplate_MalformedOverrideReturnsError(t *testing.T) {
	t.Parallel()

	_, err := parseOTPTemplate("otp", "{{.Bad", "fallback")
	if err == nil {
		t.Fatal("expected error for malformed override, got nil")
	}
}

func TestParseOTPTemplate_UsesFallbackWhenOverrideEmpty(t *testing.T) {
	t.Parallel()

	tmpl, err := parseOTPTemplate("otp", "", "Code: {{.Code}}")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, otpTemplateData{Code: "123456"}); err != nil {
		t.Fatalf("execute: %v", err)
	}
	if !strings.Contains(buf.String(), "123456") {
		t.Errorf("expected rendered fallback to contain code, got %s", buf.String())
	}
}
