## Purpose

Produce truthful, repeatable App Store screenshots from isolated fictional data, with an English iPhone approval gate before expanding to localized iPhone and iPad sets.

## ADDED Requirements

### Requirement: Capture sessions cannot affect production accounts

The capture workflow SHALL run only in an explicitly selected, simulator-only capture build using fictional account information and isolated data. It MUST NOT read or mutate production credentials, account files, active-account markers, sync state, or production services. Ordinary shipping builds MUST ignore capture launch parameters and retain mandatory sign-in.

#### Scenario: Isolated capture launch
- **WHEN** an operator launches a valid capture request on the selected simulator
- **THEN** all fixture data and session state belong to that capture session, no production network request occurs, and production account state remains unchanged

#### Scenario: Capture request reaches an ordinary shipping build
- **WHEN** capture parameters are supplied to an ordinary shipping build
- **THEN** they cannot seed data, sign a user in, or alter the normal launch gate

#### Scenario: Unsupported target or incomplete fixture
- **WHEN** the capture build is requested for a physical device or archive, or fixture preparation fails
- **THEN** the workflow fails explicitly without producing an accepted screenshot or falling back to real account state

### Requirement: Culture-adapted decks preserve a common timeline

The workflow SHALL provide a 21-day fictional timeline of approximately 55 committed entries and a separate running draft for `en`, `ru`, `zh-Hans`, `es-419`, and `pt-BR`. It SHALL preserve committed durations, timeline shape, and ordered category relationships across the Austin, Moscow, Shanghai, Mexico City, and São Paulo decks while adapting visible text and notes. Every deck MUST include multiple categories on one entry, a notes-bearing entry, an exact-text distinction, a long name, and more than twelve distinct recent texts. The running draft MUST NOT contribute to History or Insights totals.

#### Scenario: Equivalent localized decks
- **WHEN** the same timeline version is prepared in any supported locale
- **THEN** the fixture has the expected records, durations, ordered category links, and computed totals for its declared calendar, without duplicate starter categories or foreign-language fixture leakage

#### Scenario: Running entry remains uncommitted
- **WHEN** the running Track frame and its Insights or History companion frame are inspected
- **THEN** their committed totals exclude the running draft and match the fixture manifest

### Requirement: Capture inputs and app-owned time are repeatable

Each capture SHALL declare its reference Tuesday, timezone, application language, formatting region, calendar/week rules, appearance, text size, simulator runtime, screen state, and target elapsed duration. Given identical inputs and runtime, app-owned date labels, timer readouts, sorting, and committed totals SHALL be stable across clean launches. System-owned running timers are subject to the separate Live Activity requirement. The workflow SHALL prepare a 9:41 status bar where supported and MUST NOT treat a cosmetic status-bar override as a frozen application clock.

#### Scenario: Clean rerun on a different wall-clock day
- **WHEN** an app frame is prepared twice with the same declared inputs on the same runtime
- **THEN** Today/Yesterday labels, the selected Insights interval, totals, recent ordering, and app-owned elapsed readout are unchanged

#### Scenario: Unsupported or inconsistent input
- **WHEN** a requested language, region, timezone, dataset version, or screen state is unsupported or inconsistent
- **THEN** preparation fails with a useful diagnostic rather than silently substituting a default locale or partial dataset

### Requirement: English iPhone pilot gates capture expansion

The workflow SHALL first produce an English large-iPhone pilot in this order: Track running, Insights, History (top viewport: Today/Yesterday), Add entry, and Live Activity in three states (Lock Screen, Island compact, Island expanded). It SHALL record explicit owner approval of the pilot's demo content, composition, and visual treatment before producing non-English or iPad sets or the final landing montage. A run without that approval MUST remain a pilot and MUST NOT be reported as an approved expanded set.

#### Scenario: Expansion requested before approval
- **WHEN** an operator requests iPad or non-English capture before owner pilot approval is recorded
- **THEN** the workflow stops at the approval gate and identifies the pending decision

#### Scenario: Approved pilot expands
- **WHEN** the owner approves a specific pilot manifest and its verified, externally retained frame hashes
- **THEN** subsequent sets reuse that approved story and treatment, with truthful platform-specific Live Activity presentation

### Requirement: Capture matrix includes actual iPad layouts

The final matrix SHALL cover all five locales on portrait iPhone 1320 × 2868, portrait iPhone 1242 × 2688, and portrait 13-inch iPad 2064 × 2752. Each set SHALL contain the seven approved story frames (Track running, Insights, History top, Add entry, Live Activity × 3 states). App frames MUST be captured at the target device's native screenshot dimensions rather than stretched from another device. Frame dimensions and the actual runtime presentation SHALL be validated; an unavailable required frame MUST leave that set incomplete.

#### Scenario: iPad set is produced
- **WHEN** the operator captures an iPad set
- **THEN** it shows the app's actual iPad layout, its screenshots have the declared dimensions, and no iPhone-only Dynamic Island is fabricated

#### Scenario: A required frame cannot be captured
- **WHEN** the selected simulator or runtime cannot display a required system presentation
- **THEN** the manifest records the blocked frame and reason, and the set is not marked complete or replaced by a mockup

