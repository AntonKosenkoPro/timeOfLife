package handlers

import (
	"net/http"
	"testing"

	"github.com/antonkosenko/time-of-life/backend/internal/observe"
)

// TestInternalErrorEnvelopePreserved proves a store failure on an authed
// route still returns the generic 500 envelope — with Sentry disabled (the
// empty-DSN contract) and with Sentry enabled (reporting must never alter
// the client response). The closed SQLite store stands in for any production
// store outage (e.g. the LIFIO-BACKEND-2/3 dependency failure); AuthMiddleware
// is JWT-only, so auth passes and ListCategories is what fails.
func TestInternalErrorEnvelopePreserved(t *testing.T) {
	for _, enabled := range []bool{false, true} {
		name := "disabled"
		if enabled {
			name = "enabled"
		}
		t.Run(name, func(t *testing.T) {
			if enabled {
				// Capture the pre-test flag first (off without SENTRY_DSN)
				// so cleanup restores it; InitSentry then arms reporting
				// with a dummy DSN (no network I/O, no Flush → hermetic).
				observe.SetEnabledForTest(t, true)
				if err := observe.InitSentry("https://public@example.com/1"); err != nil {
					t.Fatalf("InitSentry(dummy DSN): %v", err)
				}
			}

			store := newTestStore(t)
			h := newTestHandler(t, store)
			_, tok := mintBearer(t, store, "internal-error@example.com")
			// Simulate a store outage after auth material exists.
			if err := store.Close(); err != nil {
				t.Fatalf("close store: %v", err)
			}

			w := serve(h, jsonReq(t, http.MethodGet, "/api/v1/categories", tok, nil))
			if w.Code != http.StatusInternalServerError {
				t.Fatalf("expected 500, got %d (body=%s)", w.Code, w.Body.String())
			}
			if code := errCode(t, w); code != "internal_error" {
				t.Errorf("expected internal_error envelope, got %q", code)
			}
		})
	}
}
