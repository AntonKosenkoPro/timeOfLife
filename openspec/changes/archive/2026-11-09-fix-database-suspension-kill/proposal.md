## Why

TestFlight 0.2.8 (153) was terminated on 2026-11-09 at 09:26:28 +0200 with `RUNNINGBOARD 0xdead10cc`: a file or SQLite lock was held during suspension. Three older build-152 reports share this termination code; today's report shows a Track snapshot database read in progress while the main thread is idle, not a SwiftUI pointer exception.

## What Changes

- Coordinate account-bound database access with app suspension so locks are released and unsafe new access cannot begin after execution permission ends.
- Preserve committed entries, running drafts, undo state, outbox, and account isolation across suspension and resumption.
- Reproduce the concrete lifecycle-safety failure before production edits and retain a regression test; distinguish simulated lifecycle evidence from a physical-device OS kill.
- Keep intentional background Live Activity cleanup compatible with its bounded execution window.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `local-first-store`: define suspension-safe access and recovery without data loss.

## Impact

iOS LocalStore configuration and lifecycle integration, their composition root and tests; related runbook and architecture notes. No backend/API/schema changes, new dependencies, strings, visual redesign, or widget-extension database writer. Non-goals: timer rendering changes, arbitrary query optimizations, journal-mode migration, and a broad sync redesign.

Research: Apple `/websites/developer_apple_de`, query `iOS 18 SDK Xcode 16 UIApplication beginBackgroundTask acquire assertion on main thread before SQLite file access expiration handler endBackgroundTask suspension 0xdead10cc` (2026-11-09); Apple `https://developer.apple.com/documentation/xcode/sigkill` explains the termination code. GRDB version-specific research and implementation decisions are recorded in design.md before implementation. HIG waived: lifecycle/storage reliability only, no visual or interaction design change.
