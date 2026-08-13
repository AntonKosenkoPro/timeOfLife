## Why

The iOS target currently has an empty app-icon catalog, so builds do not present the finished Time of Life identity. The approved, platform-sized artwork already exists under `Design/icon/ios/` and should become the authoritative source for the application icon.

## What Changes

- Populate the iOS `AppIcon.appiconset` with the supplied artwork and matching asset-catalog metadata.
- Ensure every icon slot required by the iOS 15+ phone, tablet, CarPlay, and App Store configurations resolves to the intended image.
- Verify the generated Xcode project and iOS build compile the asset catalog without missing-icon warnings.
- Document `Design/icon/ios/` as the source artwork for future app-icon updates.
- Non-goals: changing in-app branding, adding alternate icons, generating new artwork, or integrating the sibling Android and web icon packages into targets that do not exist in this repository.

## Capabilities

### New Capabilities
- `app-icon`: Defines the shipped iOS application icon and required asset-catalog coverage from the approved design package.

### Modified Capabilities

None.

## Impact

- Affected files: `Design/icon/ios/`, `ios/TimeOfLife/TimeOfLife/Resources/Assets.xcassets/AppIcon.appiconset/`, and relevant design/project documentation.
- Build system: Xcode asset-catalog compilation and XcodeGen verification; no hand edits to the generated `.pbxproj`.
- APIs, backend, persisted data, dependencies, and localization are unaffected.
