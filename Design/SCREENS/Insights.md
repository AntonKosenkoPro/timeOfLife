# Insights Screen

Implements the `insights-breakdown` capability: a read-only, mirror-only breakdown of committed time in the Insights tab. No navigation, drill-in, filtering, percentages, targets, or comparisons.

## Screen: InsightsView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Insights/Views/InsightsView.swift`
- **Route**: App shell Insights tab
- **ViewModel**: `InsightsViewModel` (pure in-memory aggregation over existing `LocalStore` reads)

### Layout

- `ScrollView` → `VStack(spacing: Theme.spacingMedium)`, background `Theme.backgroundPrimary`.
- Period switch: `Today | This week | All time` segmented control (default `This week`), `accessibilityIdentifier("InsightsPeriodPicker")`.
- Hero period total (`.title.bold()`, `Theme.textPrimary`, `.monospacedDigit()`).
- Lens toggle: `By category | By text` (default `By category`), `accessibilityIdentifier("InsightsLensPicker")`.
- Proportional rows with max-scaled bars (`Theme.backgroundSecondary` track, `Theme.accentPrimary` fill).
- Footnote naming the category double-count rule (one line, `.caption`, `Theme.textSecondary`).
- Empty periods show a one-line sentence; the true-zero state keeps the honest placeholder (`EmptyState` with `chart.line.uptrend.xyaxis`, `insightsEmptyTitle` / `insightsEmptySubtitle`).
- Compact cross-tab running timer stays visible via `.safeAreaInset(edge: .bottom)`.

### Behaviors

- Text lens groups by exact entry text (`Gym` ≠ `GYM`); each entry's full duration attributes to its text row.
- Category rows attribute the full duration to every attached category (rows may sum above the hero).
- Rows are not tappable.
- Lifecycle mirrors History: guarded reload on appear, stale on leave, refresh-signal reload so compact-timer saves appear without leaving the tab; reload on sync-cycle exit.

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys (EN + RU).
- [ ] Period/lens pickers have stable identifiers.
- [ ] Rows non-tappable, no percentages/targets/comparisons.
- [ ] Compact timer `safeAreaInset` preserved.
- [ ] Previews exist (breakdown + empty).
