## 1. Stable Timer Layout

- [x] 1.1 Refactor `NumericTimerReadout` so the saved-state checkmark is overlaid above the stable timer text-and-caption layout and cannot affect its measured position.
- [x] 1.2 Mark the checkmark as decorative while preserving the combined saved-state accessibility label and value.
- [x] 1.3 Update the numeric-timer component and Track-screen design documentation to state that saved feedback does not displace the readout.

## 2. Visual Verification

- [x] 2.1 Exercise the ready, running, and saved states in an iOS simulator and verify the timer keeps the same vertical position when the blue checkmark appears.
- [x] 2.2 Verify the saved mark remains visible without clipping at the supported default and accessibility Dynamic Type sizes, and confirm VoiceOver semantics still report the saved timer state without a separate checkmark announcement.

## 3. Quality Gates

- [x] 3.1 Generate the Xcode project, run strict SwiftLint, run the warning-as-error iOS build, and run the iOS test suite.
- [x] 3.2 Run the backend formatting check, vet, lint, and test suite required by the repository iteration checklist.
