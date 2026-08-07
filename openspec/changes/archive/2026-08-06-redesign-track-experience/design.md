## Context

See `proposal.md` for motivation and the `app-shell` and `timer-capture-experience` specs for observable behavior. The current app routes authentication before `TimerView`; the existing screen uses a focused free-text field, a digital timer, and a pinned Start/Stop button. The DEBUG design study explored several visual variants, but its `TODAY` and `RECENT` content was illustrative rather than tied to product behavior.

The redesign must align with the separate `local-first-sync-architecture` change: unsigned launch, persisted running state, optional account sync, and an App Group store. It must support iOS 15 while allowing modern system styling through availability guards, use semantic `Theme` colors, localize all copy in English and Russian, and provide a hierarchy that can later map to macOS.

## Goals / Non-Goals

**Goals:**
- Give timer capture one obvious path with explicit selection, Start, Stop, and save states.
- Make the numeric timer and its surrounding state correspond directly to elapsed time or interaction state.
- Separate capture, review, and analysis without making low-frequency configuration a peer destination.
- Preserve timer awareness while the user browses the rest of the app.
- Produce equivalent first-class light and dark appearances using native typography and controls.

**Non-Goals:**
- Implement the complete History, Insights, subscription, integration, widget, Control, or macOS feature sets in this change.
- Turn the numeric timer into a daily summary, goal indicator, or decorative activity visualization.
- Replace standard sheets, tab navigation, search, lists, alerts, or accessibility behavior with custom interaction models.
- Change backend APIs or the local-first persistence design.

## Decisions

### D1 - Track, History, and Insights are the primary destinations
**Choice:** Use an iOS tab container with Track, History, and Insights. Track is initially selected. Profile is opened from a consistent top-trailing person control and is not a fourth tab.

**Rationale:** Capture, retrospective review, and interpretation are durable user intents with different frequencies and information density. A tab per intent keeps History discoverable and maps directly to a future macOS sidebar. Profile contains lower-frequency configuration and optional account state, so promoting it to a tab would overstate its importance.

**Alternatives considered:** A single Track root with a History sheet hides the retention loop and scales poorly to macOS. A two-tab shell makes Insights harder to discover as it matures. A Settings tab spends persistent navigation on infrequent work.

### D2 - The numeric timer is a pure start instrument
**Choice:** Track uses a centered numeric readout with no dial, ring, sweep, daily-total, goal, or decorative progress visualization. The readout carries the exact elapsed time, including hours, and remains in the same central region across ready, running, saving, and saved states.

**Rationale:** The user rejected the Dial entirely and chose a centered numeric treatment. Exact numbers are sufficient for capture, while History and Insights own retrospective meaning.

**Alternatives considered:** Dials, rings, and decorative progress add visual meaning that does not help start/stop capture. A 24-hour timeline conflates capture with review. Daily goal progress requires a goal before the timer is useful.

### D3 - Activity selection is a native sheet
**Choice:** Tapping the selected activity affordance opens a searchable sheet. It shows recent Activity names before search, filtered Activity-name matches while typing, `Create “Name”` for valid unmatched input, and Manage Activities as a secondary destination. Category names and icons are not shown in this capture chooser. Selecting or creating prepares the Activity and dismisses the sheet.

**Rationale:** The main screen stays calm and numeric while the sheet handles a potentially large Activity catalog with familiar search and keyboard behavior. Categories are optional analytics metadata and should not compete with the concrete task being selected.

**Alternatives considered:** A permanent text field makes the keyboard part of the home screen and weakens the selected-activity state. Starting immediately from a recent row is faster but easier to trigger accidentally and behaves differently from search/create.

### D4 - Start is explicit and Stop is spatially stable
**Choice:** Selection enters a ready state; a separate Start action begins timing. The same central/lower control region changes from Start to Stop without moving. After Stop succeeds, a restrained saved confirmation appears and the same activity remains prepared.

**Rationale:** Explicit Start is predictable across recents, search, and creation. Stable geometry supports muscle memory and avoids the current screen's state-dependent composition. Retaining selection makes repeated sessions quick while still requiring explicit confirmation.

