## Purpose

Produce App Store marketing panels — five on iPhone (Track, Insights, History, Add-entry, and LA-combined) and four on iPad (Track, Insights, History, Add-entry — no LA panel: iPad has no Island presentations and the owner scoped LA out of the iPad set) — from approved capture frames with owner-fixed English captions, localized to all five app locales and rendered at the matching Store sizes (5 × 5 × 2 + 4 × 5 × 1 = 70 images). The landing-page montage stays deferred and out of scope for this panel work.

## ADDED Requirements

### Requirement: Panels reuse approved captures with fixed English captions

Each panel SHALL pair one approved capture story frame with its owner-fixed English caption, verbatim: Track ("Time tracking at your fingertips."), Insights ("See where your time goes."), History ("Every minute, at a glance." + "For your eyes only."), Add-entry ("All details you need."), and LA-combined ("Your timer, always in view." — one combined Live Activity presentation built only from the approved LA Lock/compact/expanded frames of the same locale and run — no cross-locale or cross-run mixing). Panels MUST NOT reconstruct app UI, invent features, retouch app content, or alter caption wording without renewed owner approval.

#### Scenario: Panel uses an approved source with exact caption

- **WHEN** a panel is composed in English
- **THEN** its app image is traceable to a currently approved (post-2026-11-02 baseline) frame hash and its caption matches the owner-fixed English copy exactly

#### Scenario: Unapproved source or altered caption is selected

- **WHEN** a panel input is unapproved, superseded (pre-2026-11-02), from another dataset version, or carries edited English copy
- **THEN** export fails validation rather than silently substituting it

#### Scenario: Source frame carries incorrect status-bar chrome

- **WHEN** a source frame does not show the required 9:41 status bar with full cellular, full wifi, and a 100% non-charging battery
- **THEN** it is rejected as a panel source until chrome-fixed sources are verified frame-by-frame, and no matrix render proceeds from defective sources

### Requirement: Panel template approval gates localization and render

The workflow SHALL define one text panel template (canvas treatment per Store size, caption placement/typography, safe-area handling, background matching the approved light treatment) and record explicit owner approval of the English template before any localized caption work or full-matrix render. No localization or render run without that template approval counts toward the 70-image deliverable.

#### Scenario: Work requested before template approval

- **WHEN** caption localization or matrix rendering is requested before the English template approval is recorded
- **THEN** the workflow stops at the template gate and identifies the pending decision

### Requirement: Caption localization preserves meaning across five locales

The five English captions SHALL be localized to `ru`, `zh-Hans`, `es-419`, and `pt-BR`, preserving the approved meaning and Store-listing consistency (es-419 app captures map to the Spanish Mexico listing). Localized captions MUST be reviewed for clipping, truncation, and overlap on the actual panel template with Spanish/Portuguese prioritized; blocking findings reject the affected caption, never hidden by shrinking app content or editing the screenshot.

#### Scenario: Localized captions reviewed on template

- **WHEN** the five captions are prepared in all five locales
- **THEN** each locale's captions carry the same approved meaning, fit the template without clipping, and stay consistent with listing claims

### Requirement: Render matrix covers iPhone and iPad panel sets across five locales

The final matrix SHALL be 5 iPhone panels × 5 locales (`en`, `ru`, `zh-Hans`, `es-419`, `pt-BR`) × 2 iPhone sizes (portrait iPhone 1320 × 2868, portrait iPhone 1242 × 2688) plus 4 iPad panels (Track, Insights, History, Add-entry — NO LA-combined panel on iPad) × 5 locales × 1 iPad size (portrait 13-inch iPad 2064 × 2752) = 50 + 20 = 70 images. App art MUST come from the matching locale/size capture set at native dimensions — never stretched from another size. The LA-combined panel MUST use only genuine Live Activity presentations valid for that size (Island states only where the target genuinely presents them; otherwise Lock-banner-led composition, recorded never fabricated).

#### Scenario: Full matrix rendered

- **WHEN** the matrix is rendered after template and caption approvals
- **THEN** 70 images exist with declared dimensions, source-frame hashes, caption versions, renderer version, and SHA-256 hashes, and no entry is missing, stretched, or fabricated

#### Scenario: A required source frame is missing or blocked

- **WHEN** the matching locale/size capture set lacks a required approved frame
- **THEN** the manifest records the blocked panel and reason, and the set is not marked complete or replaced by a mockup

### Requirement: Panel evidence is external and the landing montage stays deferred

The workflow SHALL export panel binaries outside the repository with a text manifest (template version, caption versions, source hashes, dimensions, hashes, review status) and SHALL present the panels for separate owner acceptance. It MUST NOT modify `web/`, publish the site, embed image binaries/base64 in tracked recipes, or commit binaries without explicit owner permission. The English landing-page montage (section 7) REMAINS DEFERRED while panel work proceeds — no panel approval implies montage approval and no panel task reopens montage scope.

#### Scenario: Panel handoff completes

- **WHEN** the owner approves the panel matrix
- **THEN** the handoff includes the external asset location, the 70-image manifest with hashes, and the template/caption approval references, while website code and deployment remain unchanged
