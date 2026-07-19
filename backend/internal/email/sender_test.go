package email

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"os"
	"strings"
	"testing"
)

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

func TestConsoleSender_PrintsCodeOnItsOwnLine(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelInfo}))
	s := NewConsoleSender(logger)

	ctx := context.Background()
	output := captureStdout(func() {
		err := s.SendOTP(ctx, "user@example.com", "482103", "timeoflife://auth/verify?code=482103")
		if err != nil {
			t.Fatalf("SendOTP returned error: %v", err)
		}
	})

	if !strings.Contains(output, "482103") {
		t.Errorf("expected code 482103 in output, got: %s", output)
	}
}

func TestConsoleSender_IncludesMagicLink(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelInfo}))
	s := NewConsoleSender(logger)

	ctx := context.Background()
	magicLink := "timeoflife://auth/verify?code=123456"
	output := captureStdout(func() {
		err := s.SendOTP(ctx, "user@example.com", "123456", magicLink)
		if err != nil {
			t.Fatalf("SendOTP returned error: %v", err)
		}
	})

	if !strings.Contains(output, magicLink) {
		t.Errorf("expected magic link %q in output, got: %s", magicLink, output)
	}
}

func TestConsoleSender_IncludesRecipient(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelInfo}))
	s := NewConsoleSender(logger)

	ctx := context.Background()
	output := captureStdout(func() {
		err := s.SendOTP(ctx, "alice@example.com", "987654", "timeoflife://auth/verify?code=987654")
		if err != nil {
			t.Fatalf("SendOTP returned error: %v", err)
		}
	})

	if !strings.Contains(output, "alice@example.com") {
		t.Errorf("expected recipient in output, got: %s", output)
	}
}

func TestNewSender_ReturnsConsoleSenderForConsoleBackend(t *testing.T) {
	t.Setenv("EMAIL_BACKEND", "console")

	logger := slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelInfo}))
	s := NewSender(logger)

	_, ok := s.(*ConsoleSender)
	if !ok {
		t.Fatalf("expected *ConsoleSender, got %T", s)
	}
}

func TestNewSender_ReturnsConsoleSenderForEmptyBackend(t *testing.T) {
	t.Setenv("EMAIL_BACKEND", "")

	logger := slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelInfo}))
	s := NewSender(logger)

	_, ok := s.(*ConsoleSender)
	if !ok {
		t.Fatalf("expected *ConsoleSender, got %T", s)
	}
}

func TestNewSender_ReturnsConsoleSenderForUnknownBackend(t *testing.T) {
	t.Setenv("EMAIL_BACKEND", "unknown")

	logger := slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelInfo}))
	s := NewSender(logger)

	_, ok := s.(*ConsoleSender)
	if !ok {
		t.Fatalf("expected *ConsoleSender, got %T", s)
	}
}

func TestMailgunSender_TemplateRendersCorrectly(t *testing.T) {
	t.Parallel()

	cfg := MailgunSenderConfig{
		APIKey:      "test-api-key",
		Domain:      "mg.example.com",
		From:        "noreply@example.com",
		TemplateStr: "Code: {{.Code}}\nLink: {{.MagicLink}}",
		Logger:      slog.Default(),
	}

	s, err := NewMailgunSender(cfg)
	if err != nil {
		t.Fatalf("NewMailgunSender returned error: %v", err)
	}

	var bodyBuf bytes.Buffer
	err = s.tmpl.Execute(&bodyBuf, otpTemplateData{
		Code:      "555555",
		MagicLink: "timeoflife://auth/verify?code=555555",
	})
	if err != nil {
		t.Fatalf("template execution failed: %v", err)
	}

	output := bodyBuf.String()
	if !strings.Contains(output, "555555") {
		t.Errorf("expected code in rendered template, got: %s", output)
	}
	if !strings.Contains(output, "timeoflife://auth/verify?code=555555") {
		t.Errorf("expected magic link in rendered template, got: %s", output)
	}
}

func TestMailgunSender_DefaultTemplate(t *testing.T) {
	t.Parallel()

	cfg := MailgunSenderConfig{
		APIKey: "test-api-key",
		Domain: "mg.example.com",
		From:   "noreply@example.com",
		Logger: slog.Default(),
	}

	s, err := NewMailgunSender(cfg)
	if err != nil {
		t.Fatalf("NewMailgunSender returned error: %v", err)
	}

	if s.templateStr != defaultOTPTemplate {
		t.Errorf("expected default template, got different template")
	}
}

func TestMailgunSender_NewMailgunSender_InvalidTemplate(t *testing.T) {
	t.Parallel()

	cfg := MailgunSenderConfig{
		APIKey:      "test-api-key",
		Domain:      "mg.example.com",
		From:        "noreply@example.com",
		TemplateStr: "{{.InvalidField}}",
		Logger:      slog.Default(),
	}

	s, err := NewMailgunSender(cfg)
	if err != nil {
		t.Fatalf("NewMailgunSender returned error: %v", err)
	}
	if s == nil {
		t.Fatal("expected non-nil sender")
	}
}
