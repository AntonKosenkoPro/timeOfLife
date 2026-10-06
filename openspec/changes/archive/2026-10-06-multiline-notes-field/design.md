## Context

See `proposal.md` for motivation. Current state (`LogTimeView.notesCard`, `FormCard`, `ClearTextButton`): the Notes row is `VStack(caption + HStack[TextField(.submitLabel(.done)) + conditional ClearTextButton])` with `@FocusState FormField.notes`, visibility via `ClearButtonVisibility.shouldShow` (focused AND non-empty, locked hides), and `vm.clearNotes()` clearing notes only. PR #118 (unmerged `fix/67-notes-clear-no-resign` branch) inverts `FormCard` from `simultaneousGesture` + one-shot suppress to plain `.onTapGesture` with explicit resigns in chip/pill actions and a clear-only Notes ×. This design targets that end-state: it assumes the plain tap-away baseline (rebase onto #118 at implementation; if #118 merges first, no rework — the × contract here is already suppress-free).

Constraints from `docs/project-context.md`: `LocalStore` is the single mutation chokepoint (untouched — no storage change); `Theme` semantic colors only; user-facing strings via `L10n` + both locales (no new strings — the placeholder and × label are reused); iOS 18+ with no availability guards; pre-release — no on-disk migration (column is `TEXT`, validation-only domain, and the 280 cap does not move).

External docs (ctx7, fetched during proposal): library `/websites/developer_apple_swiftui`, queries `TextEditor multiline placeholder focus dismissal` (focus/dismissal semantics: programmatic `focused` binding moves/dismisses focus; tap-away + `scrollDismissesKeyboard` remain the dismissal paths) and `TextEditor` (initializer/binding contract). Version pin: iOS 18+ (repo floor).

## Goals / Non-Goals

**Goals:**
- Notes becomes a true multiline editor with newline input, stable 3-line reserve, and the #118 focus guarantee intact (× never resigns).
- Zero behavior change outside the Notes row interior (validity gate, save/LWW path, LOCKED dimming, History/Insihts untouched).

**Non-Goals:**
- No limit change (280 runes), no keyboard toolbar Done, no width-reserve for ×, no History row notes rendering, no shared-component API change.

## Decisions

1. **`TextEditor` over `TextField(axis: .vertical)`.** Return=newline is native to `TextEditor`; on a vertical-axis `TextField` it fights the submit/dismiss path the row is abandoning by design. Placeholder and dismissal become manual work, but both are one-liners against existing pieces (overlay + card tap-away). Rejected alternative: `axis: .vertical` keeps placeholder/Done for free but contradicts the chosen newline grammar.
2. **No keyboard Done affordance.** Dismissal rests on the two paths that already exist and already cover the editor: `FormCard` plain tap (label/padding — the editor consumes its own taps so focus never drops while typing) and `.scrollDismissesKeyboard(.interactively)` on the form. A toolbar Done would add chrome plus new strings for a problem Apple Notes leaves to tap-away; recorded as fallback, not scope.
3. **Fixed 3-line reserve expressed in lines, not points.** The spec pins lines-at-current-Dynamic-Type; implementation derives height from `.body` line metrics (not a hard-coded pt value) so larger type scales instead of clipping. Content past 3 lines scrolls inside the editor; card height never moves — which is also what makes the × mount/unmount vertically jump-free.
4. **`HStack(alignment: .top)` with conditional × (accept horizontal shift).** Top pin puts the glyph on line 1 as text grows downward. The editor's width still snaps when × mounts — accepted to stay consistent with every other clear field (`NamePicker` field, category editor); permanently reserving 44pt would leave a dead gutter in the common empty state.
5. **Placeholder as overlay reusing `L10n.entryNotesPlaceholder`.** `TextEditor` has no native placeholder; overlay shows only when `vm.notes.isEmpty`, in `Theme.textSecondary`, non-interactive (taps pass through to the editor). No new strings → no locale/L10n-test churn.
6. **Styling: transparent editor chrome.** `scrollContentBackground(.hidden)`, clear background, `.font(.body)`, existing `focused($focusedField, equals: .notes)` binding unchanged — so the #118 resign topology (card silent on × taps because the `Button` consumes them; explicit resigns in `toggle`/chips) carries over untouched.

## Risks / Trade-offs

- [Risk] Nested scroll (outer form `ScrollView` + inner editor past line 3): drags starting inside the editor scroll the editor, not the form → Mitigation: 280-run cap bounds overflow to a few lines; verify on device that a 5-line note remains readable without gesture confusion.
- [Risk] `TextEditor` focus-claim ordering vs the old `TextField` assumption in `FormCard` docs (field wins focus after the card's tap resign) → Mitigation: device check that tapping the editor while unfocused focuses without a resign flicker; the plain-tap-away baseline makes this strictly easier than the old simultaneous gesture.
- [Risk] Same delta touches the resign sentence #118 also rewrites (baseline says "suppresses the resign, once") → Mitigation: this change stacks after #118; if #118 merges first, rebase the delta's sentence (already written suppress-free) — no semantic conflict.
- [Risk] No client-side length gate today (server 422 is the backstop); multiline invites longer typing → Mitigation: out of scope by decision (280 unchanged), but the validity-gate question is named in tasks as a follow-up check, not silent.
- [Risk] VoiceOver order with top-trailing × (editor → clear button) → Mitigation: keep `EntryNotesClearButton` identifier/label; verify rotor order on device during the sim/device battery.

## Migration Plan

iOS-only, no data migration, no API/contract change. Land after #118 (rebase onto its branch or `main` post-merge). Rollback is a straight revert of the `notesCard` interior — the spec delta reverts with it. Archive folds the `entry-editor` delta into the baseline per the normal flow.
