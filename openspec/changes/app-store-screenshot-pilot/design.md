## Context

See `proposal.md` for motivation and scope, and the two delta specs for acceptance behavior. The owner selected the separate Screenshot configuration during proposal planning; that choice resolves the Release-versus-DEBUG question rather than deferring an architectural decision to apply.

Current integration points:
- `TimeOfLifeApp.swift` admits `UITEST_SCREEN` only under DEBUG; `AppContainer+UITesting.swift` provides useful stubs but seeds asynchronously and tolerates partial failure. These are inspection tools, not a production-quality capture protocol.
- `HistoryViewModel` and `InsightsViewModel` already accept `now` providers; History's `load()` still uses `Date()` directly. Track accepts a provider but its ticker/start/stop contain direct wall-clock reads. Forwarding coherent time through actual views is necessary; changing strings or drawing mock screens is not.
- Gate-seeded starter categories can race fixture categories. The screenshot path must use one awaited preparation pipeline before revealing the shell, not layer another best-effort task onto the existing gate.
- Live Activity faces use real `Text(timerInterval:)` and a real foreground ActivityKit request. App clock injection and status-bar overrides do not freeze that system timer.
- `project.yml` controls app, shared Live Activity framework, extension, and scheme configuration. Cloud version-stamping and signing have cross-target assumptions that must be audited when introducing a third configuration, even though no new target is needed.
- The active `lifio-landing-page` change excludes a screenshot gallery. This change delivers an asset for later integration, not a silent expansion of that website contract.

## Goals / Non-Goals

**Goals:** reuse real views and domain reads; make capture state explicit and inspectable; isolate every credential/store/service; stop at human review gates; keep regeneration cheaper than reshooting by hand.

**Non-Goals:** a general demo mode, a new user account product feature, global dependency-container redesign, a new screenshot SaaS, changes to production defaults, pretending system-owned surfaces are deterministic, or a responsive iPad redesign. Existing product bugs discovered during capture require reproduction and a separately scoped resolution.

## Decisions

### 1. Separate Release-optimized, simulator-only Screenshot configuration

Add `Screenshot: release` and a dedicated non-distribution scheme in XcodeGen. Use the same app/extension view sources, assets, localizations, and optimization class as Release, but enable a narrow `SCREENSHOT_CAPTURE` condition only in this configuration. The screenshot entry point requires both that condition and a simulator target. Neither ordinary Release nor its archive action gets the flag, fixture routing, or capture resources. Physical-device builds and archives of the screenshot scheme fail explicitly.

Use distinct screenshot app/extension bundle identifiers and a separate capture-only shared-storage namespace for the two processes. Keychain/session substitutes are ephemeral; all fixture writes pass through LocalStore. If an extension needs the active-file marker for a real Live Activity action, it resolves only the screenshot namespace, never the production App Group. Disable production sync activation, network services, crash reporting, and background jobs in capture composition; an accidentally attempted request fails instead of contacting the production URL. Do not merely assume the current UI-test stub never syncs: RootView lifecycle paths need explicit capture composition coverage.

Keep normal Debug/Release scheme assignments, signing, plists, backend URL behavior, warning settings, and Cloud archives unchanged. Explicitly audit XcodeGen config-name matching, configFiles, extension embedding, shared-framework flags, and version-stamp assertions; a third release-type config does not automatically inherit every named `Release` override. Add a Release-negative test with capture launch flags and build-setting checks that capture conditions are absent from all shipping targets.

Reuse small test doubles through narrowly gated shared support where practical, but do not compile the entire DEBUG inspection graph into normal Release. Capture-only sources/resources must remain excluded from shipping output. Prefer reusing existing targets rather than creating another application/extension pair.

**Alternatives considered:** extending Debug is simpler but the owner chose Release-optimized capture fidelity; using real Release accounts introduces network, privacy, and clock variability; a runtime flag in shipping Release creates an unacceptable auth-bypass surface.

### 2. Awaited preparation with a validated fixture manifest

Introduce a capture request/manifest as text data, containing schema/deck version, locale, region, timezone, calendar/week settings, reference date, state, expected totals/counts, and treatment. Only known state/locale combinations are accepted.

Preparation is ordered: create isolated storage/session → seed localized starters once → resolve stable category IDs → insert committed entries/notes/ordered category links → prepare the optional running draft → read back and validate → load view models → expose a ready marker. Unknown input, `.invalid`/`.failure` mutation outcomes, missing links, wrong counts, or mismatched totals are fatal to capture. Never silently fall back to an empty store, production services, or a different language. Await readiness and settled navigation rather than sleeping a fixed number of seconds.

