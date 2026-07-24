---
description: |
  Use when iterating on iOS SwiftUI UI in the TimeOfLife app. Builds the app,
  launches it seeded to a chosen screen on the iOS Simulator, captures the
  accessibility tree as compact text via the ios-sim MCP server, and closes the
  edit → build → capture loop without screenshots.
tools:
  - bash
  - mcp
---

# iOS UI feedback loop

This skill drives the iOS Simulator, reads the running UI as text through its
accessibility tree, and lets you iterate on SwiftUI quickly.

## What it does

1. Builds the TimeOfLife app in Debug.
2. Installs it on the booted iOS Simulator.
3. Launches it seeded to a chosen screen (`emailEntry`, `otpEntry`, `signedIn`,
   `signedInConfirmation`) using a DEBUG-only, stub-backed container — no real
   network or OTP.
4. Captures the accessibility tree via the `ios-sim` MCP server (`get_ui_tree`).
5. You read the tree, edit the SwiftUI, rebuild, re-capture, repeat.

## One-time setup

The agent must already have:

- `ios-mcp-server` registered: `claude mcp add -s user ios-sim -- npx -y ios-mcp-server`
- A booted iOS Simulator (the user normally keeps `iPhone 17` booted).

Verify with `claude mcp list`.

`ios-mcp-server` is a no-idb, no-Appium simulator MCP. It reads the AX tree
natively via `simtree` (AXPTranslation/CoreSimulator) and taps/types via
`simtouch` (IndigoHID). It does **not** need macOS Accessibility permissions.

## Build + install + launch seeded

Use Bash. Replace `<screen>` with one of:

- `emailEntry` — auth-flow root with the email field.
- `otpEntry` — OTP screen pre-seeded for `user@example.com`.
- `signedIn` — signed-in landing screen (`TimerView`).
- `signedInConfirmation` — the post-verify `SignedInView` inside `AuthFlowView`.

```bash
cd /Users/antonkosenko/work/timeOfLife/ios/TimeOfLife
xcodegen generate
xcodebuild build -scheme TimeOfLife \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -derivedDataPath /tmp/tol-build

UDID=$(xcrun simctl list devices booted -j | python3 -c "
import sys, json
d = json.load(sys.stdin)['devices']
print(next(x['udid'] for v in d.values() for x in v if x['state'] == 'Booted'))
")
APP=/tmp/tol-build/Build/Products/Debug-iphonesimulator/TimeOfLife.app
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" com.antonkosenko.timeoflife 2>/dev/null
xcrun simctl launch "$UDID" com.antonkosenko.timeoflife SIMCTL_CHILD_UITEST_SCREEN=<screen>
```

`simctl launch` forwards `SIMCTL_CHILD_UITEST_SCREEN` as a launch argument (not an
environment variable) on modern simulators. The app parses it via
`ProcessInfo.processInfo.arguments` and routes to a DEBUG-only UI-testing
container.

## Capture the UI as text

After the app settles (≈1–2 s), call the MCP tool:

```
ios-sim get_ui_tree
```

Read the returned text. It looks like:

```
<App name="TimeOfLife" ...>
  <Window>
    <Button label="Continue" identifier="" rect="..." enabled="true" .../>
    <TextField label="Email" identifier="EmailField" rect="..." .../>
    <StaticText label="Welcome" .../>
  </Window>
</App>
```

Use the accessibility identifiers that already exist (`EmailField`,
`EmailErrorBanner`, `OtpField`, `OtpResendButton`, `OfflineBanner`) and add
`accessibilityId:` to every new interactive element so it appears queryable in
the tree.

## Iterate

Compare the tree to the design intent. Edit the SwiftUI, then rebuild + install
+ launch + `get_ui_tree` again. Stop when the tree matches.

Project conventions to preserve:

- Use `Theme` semantic colors (no raw `Color` literals).
- Add user-facing strings to both `en.lproj` and `ru.lproj`, and to `L10n`.
- Add `accessibilityId:` on new interactive elements.
- Keep view models `@MainActor` and dependencies injected via `AppContainer`.

## Optional: drive the real flow

`ios-mcp-server` can also tap and type. Because the UI-testing container uses a
stub `AuthRepository`, you can drive the passwordless flow without a real email:

1. Launch with `SIMCTL_CHILD_UITEST_SCREEN=emailEntry`.
2. `ios-sim tap_element label="Email"` (or `id=EmailField`).
3. `ios-sim type_text text=user@example.com`.
4. `ios-sim tap_element label="Continue"`.
5. `ios-sim get_ui_tree` to confirm the OTP screen appeared.
6. `ios-sim type_text text=123456` then `tap_element label="Verify"`.

Use `wait_for_element` after a navigation/tap to avoid sleep-based waits.

### Typing emails and codes

`type_text` uses the macOS pasteboard under the hood. In restricted
environments this may fail with a `pbcopy` error. The reliable fallback is to
tap the focused field, then use `tap_sequence` with keyboard-key coordinates
from `get_ui_tree` (the server exposes each key as a labeled `Button` with its
center point). For example, after focusing `EmailField`, tap `t`, `e`, `s`,
`t`, `@`, `t`, `e`, `s`, `t`, `.`, `c`, `o`, `m` using the coordinates the tree
reports.

## Caveats

- This is a text representation of the accessibility tree — great for structure,
  labels, IDs, and frames; not for pixel-perfect color/layout verification. Add a
  screenshot channel later via `ios-sim screenshot` if needed.
- The UI-testing container is DEBUG-only and never ships in Release builds.