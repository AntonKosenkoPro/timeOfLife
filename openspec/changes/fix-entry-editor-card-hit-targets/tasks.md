## 1. Repro (parent-scheduled, DONE on clean tree)

- [x] 1.1 Record failing repro on current tree via dedicated verifier (`UITEST_SCREEN` fixture, DEBUG): tap Name caption/chevron/blank/padding and Notes caption/chevron/blank/padding in CREATE/EDIT pushes nothing; attach evidence relayed by parent
- [x] 1.2 Confirm LOCKED baseline: taps on Name/Notes cards push nothing

## 2. Implementation (repro received — applied)

- [x] 2.1 Name card: hoist caption row (label + chevron) inside the `NavigationLink` label; full-width `VStack` + `contentShape(Rectangle())`; keep `.buttonStyle(.plain)`, VoiceOver label/value, LOCKED branch untouched
- [x] 2.2 Notes card: hoist `contentShape(Rectangle())` to the outer label `VStack` with full-width frames; keep `.buttonStyle(.plain)`, VoiceOver label/value, LOCKED branch untouched, notes copy unchanged
- [x] 2.3 Padding capture without `FormCard` global change: scope the push to cover card padding (per-card outer link or hit-expansion that leaves `FormCard.swift` generic); no custom gestures
- [x] 2.4 Parent follow-up `8d06a37` (no conflict, idle handoff): add inline `@ViewBuilder` to `nameCard`/`notesCard` — the LOCKED-vs-editable property-level branch returns mismatching types (`FormCard` vs `ModifiedContent+AccessibilityAttachmentModifier`) and the Release device build of the combined tree failed without branch type erasure; swiftlint `attributes` rule requires the attribute inline (`@ViewBuilder private var`)
- [x] 2.5 SwiftLint clean: `swiftlint lint --strict` from `ios/TimeOfLife` (no xcodebuild/simulator; verifier owns them)

## 3. Verification (parent-scheduled serially)

- [x] 3.1 UI evidence (combined tree): Release device build of the combined tree SUCCEEDS (after `8d06a37`); user ACCEPTED all four fixes on their physical iPhone
- [ ] 3.2 Per-branch xcodebuild test (parent verifier owns it): re-run identical repro on this fixed branch — full-card taps push existing editors on CREATE/EDIT; LOCKED inert; scroll/edge-back intact; attach evidence
- [ ] 3.3 `openspec validate --all --strict` green; no baseline spec edits, no strings/backend changes
