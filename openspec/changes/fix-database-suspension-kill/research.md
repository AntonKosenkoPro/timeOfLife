# Research — fix-database-suspension-kill (iOS worker)

## ctx7 bundle (combined ≤ 5 with main)

- `npx ctx7@latest library "GRDB.swift" "iOS suspension database lock 0xdead10cc observesSuspensionNotifications"` → `/groue/grdb.swift` (High reputation, benchmark 69.14; versions v7.5.0–v7.11.1 listed, resolved pin is 7.8.0).
- `npx ctx7@latest docs /groue/grdb.swift "suspendNotification resumeNotification observesSuspensionNotifications"` → `GRDB/Documentation.docc/DatabaseSharing.md` § "How to limit the 0xDEAD10CC exception": set `Configuration.observesSuspensionNotifications = true` in every writing process; post `Database.suspendNotification` on `applicationDidEnterBackground` (or a background-task expiration handler); suspended DBs throw `SQLITE_INTERRUPT` (9) / `SQLITE_ABORT` (4); post `Database.resumeNotification` on foreground return; every background-mode callback that touches the DB must bracket resume→work→suspend. Marked 🔥 EXPERIMENTAL.
- `npx ctx7@latest docs /groue/grdb.swift "DatabaseQueue vs DatabasePool WAL journal mode configuration"` → shared DBs normally use `DatabasePool` (WAL); `DatabaseQueue` can share with `.wal` journal mode; cross-process creation races need `NSFileCoordinator`.
- Apple `/websites/developer_apple_de` query (`iOS 18 SDK Xcode 16 UIApplication beginBackgroundTask … 0xdead10cc`) + `https://developer.apple.com/documentation/xcode/sigkill`: fetched by main (see design.md). 0xdead10cc = file/SQLite lock held at suspension, distinct from 0x8badf00d.
- HIG: waived — storage/lifecycle reliability only, no visual or interaction change (see proposal.md).

## Pinned-source verification (GRDB 7.8.0, checkout 18497b68 — NOT master)

Verified in `~/Library/Developer/Xcode/DerivedData/TimeOfLife-*/SourcePackages/checkouts/GRDB.swift`
(revision `18497b68fdbb3a09528d260a0a0e1e7e61c8c53d` == `Package.resolved` pin for `grdb.swift` 7.8.0):

- `GRDB/Core/Configuration.swift:128`: `public var observesSuspensionNotifications = false` (default off — current tree never opts in).
- `GRDB/Core/DatabaseQueue.swift` (~208–223): `DatabaseQueue` honors the flag via `setupSuspension()` — subscribes to `Database.suspendNotification` / `Database.resumeNotification` and forwards to the single writer connection. The mechanism works with our `DatabaseQueue` (docs example uses `DatabasePool`, but the flag + observer path exists on the queue type we use).
- `GRDB/Core/Database.swift:1203–1231` (`suspend()`): synchronous, any-thread; idempotent (`isSuspended` guard); calls `sqlite3_interrupt` on the connection. New-queue catch-up does NOT exist — a queue created after the post misses it (motivates re-apply at queue creation).
- `GRDB/Core/Database.swift` (statement gate, ~1370–1430): while suspended, lock-acquiring statements throw `SQLITE_ABORT` ("Database is suspended", after attempting `rollback` to release); reads in WAL mode are exempt, **writes and (in our default rollback-journal mode) reads are not**.
- `GRDB/Core/DatabaseError.swift:68,73`: `ResultCode.SQLITE_ABORT == 4`, `ResultCode.SQLITE_INTERRUPT == 9`; `DatabaseError.resultCode` is public — errors are classifiable without message matching.
- App code calls no other interrupter: repo-wide grep for `.interrupt()` finds no app-level callers, so `SQLITE_ABORT`/`SQLITE_INTERRUPT` escaping `LocalStore` while the coordinator reports suspended corroborates suspension (no `ON CONFLICT ROLLBACK` clauses exist in the schema; task cancellation surfaces as `CancellationError`, which GRDB prioritizes over suspension-abort).

## Design consequences (why the fix looks the way it does)

- **Preemption bypasses the actor mailbox.** `NotificationCenter` observers registered with `queue: nil` run synchronously on the posting thread straight into `sqlite3_interrupt`. The coordinator therefore posts `Database.suspendNotification` directly and holds no `LocalStore` reference — it never awaits actor-isolated work that could be blocked behind the synchronous `queue.read` it must interrupt.
- **Stale suspend must not undo a newer resume.** All transitions are synchronous; the BG expiration path carries the coordinator generation captured at task entry and re-parks queues only if the generation is unchanged (foreground resume bumps it). `GRDB suspend()` itself is idempotent, so re-posts are safe.
- **Resume happens before reads, never waits for loads.** `noteResumed()` is synchronous (post GRDB resume → clear flag → post app-level did-resume); view-model reloads re-trigger on did-resume, so a foreground read that raced ahead of resume fails fast with a typed error and retries instead of showing a failure banner.
- **No journal-mode / busy-timeout change** (non-goal); no new background work; BG cleanup keeps its system-granted window with exactly-once completion and no `UIApplication` time extension.
