## MODIFIED Requirements

### Requirement: Day groups use relative-then-absolute labels; total shown when elevated
Day group headers SHALL use relative labels ("Today", "Yesterday") for the two most recent days and the regional-standard absolute date for older days. Each header SHALL show the day label on its first line and the day's total tracked time as a subheader second line ("8h 30m tracked": total formatted in the device locale's natural language with a localized "tracked" suffix), following the Calendar Agenda week-number pattern. The total subline SHALL be visible in every header position — in-list and pinned alike, with no scroll-state gating. The day label SHALL be left-aligned to the `EntryRow` icon column's leading edge. Day group headers (in-list and elevated) SHALL render over a translucent system material with a scroll-edge effect rather than an opaque fill, so scrolling entries blur beneath them and the pinned header reads as one continuous translucent band with the navigation bar. Under Reduce Transparency / Increase Contrast the headers SHALL fall back to an opaque fill.

#### Scenario: Today's entries
- **WHEN** entries exist for the current calendar day
- **THEN** their day group header reads "Today" (localized) with the day's total tracked time as its subline

#### Scenario: Yesterday's entries
- **WHEN** entries exist for the previous calendar day
- **THEN** their day group header reads "Yesterday" (localized) with the day's total tracked time as its subline

#### Scenario: Older entries
- **WHEN** entries exist for a day before yesterday
- **THEN** their day group header reads the absolute date formatted using the device's regional settings, with the day's total tracked time as its subline

#### Scenario: In-list header shows only the day label
- **WHEN** a day group header sits in its in-list scroll position (not pinned at the top)
- **THEN** the header shows the day label on its first line together with the total subline on its second line — the position-independent two-line header supersedes the former label-only presentation, so in-list and pinned headers render identically

#### Scenario: Day with in-progress entries
- **WHEN** a day group contains an entry with no end time
- **THEN** the total counts only entries with a known `durationSeconds`; in-progress entries contribute zero to the total

#### Scenario: Elevated total follows the device locale
- **WHEN** the device locale is Russian and a header is elevated
- **THEN** the day total renders with Russian unit abbreviations followed by the localized "tracked" suffix (the total subline is position-independent, so this holds for in-list headers identically)

#### Scenario: Pinned header blurs content beneath it
- **WHEN** the user scrolls a day group so its header pins at the top of the list
- **THEN** scrolled entries pass visibly blurred beneath the header and the header-to-navigation-bar boundary shows no opaque seam

#### Scenario: Reduce Transparency falls back to opaque
- **WHEN** Reduce Transparency (or Increase Contrast requiring opacity) is enabled
- **THEN** day group headers render over an opaque fill and label and total subline remain fully legible

## ADDED Requirements

### Requirement: Pinned header stays legible over dense content on iPad
On regular-width (iPad) panes the pinned day group header SHALL keep the day label and the total subline simultaneously legible over scrolling entry rows in light and dark appearances, with no opaque seam against the navigation bar and no label/subline overlap at any supported Dynamic Type size.

#### Scenario: iPad landscape pinned header
- **WHEN** the user scrolls History on an iPad landscape pane so a day header pins
- **THEN** the day label and the total subline are both readable over the blurred rows beneath, with the header band visually continuous with the navigation bar

#### Scenario: Large Dynamic Type keeps label and subline apart
- **WHEN** the device uses an accessibility-large Dynamic Type size
- **THEN** the day label and the total subline do not overlap or clip

### Requirement: List content passes under the glass tab bar
The History list SHALL extend its scroll content beneath the bottom tab bar so rows blur behind the glass mid-scroll (TestFlight parity); the bottom content inset SHALL keep the final row fully reachable above the tab bar and above the compact timer when it is shown.

#### Scenario: Rows blur beneath the tab bar
- **WHEN** the user scrolls History so content crosses the tab-bar line
- **THEN** rows pass visibly blurred beneath the bar with no hard cut at its top edge

#### Scenario: Final row reachable with and without the compact timer
- **WHEN** the compact timer is shown or hidden
- **THEN** the last entry row scrolls fully above the timer/tab-bar chrome (no row permanently obscured)
