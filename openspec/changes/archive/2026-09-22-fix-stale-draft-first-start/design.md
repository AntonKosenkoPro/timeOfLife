## Context

See proposal.md (Why). Current state: `TrackViewModel.start()` pre-syncs the committed preparation from the field only for `.idle`; for a carried-over `.ready` (the post-stop state) it schedules the deferred swap against the stale draft, and the tap's own focus-resign then recomputes a different draft — which cancels the deferred start by design (`syncReadyFromDraft`: "a changed draft cancels a deferred start so a stale draft can never start"). Net effect: the first focused Start tap after a post-stop edit is silently dropped. Constraints from `docs/project-context.md`: LocalStore stays the single mutation chokepoint (this change touches no persistence), and the `disable-start-while-saved` contract (disabled Start during the confirmation) is untouched.

## Goals / Non-Goals

**Goals:** every Start tap starts on the first tap with the field's current text; the stale-draft cancel path stays as the safety net for genuine concurrent edits; pin the edit-during-saved behavior in spec.

**Non-Goals:** changing the 1.6 s confirmation window, idle/empty-text disablement, other states' enablement, persistence or sync behavior, accessibility-label changes.

## Decisions

- **Bring the preparation up to date at tap time when the field text differs from the committed `.ready` draft** (extend the existing `.idle` pre-sync in `start()` with a text-mismatch guard) rather than re-issuing the deferred start after a cancel: the resign then recomputes an identical draft, the cancel path never fires for the tap's own resign, and there is still exactly one scheduling path. The guard matters: an unconditional sync would wipe programmatically prepared categories (re-derivation reads recents) and flip the empty-text `.ready` state to `.idle`, both covered by existing tests. Matching text is already consistent, so skipping the sync there changes nothing. Alternative considered — keep the cancel and re-schedule a fresh deferred start with the new draft — rejected: two async hops (dismissal wait, then re-wait) and a second cancel window if the user keeps typing; harder to reason about and to test.
- **No change to the cancel rule itself**: a field edit or chip tap that is NOT the tap's own resign still cancels the deferred start (existing `draftEditCancelsDeferredStart` behavior is preserved and stays covered by test).
- **Edit-during-saved keeps current behavior** (return to `.ready` for the new text at once, confirmation ends early) and the spec now says so: the field is live in every non-running state, and holding a confirmation the user has already overwritten would be the dishonest signal.

## Risks / Trade-offs

- [Risk] The tap-time sync can change categories under the tap (exact-recents inheritance) → accepted: it is the same inheritance typing already performs; the swap uses the fresh draft, never a mix.
- [Risk] Taps inside the `.saved` window stay ignored (disabled button) → accepted: unchanged contract from `disable-start-while-saved`; the fix covers taps from `.ready` onward.