### Requirement: Live Activity frames show genuine system behavior

A Live Activity frame SHALL show an actual running activity using the shipped presentation appropriate to that platform. The workflow SHALL record its real start anchor and capture timestamp and validate the elapsed value against them with an explicit tolerance. It MUST NOT replace the system timer with a static mock, retouch its digits, invent unsupported controls, or claim pixel-identical timer digits across runs. System-owned dates or visual effects that cannot be pinned SHALL be disclosed in the manifest.

#### Scenario: Running Live Activity capture
- **WHEN** an actual Live Activity is started and captured on a supported target
- **THEN** its text and categories match the approved deck, its timer is consistent with the recorded real-time anchor within the declared tolerance, and its platform presentation is genuine

#### Scenario: Activities are unavailable
- **WHEN** the system refuses or disables Live Activities
- **THEN** capture reports the failed capability check and does not output a fabricated success frame

### Requirement: History frame shows the top of the timeline

The History frame SHALL show the top viewport: Today and Yesterday day groups with their day totals, newest entries first. The multi-category entry, long name, exact-text pair, and notes-bearing entry remain in the dataset (and stay covered by fixture tests) but are NOT required to be visible in this viewport.

#### Scenario: History top viewport captured
- **WHEN** the History frame is prepared and captured
- **THEN** Today and Yesterday labels with day totals and the newest entries are visible, and no scrolled substitute viewport is passed off as the top

### Requirement: Add-entry frame shows the Log Time sheet

The story SHALL include an Add-entry frame showing the real Log Time (manual entry) sheet with all five cards (Name, Start, End, Categories, Notes) and sample content including a visible notes value. It replaces the name-picker frame (removed per 2026-10-30 owner correction). The sheet MUST be the genuine product UI with validated state — no mock drawing, no image editing.

#### Scenario: Add-entry frame captured
- **WHEN** the Add-entry frame is prepared and captured
- **THEN** the Log Time sheet is shown with Name, Start, End, Categories, and Notes all visible, sample content populated, and the state validation passing

### Requirement: Live Activity captured in three genuine states

The Live Activity story SHALL cover three genuine system presentations of the same running activity: Lock Screen banner, Dynamic Island compact, and Dynamic Island expanded. Each MUST be a real ActivityKit presentation on a supported device — no composites, no mocks. System-owned timers in each state are validated numerically within the declared tolerance, never pixel-compared.

#### Scenario: Three Live Activity states captured
- **WHEN** the three Live Activity frames are prepared and captured on a Dynamic-Island device
- **THEN** the Lock Screen banner, the Island compact presentation, and the Island expanded presentation are each genuine, text and categories match the approved deck, and each timer is consistent with the recorded real-time anchor within tolerance

#### Scenario: A state is unavailable
- **WHEN** the system cannot present one of the three states on the capture target
- **THEN** the manifest records the blocked state and reason, and the set is not marked complete or replaced by a mockup

### Requirement: Captures run on the iOS 27 simulator runtime

All captures SHALL run on the pinned iOS 27 simulator runtime on a 6.9-inch-class iPhone (1320 × 2868 native) for the pilot, with the exact runtime version recorded per run. Prior iOS 18.6 captures are drafts and MUST be recaptured on iOS 27 before approval.

#### Scenario: Capture on the pinned runtime
- **WHEN** any pilot or matrix frame is captured
- **THEN** the manifest records the iOS 27 runtime version and device geometry, and frames from other runtimes are not mixed into the approved set

### Requirement: Final frames pass visual and language review

Every final set SHALL be inspected for clipping, truncation, text overlap, incorrect language, transient loading states, and inconsistent data. The fixed-height Recents area, History headers, and Insights footnote MUST be checked in each locale, with explicit Spanish and Portuguese review. Blocking findings MUST remain unresolved capture blockers rather than being hidden by image editing or unapproved changes to product layouts.

#### Scenario: A translated frame clips text
- **WHEN** review finds required content clipped or overlapping in a translated screenshot
- **THEN** that frame is rejected, the finding and reproduction are recorded, and final approval waits for a scoped resolution and recapture

### Requirement: Evidence and cleanup are scoped and externally stored

The workflow SHALL export screenshot binaries outside the repository, with a text manifest containing commit, configuration, device, OS/tool versions, all capture inputs, expected totals, frame identifiers, dimensions, hashes, clock exceptions, and review status. Pilot evidence SHALL be copied to an owner-agreed externally retained location and its hashes verified before pilot approval; temporary working outputs MUST NOT be the only approval source. Session cleanup SHALL preserve exported evidence through review and handoff, clean up only its own fixture state, activities, and simulator overrides, and restore prior settings where applicable. It MUST NOT commit binaries without explicit owner permission or disturb unrelated simulators or accounts.

#### Scenario: Capture session finishes
- **WHEN** capture completes or aborts
- **THEN** its exported files remain available at the declared external location, the manifest accurately distinguishes captured from approved frames, and only session-owned runtime state is cleaned up
