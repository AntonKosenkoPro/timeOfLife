## Context

See proposal.md (Why) and `specs/category-management/spec.md` (modified requirement). Current state: user-facing delete confirmations in both languages bound the undo window to sync ("until it syncs" / "пока она не синхронизировалась"), while the baseline spec bounds it to restart — and the implementation (`UndoBufferStore`: push-then-commit on sync, `commitAll()` backstop on cold launch, no wall-clock) is the earliest of the two. The truth lives in one place; copy and spec each tell half of it. Constraints: U4 (EN + RU + `L10n` stay in sync, snapshot test at `LocalizationTests.swift:173`), S10 (no API surface touched), no behavior change.

## Goals / Non-Goals

**Goals:**
- User-facing copy states availability with no lifetime bound; the spec states the full earliest-of(push success, restart-commit) lifetime in one sentence.
- EN, RU, `L10n` snapshot, baseline delta, and the FURPS R3 note all agree.

**Non-Goals:**
- No buffer, sync, or UI-structure changes; no new keys; no other string edits.

## Decisions

- **Timeless copy: "You can shake to undo." / "Отменить можно встряской."** (dropping the trailing clause) over picking either existing bound — rationale: any bound restated in copy re-creates this exact bug the next time buffer semantics evolve; the confirmation is a destructive gate, not a lifetime manual. Alternative (copy the full earliest-of lifetime into the alert) rejected: alerts stay short, and bilingual lifetime prose drifts.
- **Spec carries the full lifetime in the requirement body** ("earlier of a successful relay push of its `DELETE` (push-then-commit) or the next app restart") plus a dedicated push-commit scenario — rationale: the two commit paths were previously split across code comments and the restart-only scenario; one sentence + one scenario makes push-then-commit first-class.
- **FURPS R3 gets a pointer note, not a rewrite** — rationale: FURPS describes intent; the OpenSpec baseline is the contract. A one-line note ("full lifetime: category-management spec") prevents a third statement of the lifetime from drifting.
- **Snapshot-test update is part of the change, not follow-up** — rationale: `LocalizationTests` pins exact string values, so the suite goes red until the snapshot matches; updating it in the same change keeps the gate green.

## Risks / Trade-offs

- [Risk] Users previously inferring "safe after sync" from the old copy may now assume unbounded undo. Mitigation: accepted — the old inference was false in the restart direction too; the system prompt + actual restore behavior are unchanged.
- [Risk] RU timeless phrasing ("Отменить можно встряской.") reads terse vs. the old clause. Mitigation: same imperative-free style as other RU confirmations; reviewer pass during implementation.

## Migration Plan

None: string-value edits only, pre-release, no format or API change. Rollback = revert the four string values + snapshot + docs note.

## Open Questions

None.
