## Context

See proposal.md for motivation and evidence.md for the original device report. `LocalStore` is an actor containing a synchronous GRDB `DatabaseQueue`; an actor method executing `queue.read` can hold a lock independently of the idle main run loop. Snapshot loading performs several reads, and sync-exit reloads can arrive near background transitions. Existing background Live Activity reaping also reads this store. Account files and transactional outbox/undo/draft guarantees remain unchanged.

## Goals / Non-Goals

**Goals:** prevent locks surviving suspension, reject unsafe new lock acquisition, recover normal access on foreground, and keep existing bounded cleanup safe. Exercise the real store and actual lifecycle integration in regression tests.

**Non-Goals:** change journal mode or busy timeout, optimize snapshot queries, redesign sync, add scheduled background work, change timer rendering, or infer a SwiftUI memory defect from a lower stack frame.

## Decisions

1. **Centralize safety at the database boundary.** A Track-only reload guard is insufficient: sync, auth binding and background reap also touch the database. Keep mutations inside LocalStore and protect both reads and writes, including queue creation/account binding while execution is unavailable.
2. **Preemption must bypass the actor mailbox.** `DatabaseSuspension` serializes synchronous lifecycle transitions and posts GRDB suspension/resumption notifications directly; `LocalStore` enables `observesSuspensionNotifications`. Serialization covers both the policy mutation and notification effects, not just the generation check: a stale expiry post must never land after a newer foreground resume. Pinned GRDB forwards suspension synchronously to `sqlite3_interrupt`, bypassing the LocalStore actor. The queue guard and account-open guard refuse suspended work; newly created queues reapply current suspension state. Queue-level resume precedes the app's foreground did-resume signal, which drives deferred reload/bind/sync retries. A temporary inactive state (such as a system sign-in or permission sheet) is not suspension: do not disable storage solely because the app resigns active.
3. **Use only the existing background execution window.** This implementation adds no UIApplication execution assertion: it interrupts/refuses unsafe work instead of extending its lifetime. Existing BG cleanup uses only its system-granted BG task window and exactly-once completion. Its queue-level resume does not emit the foreground app-level signal or initiate unrelated sync/binding/reloads. A generation captured on entry prevents its expiry/exit from re-suspending a newer foreground state. Do not re-arm after losing the completion race to expiry. An interrupted read is distinct from an unbound store or an absent draft: it ends no Live Activity, fabricates no Saved card, and erases nothing. A transient error may preserve the existing retry policy only while the task still owns its execution window.
4. **Make suspension transient, not destructive.** Interrupted transactions roll back. Resumption reuses the bound account's durable state. New queues inherit current lifecycle policy, including open retries while backgrounded; an unbound background cleanup never creates a file. Close/switch/erase must not resurrect an old account queue or apply delayed writes to the new account. Queue-level resume occurs before foreground reads and must never wait for a snapshot load to finish.
5. **Reproduction and research gate production edits.** First run a deterministic failing regression against the base tree using a real temporary-file LocalStore and its production suspension signal path. Record exact commands and output. This tests the unsafe condition, not a physical-device RunningBoard kill. Re-run the identical case after implementation, then full iOS/backend checks. If no concrete bug can be reproduced, stop instead of applying speculative mitigation.

Alternatives rejected: changing SwiftUI pointer/timer code (the report shows an idle main thread), pausing only Track reloads (incomplete coverage), waiting for the LocalStore actor before interrupting (cannot preempt synchronous reads), and adding scheduled background sync (violates existing sync contract).

## Research

- Apple `/websites/developer_apple_de`, resolved and fetched 2026-11-09: `iOS 18 SDK Xcode 16 UIApplication beginBackgroundTask acquire assertion on main thread before SQLite file access expiration handler endBackgroundTask suspension 0xdead10cc`. The fetched UIKit documentation says to request time before starting work, cancel/defer on expiry, and end the assertion on completion; scene apps still receive `didEnterBackgroundNotification`.
- Apple https://developer.apple.com/documentation/xcode/sigkill : `0xdead10cc` identifies file/SQLite locks held during suspension, distinct from `0x8badf00d` responsiveness-watchdog termination.
- GRDB Context7 `/groue/grdb.swift`: `suspendNotification resumeNotification observesSuspensionNotifications` and `DatabaseQueue vs DatabasePool WAL journal mode configuration`; resolved/fetched and checked against **7.8.0**, revision `18497b68fdbb3a09528d260a0a0e1e7e61c8c53d`, before production edits. Full commands and pinned-source findings are in research.md. The official database-sharing guidance marks the API experimental; the pinned queue type supports it, and rollback-journal reads are subject to its suspended-statement gate. Journal mode and busy policy remain unchanged.
- HIG waived: storage/lifecycle reliability only, no visual or interaction change. No backend API or cloud service changes.

## Risks / Trade-offs

- **Experimental GRDB suspension behavior** → inspect pinned source and test real queue interruption, rollback, resume and repeated transitions; retain device smoke requirement.
- **Newly opened queues miss prior signals** → apply lifecycle state at queue creation, including failed-open retry and account switch.
- **Expiration races completion/foreground** → use one owner for policy and exactly-once completion; exercise ordering explicitly rather than adding unrelated delays.
- **Synthetic tests hide wiring defects** → drive the production notification/queue path, not test-only suspension flags or only mock stores.
- **Device-only kill cannot be established on simulator** → report automated safety checks separately from the unchecked real-device checklist.

## Migration Plan

No on-disk migration, backend deploy, secrets, strings or dependency upgrade. Distribute through the normal signed iOS build only after local checks; run the real-device suspension checklist and monitor matching Organizer reports. Reverting the code does not require data conversion.
