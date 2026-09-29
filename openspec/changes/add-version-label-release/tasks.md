## 1. Source-of-truth spike

- [x] 1.1 Verify post-`xcodegen generate` bundle version keys come from `project.yml` (not `Info.plist` statics) and record the result in the PR
- [x] 1.2 Confirm `CFBundleVersion` / `CURRENT_PROJECT_VERSION` equality assertion point for the bump script

## 2. Version label in Profile

- [x] 2.1 Add version-reading helper (bundle marketing + build keys, `• Debug` suffix under `DEBUG` only)
- [x] 2.2 Add trailing version `Section` to `ProfileView` (right-aligned caption, `Theme.textSecondary`, non-tappable, accessibility identifier)
- [x] 2.3 Add `L10n` key + `en`/`ru` strings (universal `Debug` wording) and keep `LocalizationTests` green
- [x] 2.4 Verify VoiceOver (static label) + Dynamic Type + light/dark rendering

## 3. Release workflow

- [x] 3.1 Create `workflow_dispatch` release workflow (`version` input only): main guard, `X.Y.Z` check, strictly-greater-than-current check, clean-tree check
- [x] 3.2 Implement `project.yml` bump (marketing + `CFBundleVersion` + `CURRENT_PROJECT_VERSION`, `+1` build, equality assert) with `1.0` → semver normalization
- [x] 3.3 Commit (`chore(release): bump to X.Y.Z (N)`) + annotated `vX.Y.Z` tag + push (`contents: write`)
- [x] 3.5 AI-review follow-ups: `build_only` rebuild mode + missing-tag recovery, injection-hardened ref, canonical semver, dup-key detection, `timeout-minutes`, truthful CI note (spec tag requirement clarified for rebuilds)
- [x] 3.6 Second-review follow-ups: `--atomic` pushes, recover BUILD from bump snapshot, automated `verify` via `ios.yml workflow_call`, origin-side tag checks, fixed-string bump lookup + snapshot verify, rebuild canonical-string + tag-presumption guards, SHA-compare landed check
- [x] 2.5 Owner feedback: footer label at Profile bottom (right-aligned, no card) after row + navbar spikes rejected, `v`-prefixed format, live versions set to `0.1.0 (1)`
- [ ] 3.4 Dry-run with an invalid version (guards refuse, nothing changes), then a real run; confirm refs landed (workflow's `ls-remote` check) and verify with a local build/archive before uploading (GITHUB_TOKEN pushes do not trigger `ios.yml`)

## 4. Verification and docs

- [x] 4.1 Run `swiftlint lint --strict`, `xcodebuild` build (warnings clean), iOS tests green
- [x] 4.2 Run `openspec validate --all --strict`
- [x] 4.3 Re-check `Requirements/FURPS` rows; update `docs/project-context.md` (TestFlight/versioning) and `README.md` smoke checklist if run steps changed
