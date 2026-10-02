package handlers

import (
	"net/http"
	"testing"
)

// Canonical dot-edge reject vectors (fix #95): kept in sync with
// AuthValidatorTests dot-edge vectors on iOS. The server is authoritative;
// the client mirror exists only for instant inline feedback.
func TestRequestOTP_RejectsDotEdgeLocalParts(t *testing.T) {
	for _, tc := range []struct {
		name  string
		email string
	}{
		{"leading dot", ".a@example.com"},
		{"consecutive dots", "a..b@example.com"},
		{"trailing dot", "a.@example.com"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := newTestStore(t)
			sender := &captureSender{}
			h := newTestHandlerWithDependencies(t, store, nil, sender)

			w := requestOTP(t, h, tc.email)
			if w.Code != http.StatusBadRequest {
				t.Errorf("expected 400 for %q, got %d", tc.email, w.Code)
			}
			if len(sender.messages) != 0 {
				t.Errorf("expected no OTP issued for %q, got %d messages", tc.email, len(sender.messages))
			}
		})
	}
}

// Representative valid senders must keep working (fix #95): the strict rule
// is an intersection that only narrows the three dot-edge shapes above.
func TestRequestOTP_AcceptsRepresentativeValidSenders(t *testing.T) {
	for _, tc := range []struct {
		name  string
		email string
	}{
		{"plain", "user@example.com"},
		{"plus tag", "user+tag@example.com"},
		{"dotted local", "first.last@example.com"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := newTestStore(t)
			h := newTestHandler(t, store)

			w := requestOTP(t, h, tc.email)
			if w.Code != http.StatusAccepted {
				t.Errorf("expected 202 for %q, got %d: %s", tc.email, w.Code, w.Body.String())
			}
		})
	}
}
