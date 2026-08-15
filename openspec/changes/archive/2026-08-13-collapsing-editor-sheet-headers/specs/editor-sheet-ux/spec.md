## Purpose

Defines the shared presentation contract for editor sheets (Category create/edit, Activity edit/refine, and future quick-create): a system-owned collapsing large-title header with an always-available Cancel affordance, rendered by one reusable scaffold.

## ADDED Requirements

### Requirement: Editor sheets present a native collapsing header
Every editor sheet SHALL present its title as a native large title below the top bar at rest, with a Cancel affordance in the top bar. When the user scrolls the sheet content, the title SHALL collapse into the top bar and the bar SHALL display the title inline next to Cancel while content scrolls beneath it. When the user returns to the top edge, the title SHALL expand back to its large form. The collapse, expansion, bar material, and animation SHALL be provided by the operating system, not by custom views or scroll-offset tracking.

#### Scenario: Editor opens at rest
- **WHEN** an editor sheet is presented
- **THEN** the large title is visible in the content area and the Cancel affordance is visible in the top bar, with no additional header changes

#### Scenario: User scrolls the editor content
- **WHEN** the user scrolls the editor sheet downward
- **THEN** the title collapses into the top bar, an inline title appears next to Cancel, the bar gains its material background, and content scrolls beneath the bar without overlapping Cancel

#### Scenario: User returns to the top
- **WHEN** the user scrolls the editor sheet back to its top edge
- **THEN** the title expands back to its large form and the at-rest presentation is restored

#### Scenario: Cancel during scrolling
- **WHEN** the user scrolls the editor sheet and activates Cancel
- **THEN** the sheet dismisses without saving and any draft is discarded, exactly as at rest

### Requirement: Every editor sheet shares one header scaffold
All editor sheets in the app SHALL render their header, Cancel affordance, scroll container, and pinned bottom action bar through a single shared scaffold. New editor sheets SHALL reuse the scaffold rather than introducing bespoke header implementations.

#### Scenario: Category editor uses the shared scaffold
- **WHEN** the Category editor is presented in create or edit mode
- **THEN** it renders through the shared scaffold with its create or edit title and its Cancel affordance

#### Scenario: Activity editor uses the shared scaffold
- **WHEN** the Activity editor is presented in edit or refine mode
- **THEN** it renders through the shared scaffold with its edit title and its Cancel affordance

#### Scenario: A future editor sheet is added
- **WHEN** a new editor sheet is added to the app
- **THEN** it uses the shared scaffold and inherits the collapsing-header behavior without new header code

### Requirement: Cancel affordance respects saving state
The Cancel affordance in an editor sheet SHALL be disabled while a save is in flight, and interactive swipe-down dismissal SHALL remain disabled for the same period, preserving the existing behavior that an in-flight save is never lost to cancellation.

#### Scenario: Cancel while saving
- **WHEN** the user activates Cancel or attempts swipe-down dismissal while the editor is saving
- **THEN** the affordances do not dismiss the sheet and the save continues to completion or failure

### Requirement: Keyboard-safe pinned action bar is preserved
Editor sheets SHALL keep their primary action pinned above the keyboard via the bottom safe-area inset, and the scrollable content SHALL reserve the measured height of that bar so no field is permanently hidden behind it. The collapsing header SHALL NOT interfere with the pinned bar or its keyboard-following behavior.

#### Scenario: Keyboard appears in an editor with the collapsing header
- **WHEN** the editor opens and focuses its name field
- **THEN** the pinned action bar follows the keyboard, the reserved scroll space matches the bar height, and the collapsing header continues to behave normally
