## Why

Profile currently opens as a sheet containing its own `NavigationStack`, with a right-sided Done button to dismiss; Manage Categories pushes inside that sheet's stack. The sheet-nested stack produces non-standard navigation chrome (Done where every other destination uses `<` back) and the Categories push inherits the sheet's presentation context. Making Profile a pushed page aligns it with every other destination in the app.

## What Changes

- Profile opens as a pushed page on the current tab's `NavigationStack` (automatic `<` back button) instead of a sheet; the Done button is removed.
- Manage Categories keeps pushing from Profile (now inside the tab's page stack instead of the sheet's stack); the category editor remains a sheet.
- Exiting Profile back to a tab reloads `TrackViewModel` (replaces the sheet's `onDismiss` reload), so categories created in Profile are immediately toggleable on Track.
- No changes to Profile rows, sync behavior, sign-out, erase flow, strings, or the category editor.

**Non-goals:** the iOS 26 Liquid Glass toolbar-item interpolation during pushes (issue #101's morph) is platform behavior — six fix rounds (glass transition, conditional transaction, semantic placement, stable item id, own circular glass, glyph transition) all failed on device, so the code is deliberately left as before and the remainder is tracked in #101. This change does not alter the morph.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `app-shell`: Profile is a pushed page (back navigation, no Done/dismiss) rather than a sheet; exiting it restores the tab and reloads Track data.

## Impact

- `AppShellView` (sheet → per-tab `navigationDestination`, exit-reload trigger), `ProfileView` (drop inner `NavigationStack` + Done + `dismiss` env).
- Accessibility: Done button identifier goes away; back navigation uses the system Back item.
- No backend, OpenAPI, FURPS-behavior, or string changes.
