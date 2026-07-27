# Design System — Time of Life

This directory contains the textual design system for the Time of Life iOS app. It is the single source of truth for visual design, reusable components, screen layouts, and interaction patterns.

## Goal

Keep design under version control as plain Markdown so:

- **You** can edit it in any text editor and review diffs in pull requests.
- **Coding agents** can implement screens deterministically without guessing colors, spacing, copy, or behavior.
- **SwiftUI Previews** remain the visual validation loop, replacing the need for a separate design tool for the MVP.

## How to use

1. Before adding or changing a screen, write the spec in `SCREENS/<Screen>.md`.
2. If the screen introduces a new color, spacing value, icon, or component, update `TOKENS.md` or `COMPONENTS.md` first.
3. Implement the screen in SwiftUI using only the tokens and components documented here.
4. Add SwiftUI Previews for light/dark and English/Russian.
5. Run the per-iteration checklist from `AGENTS.md`:
   - `swiftlint lint --strict` (iOS)
   - `xcodebuild test`
   - confirm requirements alignment
   - update this design doc if the implementation diverged.

## File guide

| File | Purpose |
|---|---|
| `TOKENS.md` | Colors, typography, spacing, corner radii, shadows, icons. |
| `COMPONENTS.md` | Reusable SwiftUI components: signature, states, accessibility IDs, usage. |
| `INTERACTIONS.md` | Shared patterns: loading, errors, offline, empty states, haptics, focus. |
| `SCREENS/Auth.md` | Auth flow screens (Welcome, EmailEntry, OtpEntry). |
| `SCREENS/TimeTracking.md` | First time-tracking screen. |
| `DECISIONS.md` | Design precedents and rationale. |

## Global rules

1. **Tokens only.** No raw `Color(...)`, `.padding(17)`, or hard-coded fonts. Use `Theme.*` for colors and layout constants.
2. **Localized keys only.** No hard-coded user-facing strings. Every string lives in `L10n` and in both `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`.
3. **Accessibility identifiers.** Every interactive element gets a stable `accessibilityIdentifier` for UI tests.
4. **Minimum tap area.** All tappable targets are at least `44×44 pt`.
5. **Dynamic Type.** Use text styles (`.largeTitle`, `.title`, `.title2`, `.headline`, `.body`, `.subheadline`, `.caption`) instead of fixed sizes.
6. **Color scheme.** Light and dark variants must be previewed and tested. The app follows the system scheme by default.
7. **Offline awareness.** Every screen documents its offline behavior; network-dependent actions are disabled or show the offline banner.

## Decisions log

See `DECISIONS.md` for resolved design precedents. Respect them when adding new screens.
