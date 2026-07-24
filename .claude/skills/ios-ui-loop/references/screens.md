# UI-feedback screens reference

Quick lookup for the `SIMCTL_CHILD_UITEST_SCREEN` values used by the
`ios-ui-loop` skill.

| Screen | Launch argument | What renders |
|---|---|---|
| `emailEntry` | `SIMCTL_CHILD_UITEST_SCREEN=emailEntry` | `EmailEntryView` (auth-flow root). |
| `otpEntry` | `SIMCTL_CHILD_UITEST_SCREEN=otpEntry` | `OtpEntryView` pre-filled for `user@example.com`. |
| `signedIn` | `SIMCTL_CHILD_UITEST_SCREEN=signedIn` | `TimerView` (signed-in landing screen). |
| `signedInConfirmation` | `SIMCTL_CHILD_UITEST_SCREEN=signedInConfirmation` | `SignedInView` inside `AuthFlowView`. |

All screens use the DEBUG-only `AppContainer.uiTesting(screen:)` graph with an
in-memory keychain and a stub `AuthRepository`, so no real network or OTP is
required.

## Common build/install/launch snippet

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
xcrun simctl launch "$UDID" com.antonkosenko.timeoflife SIMCTL_CHILD_UITEST_SCREEN=otpEntry
```

Then run `ios-sim get_ui_tree` once the app settles.