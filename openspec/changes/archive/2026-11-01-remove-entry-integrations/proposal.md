## Why

Lifio will no longer support entry-producing integrations. The unused source model, import deduplication, and imported-entry editing restrictions therefore add complexity without a product purpose; every saved entry should be editable. Live Activity Stop already opens the app's normal stop flow, making its independent fallback writer unnecessary too.

## What Changes

- Retire Garmin, Calendar, HealthKit, Screen Time, Siri, Home Screen widget capture, and the deferred lock-screen/Control Center Control plan. Keep Live Activities and their Stop/return links.
- **BREAKING:** remove `source` and `source_ref` from the current entry domain, local persistence shapes, outbox payloads, relay DTOs, and OpenAPI entry schemas; remove source validation, import deduplication behavior, and `duplicate_import`. Existing entry-ID idempotency, LWW, tombstones, undo, and account scoping stay unchanged.
- Make every saved entry open in EDIT mode. Remove LOCKED mode, imported-entry copy, provenance labels, and their unused localization keys across all five locales. CREATE/EDIT retain the current fields, validation, gestures, and deletion/undo behavior.
- Remove `StopTimerIntent`, its two fallback-only button views, and the now-unreachable Darwin external-stop signal/observer chain. Both Live Activity Stop links continue to open `lifio://track?stop=1`, reload the bound account's draft, and call the app's normal Stop.
- Prune extension-only database source memberships/dependencies and resolver operations only after their last caller is removed. Preserve App Group storage, account-deletion marker ownership checks, normal Live Activity rendering, Saved-card dismissal, and crash/orphan reaping.
- Preserve iOS 18 as the deployment floor by moving that contract out of the retired Control capability into `app-shell`.
- Retain historical backend migrations and the physical provenance columns/index for rollback. Their destructive removal is a separately gated later release, not part of this implementation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `entry-provenance`: remove all producer, provenance-label, and import-deduplication requirements; retire the capability.
- `lock-screen-controls`: remove the unimplemented Control contract; move the deployment floor before retiring the capability.
- `app-shell`: retain the iOS 18 deployment requirement independently of Controls.
- `entry-editor`: CREATE/EDIT only; every saved entry is editable with the existing validation, deletion, and undo behavior.
- `history-entry-list`: entry taps always open EDIT; rows no longer carry provenance.
- `manual-entry`: Log Time saves a source-free entry and shares only CREATE/EDIT form modes.
- `local-first-store`: source-free entries; preserve App Group/protection/durable drafts without speculative cross-process entry writers.
- `sync-client`: source-free entry transport with ordinary ID idempotency and existing sync invariants preserved.
- `live-activities`: link-only Stop through the main app, with no fallback writer or external-stop signaling dependency.
- `account-bound-store`: preserve account-scoped deletion cleanup without an extension database writer.

## Impact

- iOS entry models, LocalStore schema/serialization, undo snapshots, sync DTOs, History/form presentation, localization, Live Activity shared code, and XcodeGen source/dependency membership. No new dependency or target; `project.yml` remains authoritative.
- Go entry models/handlers/store queries and contract tests; authoritative `backend/api/openapi.yaml`. Unknown retired request keys can be ignored using the existing permissive decoder; source-free responses are already tolerated by the current app's `EntryWireDTO.decodeIfPresent` defaults. The release matrix must prove this before rollout.
- Current FURPS, Design, project context, OpenSpec guidance, and manual smoke instructions must reflect the retired features. Historical archives remain history; unrelated auth-helper removal, clock-injection cleanup, Kafka/roadmap decisions, and CI/change archival housekeeping are non-goals.
- Research: Context7 `/websites/developer_apple_activitykit`, query “iOS 18 SDK via Xcode 16+: open the containing app from a Live Activity Stop Link or widgetURL, handle the URL in the app, and end the Live Activity from app code” (2026-11-01). This covers the retained topic/API path. HIG-specific lookup waived: no new face, layout, control, or editor grammar is introduced; existing Design contracts are retained while unused branches are removed. External-library/best-practice lookup waived: no library adoption or new storage/deployment mechanism; backend expand-contract follows `docs/project-context.md` and local format changes follow its pre-release policy. Reconfirm documentation and those policies at apply time.
