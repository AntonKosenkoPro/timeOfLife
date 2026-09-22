## 1. Ensure-before-push in drain

- [x] 1.1 Add `SyncController` ensure step: before each entry create/update push, POST referenced ids missing from the (per-drain cached) relay snapshot but present locally and not pending deletion; 409 remaps to winner and the entry push re-reads its payload
- [x] 1.2 Cover with `SyncControllerTests`: entry referencing relay-unknown category pushes category first with the full set (no 422, local row intact); pending-delete id is not created and prunes as before

## 2. Pull adopt-or-remap + join healing

- [x] 2.1 Add shared entry-category resolution: relay-known-but-locally-missing ids remap to same-name local rival (local-only, never enqueued) or merge the snapshot row; respect delete-wins skips; use in pull merge and conflict adoption
- [x] 2.2 Add join-set healing: tie/older server version with local strict superset via clean rows enqueues an entry update with truncation-safe bumped `updatedAt`; skips delete-wins ids
- [x] 2.3 Cover with `SyncControllerTests`: B-side strip gone (snapshot id adopted/remapped, entry keeps category); fork heals (second drain pushes full set, peer converges); server-newer still adopts (loss path unchanged)
- [x] 2.4 Fix `EntryWireDTO` decode shape: the relay returns `categories` (`CategoryTag` id/name/icon objects), not `category_ids` — decoding the absent key zeroed every pulled entry's joins and let the pull merge wipe local `entry_categories` (bug 1 root cause)
- [x] 2.5 Heal the mirror fork: on a tie pull whose server join set strictly supersets the local set (sub-ms wire precision makes server `.385574` tie with local `.385` forever), adopt the server joins locally via `resolveEntryCategoryIDs` (no outbox row); server-older superset keeps local (legitimate relay prune). Covered by two new `SyncControllerTests`; verified live (wedged join restored)

## 3. Backend doc corrections (no behavior change)

- [x] 3.1 Fix stale `store.go` `CreateEntry` comment (strict reject, not prune) and `openapi.yaml` `EntryUpdate.category_ids` 422 text (prunes on merge); run `go test ./...` contract gate green

## 4. Linters, requirements, docs

- [x] 4.1 Run `swiftlint lint --strict` (from `ios/TimeOfLife/`), `gofmt -l .` empty, `go vet ./...`; fix every finding
- [x] 4.2 Run `xcodebuild test -scheme TimeOfLife` green with no new warnings (warnings are errors via `project.yml`)
- [x] 4.3 Re-check `Requirements/FURPS/*.md` rows for sync/categories; fix conflicts; update `docs/project-context.md` sync-plane notes if behavior wording changed
