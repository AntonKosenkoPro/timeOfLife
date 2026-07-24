# Design Tokens

Tokens are the atomic, reusable values of the design system. They are implemented in `ios/TimeOfLife/TimeOfLife/Core/Theme/Theme.swift` and resolved from `Assets.xcassets` for colors.

> **Rule:** Views never use raw `Color(...)`, `Font(...)` with fixed sizes, or magic numbers. Use `Theme.*` tokens.

## Colors

All colors are stored as color sets in `Assets.xcassets` with light/dark variants.

| Token | Light (`#RRGGBB`) | Dark (`#RRGGBB`) | Swift usage | Purpose |
|---|---|---|---|---|
| `backgroundPrimary` | `#FFFFFF` | `#0B0B0F` | `Theme.backgroundPrimary` | Screen background |
| `backgroundSecondary` | `#F2F2F7` | `#1C1C1E` | `Theme.backgroundSecondary` | Input field backgrounds, cards |
| `textPrimary` | `#111111` | `#F5F5F7` | `Theme.textPrimary` | Headings, primary body text |
| `textSecondary` | `#3C3C43` | `#9A9AA0` | `Theme.textSecondary` | Subtitles, placeholders, captions |
| `accentPrimary` | `#FF840A` | `#FF840A` | `Theme.accentPrimary` | Primary buttons, active states |
| `danger` | `#FF3B30` | `#FF453A` | `Theme.danger` | Errors, offline banner, destructive actions |
| `success` | `#34C759` | `#30D158` | `Theme.success` | Success states |
| `hairline` | `#E5E5EA` | `#38383C` | `Theme.hairline` | Borders, dividers |

## Typography

Use Apple system fonts via SwiftUI text styles. Do not use custom fonts for the MVP.

| Style | SwiftUI | Usage |
|---|---|---|
| Display | `.largeTitle` | Splash / empty states |
| Title | `.title.bold()` | Screen titles |
| Title 2 | `.title2.bold()` | Section headers |
| Headline | `.headline` | Emphasized list rows |
| Body | `.body` | Primary body text |
| Subheadline | `.subheadline` | Secondary body text |
| Caption | `.caption` | Field errors, helper text |
| Footnote | `.footnote` | Timestamps, metadata |
| Timer | `.system(size: 64, weight: .semibold, design: .rounded)` | Timer digit display (only exception) |

## Spacing

| Token | Value | Swift usage | Purpose |
|---|---|---|---|
| `spacingExtraSmall` | `4` | `Theme.spacingExtraSmall` | Tight gaps |
| `spacingSmall` | `8` | `Theme.spacingSmall` | Grouped elements |
| `spacingMedium` | `16` | `Theme.spacingMedium` | Default padding |
| `spacingLarge` | `24` | `Theme.spacingLarge` | Screen edge padding, section gaps |
| `spacingExtraLarge` | `32` | `Theme.spacingExtraLarge` | Major section breaks |

## Layout

| Token | Value | Swift usage | Purpose |
|---|---|---|---|
| `cornerRadius` | `10` | `Theme.cornerRadius` | Cards, fields, buttons |
| `cornerRadiusSmall` | `8` | `Theme.cornerRadiusSmall` | Compact inputs such as OTP digit boxes |
| `cornerRadiusLarge` | `16` | `Theme.cornerRadiusLarge` | Large cards, bottom sheets |
| `minTapArea` | `44` | `Theme.minTapArea` | Minimum tappable dimension |
| `screenHorizontalPadding` | `24` | `Theme.screenHorizontalPadding` | Standard screen edge padding |
| `maxContentWidth` | `420` | `Theme.maxContentWidth` | Readable line width on iPad |

## Icons

Use SF Symbols. Prefer filled variants for active/primary actions.

| Icon | SF Symbol | Usage |
|---|---|---|
| Play | `play.fill` | Start timer |
| Pause | `pause.fill` | Pause timer |
| Stop | `stop.fill` | Stop and save entry |
| History | `clock.arrow.circlepath` | History tab |
| Settings | `gearshape.fill` | Settings tab |
| Plus | `plus.circle.fill` | Add activity |
| Check | `checkmark.circle.fill` | Success state |
| Exclamation | `exclamationmark.triangle.fill` | Error state |
| Arrow back | `chevron.left` | Back navigation |
| Clock | `clock` | Activity icon fallback |

## Shadows

| Token | Value | Usage |
|---|---|---|
| `shadowSmall` | radius `4`, y `2`, opacity `0.08` | Cards on light backgrounds |
| `shadowMedium` | radius `8`, y `4`, opacity `0.12` | Floating timer card |

## ThemeManager

`ThemeManager` is the seam for a future manual theme override. For the MVP it is `nil`, which means the app follows the system color scheme.
