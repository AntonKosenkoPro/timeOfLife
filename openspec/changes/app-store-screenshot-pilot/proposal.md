## Why

Five-language localization has landed, but the existing UI-fit fixtures are not localized marketing datasets or a repeatable screenshot workflow. We need an owner-approved English iPhone pilot before producing the iPhone/iPad App Store sets and an English landing-page montage without repeatedly reshooting inconsistent content.

## What Changes

- Deliver #198 and the screenshot-data portion of #202 together: one 21-day fictional timeline, roughly 55 committed entries, adapted for Austin, Moscow, Shanghai, Mexico City, and São Paulo. Preserve durations, ordering, and category relationships across decks while localizing entry text and notes.
- Start with seven English iPhone frames in the agreed order: **Track running → Insights → History (top: Today/Yesterday) → Add entry → Live Activity (Lock Screen + Island compact + expanded)**. Owner approval of content, composition, and treatment gates all iPad and non-English captures.
- Retain iPhone 6.9-inch (1320 × 2868) and 6.5-inch (1242 × 2688) portrait sets; add actual 13-inch iPad captures (2064 × 2752). This is fifteen locale/device sets of seven frames (105 required images), not the original ten; unsupported system presentations must be reported rather than fabricated.
- Add an isolated, simulator-only capture composition using production views and LocalStore APIs, explicit locale/region/calendar/timezone, a fixed reference Tuesday, deterministic app-owned time, and a clean 9:41 status bar, pinned to the iOS 27 simulator runtime. Report the real system-timer variance of running Live Activities separately.
- Add a Release-optimized `Screenshot` configuration, not a shipping Release auth bypass. The owner selected this separate simulator-only configuration during proposal planning on 2026-10-29, explicitly resolving #198's literal Release-build assumption; normal Debug/Release and archive routing remain intact.
- Produce one English landing-page screenshot montage from approved pilot frames, with a reproducible text layout recipe and external binary outputs. Website integration is not included.
- Record text-only capture manifests, expected totals, runtime/device provenance, hashes, review outcomes, and scoped cleanup instructions; keep all screenshot/montage binaries outside git.

### Non-goals

- No app-screen redesign, iPad reflow project, feature additions, production demo/login bypass, or changes to auth, sync, backend endpoints, or the database contract.
- No landing-page code/gallery/redesign; the active `lifio-landing-page` change remains independent.
- No App Preview video (#200), broad press/social artwork (#199), complete listing-copy work (#201), or OTP email localization (#203). Coordinate any screenshot captions with #201, but raw pilot captures do not wait for complete listing copy.
- No screenshot claims for deferred ControlWidget/device-management features, no automatic App Store upload, and no permission to commit binaries.

## Capabilities

### New Capabilities

- `screenshot-capture`: safe capture-only composition, localized fictional decks, repeatable frame preparation, English-pilot approval gate, truthful iPhone/iPad capture matrix, and external evidence. Story frames: Track running, Insights, History (top viewport), Add entry (Log Time sheet — replaces the name-picker frame per 2026-10-30 owner correction), Live Activity in three genuine states (Lock Screen, Island compact, Island expanded).
- `landing-screenshot-asset`: English screenshot montage derived from approved pilot captures, reproducible composition, and asset-only handoff.

### Modified Capabilities

None. This implements the existing `localization` culture-adapted-deck contract and exercises `timer-capture-experience`, `name-picker`, `history-entry-list`, `insights-breakdown`, and `live-activities` without changing their product requirements. Baseline specs are not edited directly.

## Impact

- Likely iOS touchpoints at apply time: `project.yml`, capture configuration/scheme, DI/testing support, account/session isolation, date/clock injection in Track/History/Insights, fixture validation, and capture safety tests. Any view-model seam cleanup must preserve default production behavior and carry regression tests; a newly discovered product bug requires its own recorded reproduction and scoped fix.
- Tooling/docs: text fixture and capture/montage manifests, a local capture runner/runbook, `Design/` capture storyboard documentation, relevant project-context/CI guidance, and issue handoffs. No new third-party app runtime dependency or mandatory cloud screenshot service is planned.
- Requirements checked: Common U1/U2/U4/U5, S2/S5/S6, supported-devices constraint +2; Timetracking F4/F15 and R2. All store writes remain through LocalStore, tokens stay in Keychain/in-memory test doubles, and new app-visible copy still requires all five locales plus L10n.
- Research (2026-10-29): ctx7 `/websites/developer_apple_xcode`, queries "Taking screenshots and recording movies in Simulator for App Store using simctl io screenshot status_bar override launch arguments localization UI tests" and "Creating build configurations and setting Swift active compilation conditions per configuration to isolate development features from Release archive". Product floor: iOS/iPadOS 18 SDK via Xcode 16+; actual capture runtime/tool versions must be recorded (research host: Xcode 27.1, build 27A9275).
- Official supporting sources: [screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), [App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/), [review 2.3.3/2.3.9](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata), [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities), [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), and [XcodeGen project spec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md). HIG/API/library supporting lookups used official sources directly rather than additional ctx7 calls to respect the three-command limit; no production UI redesign or new ActivityKit API is proposed. Local `simctl help status_bar`, `io`, and `ui` confirm capture/appearance/text-size controls, not a frozen application clock.
