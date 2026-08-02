// Package contract holds executable contract fixtures: tests that pin the
// OpenAPI spec (backend/api/openapi.yaml) to the invariants the API contract
// promises (R-003/R-006 — OpenAPI is authoritative, S10). Any drift between
// the spec and the documented contract fails here.
package contract

import (
	"os"
	"path/filepath"
	"testing"

	"gopkg.in/yaml.v3"
)

// canonicalErrorCodes is the set of error codes the API contract defines.
// The spec must document exactly these and no others.
var canonicalErrorCodes = []string{
	"invalid_body",
	"rate_limited",
	"invalid_otp",
	"otp_expired",
	"otp_attempts_exceeded",
	"invalid_apple_token",
	"apple_not_configured",
	"invalid_refresh",
	"token_reuse",
	"unauthorized",
	"not_found",
	"conflict",
	"activity_exists",
	"category_exists",
	"activity_not_found",
	"validation_error",
}

// bearerProtectedPaths are the paths whose operations must require BearerAuth
// and document a 401 response.
var bearerProtectedPaths = []string{
	"/api/v1/auth/logout",
	"/api/v1/auth/me",
	"/api/v1/activities",
	"/api/v1/activities/{id}",
	"/api/v1/categories",
	"/api/v1/categories/{id}",
	"/api/v1/entries",
	"/api/v1/entries/{id}",
}

type rawSpec struct {
	OpenAPI    string             `yaml:"openapi"`
	Info       rawInfo            `yaml:"info"`
	Paths      map[string]rawPath `yaml:"paths"`
	Components rawComponents      `yaml:"components"`
}

type rawInfo struct {
	Version string `yaml:"version"`
}

type rawPath map[string]rawOperation

type rawOperation struct {
	OperationID string                 `yaml:"operationId"`
	Security    []map[string]any       `yaml:"security"`
	Responses   map[string]rawResponse `yaml:"responses"`
}

type rawResponse struct {
	Ref         string                  `yaml:"$ref"`
	Description string                  `yaml:"description"`
	Content     map[string]rawMediaType `yaml:"content"`
}

type rawMediaType struct {
	Schema   rawSchema      `yaml:"schema"`
	Example  map[string]any `yaml:"example"`
	Examples map[string]any `yaml:"examples"`
}

type rawSchema struct {
	Ref string `yaml:"$ref"`
}

type rawComponents struct {
	Responses map[string]rawResponse `yaml:"responses"`
}

func loadSpec(t *testing.T) *rawSpec {
	t.Helper()
	path := filepath.Join("..", "..", "api", "openapi.yaml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	var s rawSpec
	if err := yaml.Unmarshal(data, &s); err != nil {
		t.Fatalf("parse %s: %v", path, err)
	}
	return &s
}

// documentedCodes walks every example in the spec (operation and shared
// component responses) and returns the error codes it documents.
func documentedCodes(s *rawSpec) map[string]bool {
	codes := map[string]bool{}
	collect := func(resp rawResponse) {
		for _, mt := range resp.Content {
			if code, ok := mt.Example["error"].(map[string]any); ok {
				if c, ok := code["code"].(string); ok && c != "" {
					codes[c] = true
				}
			}
			for _, ex := range mt.Examples {
				exMap, ok := ex.(map[string]any)
				if !ok {
					continue
				}
				value, ok := exMap["value"].(map[string]any)
				if !ok {
					continue
				}
				errObj, ok := value["error"].(map[string]any)
				if !ok {
					continue
				}
				if c, ok := errObj["code"].(string); ok && c != "" {
					codes[c] = true
				}
			}
		}
	}
	for _, path := range s.Paths {
		for _, op := range path {
			for _, resp := range op.Responses {
				collect(resp)
			}
		}
	}
	for _, resp := range s.Components.Responses {
		collect(resp)
	}
	return codes
}

func requiresAuth(op rawOperation) bool {
	for _, sec := range op.Security {
		if _, ok := sec["BearerAuth"]; ok {
			return true
		}
	}
	return false
}

func TestSpec_IsValidOpenAPI(t *testing.T) {
	s := loadSpec(t)
	if s.OpenAPI != "3.0.3" {
		t.Errorf("expected openapi 3.0.3, got %q", s.OpenAPI)
	}
	if s.Info.Version == "" {
		t.Error("info.version must be set")
	}
}

func TestSpec_DocumentsExactlyCanonicalErrorCodes(t *testing.T) {
	s := loadSpec(t)
	codes := documentedCodes(s)

	for _, want := range canonicalErrorCodes {
		if !codes[want] {
			t.Errorf("spec does not document error code %q", want)
		}
	}
	for got := range codes {
		found := false
		for _, want := range canonicalErrorCodes {
			if got == want {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("spec documents undocumented error code %q — add it to canonicalErrorCodes and AGENTS.md", got)
		}
	}
}

func TestSpec_BearerProtectedPathsRequireAuthAnd401(t *testing.T) {
	s := loadSpec(t)
	for _, path := range bearerProtectedPaths {
		ops, ok := s.Paths[path]
		if !ok {
			t.Errorf("expected path %s to be documented", path)
			continue
		}
		for method, op := range ops {
			if !requiresAuth(op) {
				t.Errorf("%s %s must require BearerAuth", method, path)
			}
			if _, ok := op.Responses["401"]; !ok {
				t.Errorf("%s %s must document a 401 response", method, path)
			}
		}
	}
}

func TestSpec_ErrorResponsesUseEnvelope(t *testing.T) {
	s := loadSpec(t)
	check := func(resp rawResponse, where string) {
		for status, mt := range resp.Content {
			if status == "204" {
				continue
			}
			if mt.Schema.Ref != "#/components/schemas/ErrorResponse" {
				t.Errorf("%s must reference ErrorResponse schema, got %q", where, mt.Schema.Ref)
			}
		}
	}
	for _, path := range s.Paths {
		for method, op := range path {
			for status, resp := range op.Responses {
				if resp.Ref != "" {
					continue
				}
				if status[0] == '2' {
					continue
				}
				check(resp, method+" "+status)
			}
		}
	}
}

func TestSpec_IdempotentPostsDocument200And201(t *testing.T) {
	s := loadSpec(t)
	for _, path := range []string{
		"/api/v1/activities",
		"/api/v1/categories",
		"/api/v1/entries",
	} {
		post, ok := s.Paths[path]["post"]
		if !ok {
			t.Errorf("expected POST %s", path)
			continue
		}
		if _, ok := post.Responses["200"]; !ok {
			t.Errorf("POST %s must document 200 (idempotent replay)", path)
		}
		if _, ok := post.Responses["201"]; !ok {
			t.Errorf("POST %s must document 201", path)
		}
	}
}