One shared timeline defines roughly 55 entries over 21 days, all metadata timestamps relevant to sort/order, and at least 13 distinct texts to exercise the 12-Recents cap. Include multi-category attribution, one notes glyph, a culturally appropriate exact-text pair, and a long name; do not overload every marketing frame with test edge cases. Keep language-specific entry text/notes in capture-only fixture resources, not in user-facing L10n, while app chrome still uses the shipped bundles. No English/Chinese/Russian fixture mixture from `trackCategories`/`zhFit` is reused as final data.

Starter names/icons come from the selected shipped locale and canonical icon ordering. A single producer owns seeding; stable fixture IDs resolve relationships without a name-based race. Restart means a fresh session-specific dataset rather than accumulating records or mutating an existing account.

**Alternative considered:** seed the current `zhFit` dataset under different app languages. Rejected because its Chinese text and best-effort writes are not five approved decks or a completeness signal.

### 3. Pin logical time, not the simulator's global clock

Proposed pilot defaults, recorded in the manifest and subject to visual approval:

| Input | Default |
|---|---|
| Reference local date/time | Tuesday 2026-10-20, 09:41:00 |
| App-owned running elapsed | 12 minutes 34 seconds |
| Appearance / Dynamic Type | Light / standard Large |
| Locale → region / timezone | en → US / America/Chicago; ru → RU / Europe/Moscow; zh-Hans → CN / Asia/Shanghai; es-419 → MX / America/Mexico_City; pt-BR → BR / America/Sao_Paulo |
| Calendar / Insights | Gregorian with explicit locale week rules; This week / By category |
| Runtime | iOS 27 simulator, 6.9-inch iPhone (1320 × 2868 portrait) |
| Pilot size | 1320 × 2868 portrait |
| Chrome | 9:41 status bar, full battery and stable supported network indicators |

All dated fixture entries are anchored to the same *local* Tuesday in each declared timezone. Locale-native week rules can legitimately yield different weekly membership; compute and record expected totals per locale rather than forcing a hidden non-native week convention. App Store metadata maps the es-419 app captures to Spanish (Mexico); app-bundle language and Store metadata identifiers are distinct.

Forward the capture context through existing composition/view-model initialization with real time as the unchanged production default. Replace bypasses of an injected `now` only after a recorded failing test demonstrates the seam problem; cover History labels, Insights intervals, Track elapsed/started caption, compact timer, and relevant formatters/calendar/timezone reads together. This is a bounded capture seam, not a new global clock service. Avoid cached ambient formatters initialized before the locale is configured.

Run app-owned frames with a constant logical `now`; the ticker can continue requesting renders but observes that constant. Suppress real Live Activity creation for these historical-reference fixtures to avoid nonsensical system elapsed values. Ready markers are capture-build-only and not visible overlays in exported images.

**Alternatives considered:** changing OS time affects unrelated resources and cannot be assumed to freeze ActivityKit; setting only the status-bar time changes cosmetic chrome, not Date/Calendar behavior; changing production date semantics for prettier captures is out of scope.

### 4. Real Live Activity frames use a separate real-time anchor (three states)

For the story's Live Activity beat, prepare the same approved text/category/duration *intent* in separate capture runs, but anchor the real running draft to current wall time minus the desired elapsed offset. Start through the real TimerService/ActivityKit path while foregrounded. Do not pass the historical reference timestamp to the system timer and do not replace the timer view.

Capture all three genuine presentations: Lock Screen banner, Dynamic Island compact, and Dynamic Island expanded (touch-and-hold). The compact and expanded states require a Dynamic-Island device (the 6.9-inch iPhone class qualifies).

Record request acknowledgement, real start anchor, before/after screenshot timestamps, and observed timer. Validate rendered elapsed against the capture interval with a two-second rendering tolerance, not against an assumption that capture always lands on exactly 12:34. Do not claim full-image pixel equality for Live Activity reruns; compare static content separately and validate dynamic time numerically. A system-owned date, wallpaper/glass effect, or timer variance must be explicit in provenance, not retouched.

Use an actual Lock Screen presentation for the required banner frame across all three sizes, including iPad and the non-Island 6.5-inch phone. The compact and expanded Island frames are required on the Dynamic-Island pilot device; on non-Island targets they are N/A (recorded, never fabricated). Use a clean, nonpersonal wallpaper and hide unrelated notifications by using session-owned capture simulators. If the required presentation is unavailable or incompatible with current lifecycle expiry checks, stop that frame and investigate; no fabricated substitute counts as completion.

