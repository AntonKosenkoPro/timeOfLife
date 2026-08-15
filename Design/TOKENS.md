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
| `textOnAccent` | `#FFFFFF` | `#FFFFFF` | `Theme.textOnAccent` | Text and progress indicators on filled accent controls |
| `transparent` | n/a | n/a | `Theme.transparent` | Semantic clear layout/reserve surfaces |

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
| `spacingChip` | `10` | `Theme.spacingChip` | Uniform chip inner padding |
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
| Settings | `gearshape.fill` | Settings / configuration |
| Plus | `plus.circle.fill` | Add activity |
| Check | `checkmark.circle.fill` | Success state |
| Exclamation | `exclamationmark.triangle.fill` | Error state |
| Arrow back | `chevron.left` | Back navigation |
| Clock | `clock` | Time / duration |

### Catalog icons

Allowed set for category icons (F2); default is `tag`. This is the documented mirror of the authoritative `CategoryIcon` enum in `backend/api/openapi.yaml` (category-management D1) — the Go `validIcons` set and the iOS `CatalogIcon` type use the exact same list, and contract/unit tests fail on drift.

| SF Symbol | Usage |
|---|---|
| `clock` | Time / duration |
| `laptopcomputer` | Work / coding |
| `briefcase` | Work / office |
| `book` | Education / reading |
| `pencil.and.ruler` | Education / study |
| `brain.head.profile` | Education / focus |
| `figure.walk` | Sport / walking |
| `figure.run` | Sport / running |
| `figure.strengthtraining` | Sport / gym |
| `figure.yoga` | Sport / yoga |
| `figure.cycling` | Sport / cycling |
| `figure.swimming` | Sport / swimming |
| `figure.soccer` | Sport / soccer |
| `figure.basketball` | Sport / basketball |
| `figure.tennis` | Sport / tennis |
| `figure.gymnastics` | Sport / gymnastics |
| `figure.mindandbody` | Sport / mind & body |
| `figure.core.training` | Sport / core training |
| `dumbbell` | Sport / training |
| `bicycle` | Sport / cycling |
| `books` | Education / study |
| `graduationcap` | Education / school |
| `desktopcomputer` | Work / computer |
| `keyboard` | Work / typing |
| `gamecontroller` | Entertainment / games |
| `fork.knife` | Eat / cooking |
| `cup.and.saucer` | Eat / drink |
| `bed.double` | Sleep / rest |
| `moon.stars` | Sleep / night |
| `moon.zzz` | Sleep / rest |
| `film` | Entertainment / movies |
| `music.note` | Hobby / music |
| `guitar` | Hobby / music |
| `camera` | Hobby / photography |
| `tv` | Entertainment / TV |
| `musicalnotes` | Hobby / music |
| `paintbrush` | Hobby / art |
| `house` | Home / household |
| `car.fill` | Commute |
| `airplane` | Travel |
| `cart` | Shopping |
| `phone` | Calls / communication |
| `hammer` | DIY / build |
| `heart` | Wellness |
| `leaf` | Nature / outdoors |
| `sparkles` | Misc / other |
| `tag` | Category marker |

### Management icons

New for the catalog feature (Manage Activities, quick-add sheet, category management).

| SF Symbol | Usage |
|---|---|
| `plus` | Add activity/category |
| `square.and.pencil` | Quick-add / edit |
| `tag` / `tag.fill` | Category |
| `trash` / `trash.fill` | Delete |
| `chevron.right` | Row disclosure |
| `slider.horizontal.3` | Manage / settings |
| `paintpalette` | Color/icon picker |
| `checkmark` | Selected / confirm |
| `xmark` | Deselect / dismiss |
| `folder` | Categories list |

## Shadows

| Token | Value | Usage |
|---|---|---|
| `shadowSmall` | radius `4`, y `2`, opacity `0.08` | Cards on light backgrounds |
| `shadowMedium` | radius `8`, y `4`, opacity `0.12` | Floating timer card |

## ThemeManager

`ThemeManager` is the seam for a future manual theme override. For the MVP it is `nil`, which means the app follows the system color scheme.

## Implementation notes (catalog feature)

- `cornerRadiusLarge`, `textOnAccent`, and `transparent` are declared in `Core/Theme/Theme.swift` and used by the category-management surfaces.
