## Context

See `proposal.md` (Why). The implementation is the authority: `TimeOfLife.entitlements` and `LocalStore.appGroupID` both read `group.com.antonkosenko.timeoflifeapp`, and the app is verified working (green suites + on-device smoke in `rename-app-to-lifio`). Only prose is wrong.

## Goals / Non-Goals

**Goals:**
- Every non-archive reference to the App Group reads `group.com.antonkosenko.timeoflifeapp`.
- Zero behavior change; no provisioning or code edits.

**Non-Goals:**
- No identifier rename (the opposite direction — changing code to the short form — is rejected: it would orphan the working container). No archive-history rewrite.

## Decisions

### D1: Fix prose toward code, via delta spec for the baseline
Direct-doc edits for `config.yaml`, `AGENTS.md`, and `Timetracking.md`; a `local-first-store` delta spec for the baseline (never edited directly), folded at archive.
- *Rationale:* follows OpenSpec routing; keeps the baseline's history auditable.
- *Alternative considered:* editing the baseline spec directly — rejected (violates never-edit-baselines).

## Risks / Trade-offs

- [Risk] A missed short-form literal keeps misleading a future extension author → Mitigation: tasks end with `rg "group.com.antonkosenko.timeoflife"` (unanchored) whose only allowed hits are `archive/**` history.

## Migration Plan

None — prose-only. Rollback is revert-the-commit.

## Open Questions

None.
