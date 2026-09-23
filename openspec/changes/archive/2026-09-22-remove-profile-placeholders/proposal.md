## Why

Profile renders four inert rows (Integrations, Export, Appearance, Data & Privacy) as static `ListRow`s with no tap, navigation, or disabled styling. They read as broken rather than coming-soon, eroding trust in a utility destination whose working set is only sync controls, Categories, and Erase local data.

## What Changes

- Remove the `Connections` section (Integrations, Export) from `ProfileView` entirely.
- Remove the Appearance and Data & Privacy rows from the App section.
- Fold the two survivors (Categories + Erase local data) into a single `On This Device` section with a local-first explanatory footer; Account section is unchanged.
- Delete the 7 now-unused `L10n` keys (`profileLibrary`, `profileConnections`, `profileIntegrations`, `profileExport`, `profileApp`, `profileAppearance`, `profileDataAndPrivacy`) plus their `en`/`ru` strings; add one header key (`profileOnDevice`) in both locales.
- **BREAKING (spec only, pre-release):** narrows the `app-shell` Profile requirement, which currently SHALL-requires integrations/export/appearance. No on-disk, API, or navigation contract changes.

Non-goals: no new Integrations/Export/Appearance/Data-Privacy surfaces; no changes to sync behavior, category management, erase semantics, auth flow, or shell navigation. Each removed row returns via its own future change if roadmapped.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `app-shell`: Profile SHALL expose account, sync, category management, and destructive data controls only; integrations/export/appearance are no longer required Profile destinations.

## Impact

- iOS: `Features/AppShell/Views/ProfileView.swift`, `Localization/String+Localized.swift`, `en.lproj`/`ru.lproj` `Localizable.strings`, `LocalizationTests` parity (allCases).
- Specs/docs: delta on `app-shell`; no OpenAPI, backend, Design-system, or FURPS behavior change (FURPS re-check only).
- Tests/lint: SwiftLint strict, warning-as-error build, existing iOS suite green; no new test target needed beyond parity.
