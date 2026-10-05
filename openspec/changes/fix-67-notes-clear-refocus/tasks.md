## 1. Async re-claim in LogTimeView (notes card)

- [x] 1.1 Notes `×` action clears the draft notes then re-claims `.notes` focus via `DispatchQueue.main.async`
- [x] 1.2 Delete `@State suppressNotesResign` and the zero-distance `DragGesture` arming it
- [x] 1.3 Notes card `FormCard` call-site drops the `suppressNextResign` argument

## 2. Revert FormCard to unconditional resign

- [x] 2.1 Delete the `suppressNextResign` binding, init param, and one-shot skip logic
- [x] 2.2 Restore `.simultaneousGesture(TapGesture().onEnded { resignFocus() })` with accurate doc comments

## 3. Quality gates

- [x] 3.1 `swiftlint lint --strict` green
- [x] 3.2 Full `xcodebuild test -scheme TimeOfLife` suite green
- [x] 3.3 Identical simulator repro passes (keyboard stays, no flicker; videos recorded)
- [x] 3.4 Physical-device verification PASS (iPhone 17, Release build; keyboard stayed up, zero data mutations)
- [x] 3.5 `openspec validate --all` green
