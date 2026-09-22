## 1. Spec delta

- [x] 1.1 Add `specs/sync-client/spec.md` delta: categories-before-entries drain + push `validation_error/category_ids` prune-and-retry scenario
- [x] 1.2 Re-check `Requirements/FURPS/*.md` (Timetracking F14 parent language is stale activity-era; confirm no new conflict)

## 2. iOS implementation

- [x] 2.1 `SyncController.drainOutbox`: sort snapshot categories-first, `created_at, id` within resource
- [x] 2.2 `SyncController`: handle `validation_error` + `category_ids` for entry create/update — fetch server categories, prune, rewrite outbox payload, retry once, clear row; else rethrow
- [x] 2.3 Add `SyncControllerTests`: drain order (entry created before category still pushes category first); 422-heal prunes unknown and completes idle; 422 with nothing to prune still fails

## 3. Verification and docs

- [x] 3.1 `swiftlint lint --strict` + warning-as-error `xcodebuild` build + iOS test suite green
- [x] 3.2 No OpenAPI/backend change; confirm `gofmt`/`go test` untouched (or N/A)
- [x] 3.3 Update `docs/project-context.md` sync-plane drain wording if this change is archived
