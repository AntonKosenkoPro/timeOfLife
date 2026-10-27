# localization Specification

## Purpose
Lets Lifio speak the user's own language and culture at launch across the USA, China, Latin America, and Brazil while keeping every string verifiable without a native-speaker budget.
## Requirements
### Requirement: Five-locale string coverage

The system SHALL ship user-facing iOS strings in exactly five locales: `en`, `ru`, `zh-Hans`, `es-419`, `pt-BR`. Every `L10n` key SHALL resolve to a non-empty, non-key-echo value in each locale's bundle.

#### Scenario: Parity check passes for all locales

- **WHEN** `LocalizationTests` runs against the five bundles
- **THEN** every `L10n` case resolves in every bundle and the suite is green

#### Scenario: Missing key fails the build

- **WHEN** a locale lacks any `L10n` key or returns the raw key
- **THEN** CI reports failure and the change is not mergeable

### Requirement: Culture-adapted content decks

The system SHALL culture-adapt entry-facing copy per market (starter-category names, persona entry texts, notes samples) to a typical city-man day in the USA, mainland China, Mexico City, and São Paulo respectively, preserving the shared timeline shape (durations, counts, edge cases) while rewriting surface strings. `en` and `ru` decks SHALL remain the reference; `zh-Hans`, `es-419`, `pt-BR` decks SHALL NOT reuse English entry texts verbatim.

#### Scenario: Chinese screenshots read native

- **WHEN** a reviewer opens the `zh-Hans` deck
- **THEN** entry texts, notes, and category names are Simplified Chinese realistic for Shanghai daily life, with no English entry texts mixed in

#### Scenario: LatAm variants are consistent

- **WHEN** a reviewer compares `es-419` and `pt-BR` decks
- **THEN** `es-419` uses Latin-American usage anchored on Mexico City and `pt-BR` uses Brazilian usage anchored on São Paulo (one variant per language, no `es-ES`/`pt-PT` mixing)

### Requirement: LLM three-family review with length gate

Each new locale SHALL ship with an adjudication report from three different LLM families (translator → blind back-translator → reviewer), listing per-key confidence, formality choice (`tú/usted`, `你/您`, BR informality), and a risk list. Any key longer than 1.3× its EN source or rendering truncated in Recents, History pinned header, or the Insights footnote SHALL be must-fix with no LLM override.

#### Scenario: Long string is blocked

- **WHEN** a `zh-Hans` key exceeds 1.3× EN length or truncates in a tight surface
- **THEN** the locale is rejected until the string is rewritten, regardless of reviewer approval

#### Scenario: Adjudication is auditable

- **WHEN** the author opens the locale's report
- **THEN** source, candidate, back-translation, reviewer verdict, and length measurements are all present for every flagged key

### Requirement: U4 five-locale rule for new strings

Every new user-facing string SHALL land in all five `Localizable.strings` files plus the `L10n` enum, with `LocalizationTests.allCases` coverage. The extension target (`LifioLiveActivities`) SHALL read the same five bundles.

#### Scenario: New key in one locale only is rejected

- **WHEN** a PR adds a string to fewer than five locales or omits the `L10n` case
- **THEN** review/CI blocks the PR until coverage is complete