**Alternative considered:** static widget previews give convenient sizes but are not proof that a running Live Activity or its system presentation works. A Saved-card capture alone does not satisfy the approved running-activity story.

### 5. Pilot approval is a real production gate for assets

The local workflow has explicit stages: prepare English pilot → capture seven frames → create external review sheet → record owner approval tied to hashes → permit expanded matrix and final montage. Pilot approval cannot be inferred from passing tests, the earlier localization approval, or invoking apply. Recapture/changed hashes require renewed approval of affected content; expanded requests without matching approval metadata fail clearly.

The matrix is five locales × (1320 × 2868 iPhone, 1242 × 2688 iPhone, 2064 × 2752 iPad), retaining the existing optional-to-Apple 6.5-inch deliverable until the owner changes scope. Capture iPad rendering directly; a wide layout or compatibility presentation that actually exists is not advertised as a new reflow. Seven ordered frames per set gives 105 required raw frames; the pilot's seven are reused if still current. Do not pre-produce all translated decks/captures before the English content gate; implement the English template and validation first.

Frame preparation uses real product actions/state: running Track with selected categories; default-week Insights over committed data; History at the top viewport with day totals; Add-entry Log Time sheet with sample content including a notes value; real running Live Activity in three genuine states. The Add-entry frame shows the real sheet, not an image-edited variant. Navigation can be recorded as a reusable Argent flow at apply time; use stable accessibility targets from the current tree. `simctl` handles device preparation and native-resolution export. No fastlane service or new screenshot framework is required.

### 6. Output package and visual checks

The runner takes explicit device IDs and an external output root, defaults to the approved OpenCode temporary directory for working files, and rejects repository-contained output paths. One xcodebuild and one capture simulator at a time; record the exact Xcode/runtime/device tuple. Snapshot prior appearance, Dynamic Type, keyboard language/software-keyboard state, and overrides before modifications. Explicitly show the normal localized software keyboard for the picker frame regardless of the host's connected hardware keyboard; on iPad avoid an accidental floating/undocked presentation. Validate the observed keyboard, not merely the launch request. On all exits end only capture-owned activities, restore settings, and clean only the known session directory, preserving exported evidence. Never erase a shared simulator, use a global kill, or clear another account's data.

Export named PNGs plus a machine-readable manifest with actual dimensions, SHA-256 hashes, expected totals, logical/system clock domains, build/configuration, dataset version, treatment, approval references, and failures. Preserve unmodified raw captures. Contact sheets are external binaries too; commit only text recipes/runbook/manifests that contain no secrets or real account data. Temporary storage is not durable asset hosting: before the pilot approval gate, agree an externally retained destination with the owner, copy the complete pilot package there, and verify hashes. Refer to those retained files during review and handoff; never delete the only evidence during session cleanup or rely on a temporary-directory lifetime.

Check pixels/dimensions and visible language/content, then inspect Recents, History headers, Insights footnote, Add-entry cards, compact timer, and Live Activity. English pilot needs two consecutive complete runs; after approval each matrix set needs two successful runs with stable app content and validated system-clock variance. Also perform the existing 13 mini/SE3 XXXL fit checks, prioritizing Spanish and Portuguese; those are QA evidence, not extra Store-size deliverables. Existing test parity does not prove visual fit.

### 7. English montage is a derived asset, not a website implementation

After pilot approval, use the approved Track-running, Insights, and History frames in story order. Proposed initial treatment: one 1920 × 1080 landscape montage, three uniformly scaled screenshots on a light background matching the approved app treatment, no invented UI or new headline copy. Preserve source aspect ratios and app content; any crop must be explicit and keep the represented feature readable. Exact placement/scales are a text recipe reviewed with the montage, so visual revisions do not require reshooting unchanged source frames.

Choose a local deterministic compositor at apply time after checking its documentation/version; no app runtime dependency is added. Export a lossless PNG master and a browser-friendly derivative only if separately requested or useful for the handoff. Record source hashes, recipe/version, renderer version, dimensions, and montage hash. Owner approval of the montage is separate from approval of the pilot. Do not change `web/`, deploy, embed binaries/base64 in tracked text, or create non-English montage variants.

**Alternatives considered:** shooting another marketing dataset causes inconsistency; rebuilding app UI in a drawing tool can misrepresent shipped behavior; updating the landing page here conflicts with the agreed asset-only scope and the active landing change.

## Risks / Trade-offs