### D5 - A compact timer is inset above non-Track tabs
**Choice:** While running, History and Insights show a compact timer immediately above the tab bar. Its main area returns to Track; a separate Stop button saves in place. Track does not duplicate it because the full numeric timer is already visible.

**Rationale:** A running timer is global app state and must not disappear when navigation changes. A bottom safe-area inset stays close to primary navigation, avoids covering content, and creates a visual grammar reusable by widgets and Live Activities.

**Alternatives considered:** A persistent status item in the navigation bar has too little room for Activity, duration, and Stop. Forcing a return to Track to stop adds navigation friction. Showing the full numeric timer everywhere overwhelms History and Insights.

### D6 - Profile is useful without an account
**Choice:** The person control opens Profile for all users. Its account section offers Enable Sync when signed out and sync/account management when signed in; local activity/category management, integrations, export, appearance, and data controls remain accessible independently.

**Rationale:** Local-first behavior means “profile” cannot be shorthand for a mandatory remote identity. Keeping one destination avoids separate Settings and Account concepts while preserving the user's chosen profile model.

### D7 - Motion and haptics explain state rather than decorate it
**Choice:** Start uses a subtle selection haptic, Stop/save uses success feedback, and invalid input uses error feedback. The elapsed sweep updates continuously or discretely according to performance, but state transitions remain restrained. Reduce Motion replaces rotational/spring transitions with fades or immediate updates.

**Rationale:** Physical feedback marks consequential state changes without making routine navigation noisy. Motion must clarify readiness, running, and saved state and remain optional.

### D8 - Prototype states precede production replacement
**Choice:** First implement a DEBUG-only interactive Track flow containing first-use, chooser, ready, running, saved, and cross-tab compact-timer states. Once reviewed, update the canonical design documents and replace production `TimerView` through separately verifiable tasks.

**Rationale:** The current design board proved visual direction but not behavior. An interactive behavioral prototype exposes hierarchy and transition errors before persistence, localization, and production navigation are disturbed.

### D9 - Activities and Categories are separate concepts
**Choice:** An Activity is the concrete task required for timer capture. A Category is optional metadata used for management and Insights; an Activity may have zero or more Categories. Capture suggestions show Activity names only. Activity editing may assign or remove Categories, while Categories have their own management and editor surface.

**Rationale:** The user thinks in terms of a specific task while timing and a broad analytical lens while reviewing. Keeping the concepts separate allows quick categoryless creation without weakening later analysis.

**History rule:** Entries reference their Activity and resolve its current Categories at query time. Changing an Activity's Categories therefore reclassifies its existing history.

## Risks / Trade-offs

- **[Profile can imply an account in a local-first app]** -> Keep local settings visible at all times and phrase remote identity as optional “Enable Sync.”
- **[Three tabs may initially contain sparse History and Insights screens]** -> Introduce honest empty states and implement the shell alongside the first useful History slice; do not fill destinations with fake data in production.
- **[Large numeric readout can reduce context]** -> Keep the selected Activity name and explicit labeled Start/Stop action close to the readout, and test VoiceOver and Dynamic Type.
- **[Compact Stop can be activated accidentally]** -> Give it a distinct 44-point target separated from the navigation area and immediately provide the standard undo/edit path after saving.
- **[DEBUG prototype can drift from production design]** -> Treat approved prototype states as inputs to `Design/` specifications, then delete the design-lab route when production implementation is accepted.

## Migration Plan

1. Build and review the DEBUG Track flow without changing production launch behavior.
2. Update `Design/SCREENS/TimeTracking.md`, navigation and interaction rules, component contracts, and both localization catalogs.
3. Land the local-first unsigned root and persisted timer-state prerequisites from the architecture change.
4. Introduce the tab shell and Profile destination with honest History/Insights empty states.
5. Replace the existing timer composition with the approved chooser and numeric timer state machine.
6. Add the compact cross-tab timer and complete accessibility, localization, unit, and UI verification.
7. Remove the DEBUG design-lab board and its launch argument after production acceptance.

Rollback is a source-level revert to the existing timer root. No backend or released local-data migration is required because the app is unreleased and this change adds no persisted schema of its own.
