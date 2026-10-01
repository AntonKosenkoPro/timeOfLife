package email

import (
	"strings"
	"testing"
)

// TestTemplates_OverrideAppliesAndRestores pins the package-global template
// behavior: env overrides replace the defaults, and the caller restores them
// afterwards. This test is deliberately NOT parallel: the templates are
// process-global, so concurrent mutation would flake the parallel readers
// (sequential tests run exclusively, which is what makes this safe).
func TestTemplates_OverrideAppliesAndRestores(t *testing.T) {
	// Restore defaults even on failure: later tests (and the OTP autofill
	// invariant) depend on the default templates.
	t.Cleanup(func() {
		if err := setOTPTemplates("", ""); err != nil {
			t.Fatalf("restore default templates: %v", err)
		}
	})

	if err := setOTPTemplates("CODE={{.Code}}!", "<b>{{.Code}}</b>"); err != nil {
		t.Fatalf("setOTPTemplates: %v", err)
	}
	msg := NewOTPMessage("user@example.com", "482103")
	if !strings.Contains(msg.Text, "CODE=482103!") {
		t.Errorf("expected text override rendered, got %q", msg.Text)
	}
	if !strings.Contains(msg.HTML, "<b>482103</b>") {
		t.Errorf("expected HTML override rendered, got %q", msg.HTML)
	}

	// Malformed overrides fail without touching the live templates.
	before := NewOTPMessage("user@example.com", "111111")
	if err := setOTPTemplates("{{.Unclosed", ""); err == nil {
		t.Error("expected error for malformed text override, got nil")
	}
	after := NewOTPMessage("user@example.com", "111111")
	if before.Text != after.Text {
		t.Error("failed override mutated the live text template")
	}
}

// TestTemplates_DefaultHTMLPresent pins that the default OTP message always
// carries both bodies (SES includes HTML; the HTML-absent wire shape only
// arises from a hand-built Message, covered by
// TestSESSender_Send_OmitsHTMLWhenEmpty).
func TestTemplates_DefaultHTMLPresent(t *testing.T) {
	if err := setOTPTemplates("", ""); err != nil {
		t.Fatalf("setOTPTemplates: %v", err)
	}
	msg := NewOTPMessage("user@example.com", "482103")
	if msg.HTML == "" {
		t.Error("expected default HTML body, got empty")
	}
	if !strings.Contains(msg.HTML, "482103") {
		t.Errorf("expected code in HTML body, got: %s", msg.HTML)
	}
}