- [Capture config widens authentication or storage access] → compile/simulator gates, separate identities/namespace, no live services, fail-closed preparation, Release-negative tests, unchanged signed archive scheme.
- [Third config breaks generation/stamping] → inspect generated build settings and all-target version/config assumptions; verify normal Debug and Release paths before producing assets. Do not hand-edit pbxproj.
- [Injected now is only partly honored] → reproduce direct-Date leaks with failing tests before edits; assert all frame labels, intervals, draft exclusions, and compact timer agree.
- [Historical fixture causes expired/incorrect system activity] → separate real-time Live Activity run, explicit timestamps/tolerance, no pixel-identical promise.
- [iPad layout or translation needs a product fix] → reject affected frame, retain truthful evidence, file/reproduce a scoped issue, and stop acceptance until resolution; do not hide it by cropping or stretching.
- [OS chrome, keyboard, or glass changes] → pin runtime and treatment, store provenance, and review genuine output rather than claiming cross-OS pixel stability.
- [Approval becomes stale] → tie approvals to deck/treatment and source frame hashes; changed affected frames return to review.
- [Binaries leak into git or temp assets disappear] → reject repo output roots, inspect git status, and provide explicit external retention/handoff before cleanup.

## Migration Plan

1. Reconfirm research/build-config choice and pin fixture/treatment inputs; add the isolated capture composition and tests without changing production defaults.
2. Build/generate/lint/test normal configurations and the Screenshot configuration. Prove Release ignores capture flags and capture cannot touch production state.
3. Produce and review the English pilot; stop for explicit owner approval. Only after that gate expand decks/matrix and render the English montage.
4. Hand off externally retained approved assets and text provenance; update #198/#202 and docs without closing unresolved frames. Archive only after required captures and approvals are complete.

Rollback is removal/disablement of the capture-only scheme/configuration, sources/resources, and local runner. No server deploy, account migration, production data deletion, or website rollback is needed. Never delete externally approved assets during rollback without owner instruction.

## Research and Version Pins

- Product floor stays iOS/iPadOS 18 via Xcode 16+; research host is Xcode 27.1 (27A9275). Capture runs must record and pin their actual simulator OS, device geometry, and tool versions; no OS-beta marketing claim is inferred from this research environment.
- ctx7 `/websites/developer_apple_xcode`: "Taking screenshots and recording movies in Simulator for App Store using simctl io screenshot status_bar override launch arguments localization UI tests" confirms native-resolution capture and separate application language/region settings. "Creating build configurations and setting Swift active compilation conditions per configuration to isolate development features from Release archive" confirms per-config settings and conditional compilation. Library resolution plus these two docs calls exhaust the per-question three-command budget.
- HIG/API supporting-route waiver: [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities) and [ActivityKit overview](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) were read through official DocC JSON (`/tutorials/data/design/human-interface-guidelines/live-activities.json` and `/tutorials/data/documentation/activitykit/displaying-live-data-with-live-activities.json`) instead of extra ctx7 calls. They constrain genuine platform presentations, readable content, authorization, and foreground requests. Existing ActivityKit behavior is reused; no new SDK API is selected here.
- Best-practice/tooling supporting-route waiver: official [XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md), read directly due to that command budget, defines `configs`, configuration-specific settings, and schemes. Reconfirm installed XcodeGen version at apply; exact-name Release overrides are not assumed to apply to Screenshot.
- Apple [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), [localization reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/), and [review guidelines 2.3.3/2.3.9](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) constrain sizes, Store-locale mapping, genuine in-use frames, and fictional personal information. Recheck requirements at export time.
- Installed CLI help (`xcrun simctl help status_bar`, `io`, `ui`) was read without controlling a device: PNG export, status-bar overrides, light/dark appearance, and `content_size` are supported; none is proof of an app/system-wide frozen clock. Backend/API/HIG redesign items are N/A because there is no server contract change or product-layout redesign.

## Open Questions

- ~~Which externally managed folder/link should retain the pilot and final binaries?~~ **Resolved 2026-10-30 (owner decision via question tool):** retain pilot raw captures, text manifests/manifest copies, and review sheets at `/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot` (owner permitted creating the scoped folder). This resolves location only — the STOP 5.4 asset-approval gate still requires actual retained frames + verified hashes + explicit owner approval of content, composition, and treatment before any section 6/7 work. Not a blanket approval.
- After seeing the pilot/montage, does the owner want optional caption overlays, a different canvas crop, or a dark companion asset? Defaults above remain the initial deliverables; extras require explicit approval and do not block the first raw pilot.
