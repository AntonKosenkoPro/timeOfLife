package handlers

import (
	"context"
	"net/http"
	"strings"
)

// contextKey is a private type used for context keys to avoid collisions.
type contextKey string

const (
	// ContextKeyUserID is the context key for the authenticated user's ID.
	ContextKeyUserID contextKey = "userID"
	// ContextKeyEmail is the context key for the authenticated user's email.
	ContextKeyEmail contextKey = "email"
)

// AuthMiddleware returns an HTTP middleware that validates JWT Bearer tokens
// from the Authorization header. On success, the userID and email are stored
// in the request context. On failure, a 401 response is returned.
func (h *Handler) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			h.logger.Warn("missing authorization header")
			writeError(w, http.StatusUnauthorized, "unauthorized", "Missing authorization header", nil)
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") {
			h.logger.Warn("malformed authorization header")
			writeError(w, http.StatusUnauthorized, "unauthorized", "Invalid authorization header format", nil)
			return
		}

		tokenStr := parts[1]
		userID, email, err := h.tokenService.ValidateAccessToken(tokenStr)
		if err != nil {
			h.logger.Warn("invalid access token", "error", err)
			writeError(w, http.StatusUnauthorized, "unauthorized", "Invalid or expired access token", nil)
			return
		}

		ctx := context.WithValue(r.Context(), ContextKeyUserID, userID)
		ctx = context.WithValue(ctx, ContextKeyEmail, email)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// UserIDFromContext extracts the authenticated user's ID from the request context.
func UserIDFromContext(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(ContextKeyUserID).(string)
	return id, ok
}

// EmailFromContext extracts the authenticated user's email from the request context.
func EmailFromContext(ctx context.Context) (string, bool) {
	email, ok := ctx.Value(ContextKeyEmail).(string)
	return email, ok
}
