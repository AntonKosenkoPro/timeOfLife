## 1. Behavioral Prototype

- [x] 1.1 Replace the abstract visual comparison route with an interactive DEBUG-only Track flow covering chooser, ready, running, saved, and cross-tab running states using the centered numeric timer
- [x] 1.2 Render and review the prototype in light and dark appearance on a supported iPhone simulator
- [x] 1.3 Verify prototype accessibility labels and primary interaction targets through simulator discovery; Dynamic Type and Reduce Motion remain production verification work
- [x] 1.4 Add a DEBUG-only Activity/Category relationship study with separate management surfaces, categoryless creation, and optional multi-category assignment

## 2. Canonical Design Documentation

- [x] 2.1 Rewrite `Design/SCREENS/TimeTracking.md` around the approved Track state machine and Activity-only capture chooser
- [x] 2.2 Document the Track/History/Insights shell, Profile ownership, and compact timer in the relevant screen and interaction specifications
- [x] 2.3 Add numeric timer and Activity-only chooser contracts to `Design/COMPONENTS.md` and update semantic tokens if required
- [x] 2.4 Reconcile local-first, offline, authentication, sign-out, and undo wording across design and requirements documents

## 3. Localization and Navigation Foundation

- [x] 3.1 Add English and Russian strings for Track navigation, numeric timer states, chooser, saved feedback, Profile, and destination empty states
- [x] 3.2 Add localization enum cases and update localization completeness tests
- [x] 3.3 Introduce Track, History, and Insights root routes with stable tab accessibility identifiers
- [x] 3.4 Add the Profile destination and route account, sync, catalog, integrations, export, appearance, and data controls through it

## 4. Production Track Experience

- [x] 4.1 Implement a testable Track state model for no selection, ready, running, saving, saved, and recoverable error states
- [x] 4.2 Implement the activity chooser with recency ordering, search, case-insensitive reuse, create, empty state, and Manage Activities entry point
- [x] 4.3 Implement the accessible centered numeric timer with exact digital duration and no secondary progress visualization
- [x] 4.4 Connect explicit Start and stable Stop actions to the local-first timer service and persisted running state
- [x] 4.5 Add saved feedback, required haptics, idle-timer handling, Reduce Motion handling, and state restoration
- [x] 4.6 Add the compact timer above the tab bar on History and Insights with return-to-Track and in-place Stop actions

## 5. Tests and Verification

- [x] 5.1 Add unit tests for Track state transitions, elapsed formatting, selection-before-start, stop success, and recoverable save failure
- [x] 5.2 Add unit tests for activity filtering, case-insensitive reuse, creation, empty catalog, and recency ordering
- [x] 5.3 Add navigation tests for unsigned Track launch, tab state preservation, Profile return, and compact timer behavior
- [x] 5.4 Add accessibility tests for numeric timer semantics, compact timer actions, Dynamic Type, and Reduce Motion
- [x] 5.5 Run `xcodegen generate`, strict SwiftLint, warning-as-error iOS build, and the complete iOS test suite
- [x] 5.6 Manually verify first-use, ready, running, saved, cross-tab Stop, light/dark, English/Russian, and relaunch recovery flows in the simulator

## 6. Cleanup

- [x] 6.1 Remove the DEBUG design-lab routes and comparison board after the production Track experience is accepted
- [x] 6.2 Update `AGENTS.md` and README for the final navigation and run/test behavior if architecture or workflow guidance changed
