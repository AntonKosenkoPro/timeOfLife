## 1. Spec + contract wording

- [x] 1.1 Delete the `(and GET /categories)` parenthetical via the `sync-client` delta spec so delta pull names `GET /entries` only and categories read full-pull by design (catalog small).
- [x] 1.2 Harden the OpenAPI `GET /categories` description (`backend/api/openapi.yaml` ~lines 482-489) from "follow-up" wording to "by design (catalog small)" with the stated rationale (small seeded catalog, cheap snapshot merge; entries unbounded).
- [x] 1.3 Confirm FURPS F7/S1 (`Requirements/FURPS/Timetracking.md`) already say entries-only/categories full-pull and need no edit; confirm the unused `CategoryFilter.ModifiedSince` DB hook is left in place as a noted future hook.

## 2. Verification

- [x] 2.1 Run backend contract + handler pins untouched and green: `TestSpec_NoModifiedSinceOnListCategories` (`contract/openapi_test.go:460`) and `TestCategories_ModifiedSinceIgnored` (`handlers/entries_edge_test.go:226`), plus `go test ./...` and `gofmt -l .` empty.
- [x] 2.2 Run `openspec validate --change "fix-94-categories-full-pull-by-design" --all` (or `openspec validate --all` in the worktree) and resolve any findings.
- [x] 2.3 Re-check the relevant `Requirements/FURPS/*.md` rows and confirm no handler/store/client/test file was modified (`git status` shows only OpenSpec artifacts + `openapi.yaml` wording).
