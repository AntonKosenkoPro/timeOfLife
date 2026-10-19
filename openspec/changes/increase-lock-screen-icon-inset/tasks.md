## 1. Banner leading inset

- [x] 1.1 Split `.padding(.horizontal, 8)` into `.padding(.leading, 12)` + `.padding(.trailing, 8)` in `RunningBannerFace.content` (`ios/TimeOfLife/LifioLiveActivities/RunningBannerFace.swift`); update the breathing-room comment to record 12pt leading / 8pt trailing + vertical
- [x] 1.2 Confirm scope: Dynamic Island faces, Stop control, timer, `activityBackgroundTint` branches, and `widgetURL` scoping untouched; no new strings or files

## 2. Final verification (pending parent evidence — do not check off without it)

- [x] 2.1 `openspec validate --all` and `--strict` green (run in-session: 27 passed, 0 failed)
- [ ] 2.2 Full-repo `swiftlint lint --strict` green from `ios/TimeOfLife/` (in-session: single-file lint of `RunningBannerFace.swift` only — 0 violations)
- [ ] 2.3 iOS build + test suite green (parent runs; no `xcodebuild`/simulator in this session per serialization)
- [x] 2.4 Backend checks green — parent evidence 2026-10-19: base `f5aa180`, backend tree `cda3b83`; `gofmt -l .` empty, `go vet` exit 0, `golangci-lint` 0 issues, `go test ./... -cover` all ok, `go build` exit 0 (log: `T/opencode/backend-verify-increase-lock-screen-icon-inset.log`)
- [ ] 2.5 On-device Lock Screen banner visual verification (12pt leading icon inset, everything else pixel-identical) — parent evidence required (Previews/simulator render tint/glass wrong per the file's own comments)

## 3. Docs

- [x] 3.1 Scoped `Design/COMPONENTS.md` `RunningBannerFace` entry with 12 leading / 8 trailing / 8 vertical insets; no broad doc changes
