package handlers

import (
	"encoding/hex"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
	"github.com/antonkosenko/time-of-life/backend/internal/db"
)

// ReviewAccessConfig carries the disabled-by-default App Review exception
// binding (demo-account-access) into the auth handler. When Enabled, the
// configured immutable account UUID AND canonical email select one existing
// verified email-created account that authenticates with a reusable keyed
// six-digit code through the ordinary otp/request + otp/verify endpoints.
// Verifier is the 32-byte HMAC-SHA256 digest over the binding; Key is the
// independent dedicated 32-byte secret. The zero value disables the
// exception: both endpoints keep ordinary behavior.
type ReviewAccessConfig struct {
	Enabled      bool
	AccountID    string
	AccountEmail string
	Verifier     []byte
	Key          []byte
}

// WithReviewAccess wires the review exception binding into the Handler.
// Server composition translates config.Review into this struct; a zero
// value (or omitted option) leaves the exception disabled.
func WithReviewAccess(cfg ReviewAccessConfig) HandlerOption {
	return func(h *Handler) {
		h.reviewAccess = cfg
	}
}

// isReviewAddress reports whether the enabled exception selects this email.
// Matching is byte-exact on the canonical address — no case folding and no
// Gmail dot/plus alias collapsing — mirroring the ordinary email path.
func (h *Handler) isReviewAddress(email string) bool {
	return h.reviewAccess.Enabled && email != "" && email == h.reviewAccess.AccountEmail
}

// handleReviewRequest serves the review branch of otp/request: the ordinary
// 202 response with no account upsert, no OTP generation/persistence, no
// email delivery, and no attempt-budget consumption. Missing or mismatched
// review identity resolves identically — the exception never reveals
// account state.
func (h *Handler) handleReviewRequest(w http.ResponseWriter, r *http.Request) {
	h.logger.InfoContext(r.Context(), "review auth outcome", "outcome", "request_suppressed")
	writeAccepted(w)
}

// verifyReviewOTP serves the review branch of otp/verify. It enforces
// ordinary request/device validation (already done by the caller) and the
// existing IP defense, then: exact binding check, durable atomic admission,
// fixed-code verification, and a lifecycle re-check before ordinary
// device-bound token issuance. Ordinary OTP records are never consulted on
// this branch, so stale emailed codes cannot authorize the review address.
// Outcomes reuse invalid_otp, rate_limited (with Retry-After), and the
// current service-error envelopes; diagnostics carry only the bounded
// outcome, never identifiers, codes, keys, verifiers, or bodies.
func (h *Handler) verifyReviewOTP(w http.ResponseWriter, r *http.Request, deviceID, email, code string) {
	ctx := r.Context()

	user, err := h.store.GetUserByEmail(ctx, email)
	if err != nil {
		// No enumeration change: unknown addresses already 401 on the
		// ordinary path, and failures here create nothing.
		h.logger.WarnContext(r.Context(), "review auth outcome", "outcome", "invalid")
		writeError(w, http.StatusUnauthorized, "invalid_otp", "Invalid or expired code", nil)
		return
	}

	// Exact binding: the configured immutable UUID, an already-verified
	// address, and an email-created account (no Apple lineage, never
	// upserted or verified here). Anything else denies without issuing
	// credentials, creating an account, or changing verification state.
	if user.ID != h.reviewAccess.AccountID || !user.EmailVerified || user.AppleSubject != nil {
		h.logger.WarnContext(r.Context(), "review auth outcome", "outcome", "invalid")
		writeError(w, http.StatusUnauthorized, "invalid_otp", "Invalid or expired code", nil)
		return
	}

	// Durable reservation commits before comparison: every evaluated
	// submission consumes capacity, correct or not.
	admission, err := h.store.ReserveReviewAttempt(ctx, user.ID)
	if err != nil {
		if errors.Is(err, db.ErrUserMissing) {
			// Racing deletion: ordinary authentication failure, no session.
			h.logger.WarnContext(r.Context(), "review auth outcome", "outcome", "invalid")
			writeError(w, http.StatusUnauthorized, "invalid_otp", "Invalid or expired code", nil)
			return
		}
		h.writeInternalError(w, r, "failed to reserve review attempt", err)
		return
	}
	if !admission.Admitted {
		// A denial appends no history and cannot extend the window; the
		// Retry-After names the ceiling until both windows have capacity.
		seconds := int(admission.RetryAfter / time.Second)
		if seconds < 1 {
			seconds = 1
		}
		w.Header().Set("Retry-After", strconv.Itoa(seconds))
		h.logger.WarnContext(r.Context(), "review auth outcome", "outcome", "throttled")
		writeError(w, http.StatusTooManyRequests, "rate_limited", "Too many attempts. Please try again later.", nil)
		return
	}

	if !auth.VerifyReviewCode(h.reviewAccess.Key, hex.EncodeToString(h.reviewAccess.Verifier), user.ID, user.Email, code) {
		h.logger.WarnContext(r.Context(), "review auth outcome", "outcome", "invalid")
		writeError(w, http.StatusUnauthorized, "invalid_otp", "Invalid or expired code", nil)
		return
	}

	// Lifecycle re-check after admission: a deletion racing between
	// reservation and issuance must not mint a usable successor.
	current, err := h.store.GetUserByID(ctx, user.ID)
	if err != nil {
		h.logger.WarnContext(r.Context(), "review auth outcome", "outcome", "invalid")
		writeError(w, http.StatusUnauthorized, "invalid_otp", "Invalid or expired code", nil)
		return
	}
	if h.sessionCutByRevocation(nil, nil, current) {
		h.logger.WarnContext(r.Context(), "review auth outcome", "outcome", "invalid")
		writeError(w, http.StatusUnauthorized, "invalid_apple_token",
			"This Apple authorization predates revocation. Re-authorize with Apple.", nil)
		return
	}

	h.logger.InfoContext(r.Context(), "review auth outcome", "outcome", "success")
	h.issueTokens(ctx, w, r, current, deviceID, time.Time{}, "")
}
