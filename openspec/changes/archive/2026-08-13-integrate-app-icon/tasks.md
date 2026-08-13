## 1. Integrate Icon Assets

- [x] 1.1 Replace the placeholder `AppIcon.appiconset/Contents.json` with the approved `Design/icon/ios/Contents.json` metadata.
- [x] 1.2 Copy every PNG referenced by the approved metadata into the target `AppIcon.appiconset` without transforming the images.
- [x] 1.3 Verify each catalog filename exists and each PNG's pixel dimensions equal its declared point size multiplied by scale.

## 2. Documentation And Requirements

- [x] 2.1 Update `Design/README.md` to identify `Design/icon/ios/` as the authoritative source and document synchronization to the target asset catalog.
- [x] 2.2 Re-check relevant FURPS visual/usability requirements and update durable project documentation if the icon integration changes any documented architecture or visual workflow.

## 3. Verification

- [x] 3.1 Run `xcodegen generate` and `swiftlint lint --strict` from `ios/TimeOfLife/` and fix all findings.
- [x] 3.2 Build the `TimeOfLife` scheme for an iOS Simulator destination and confirm asset compilation emits no missing or unassigned app-icon warnings.
- [ ] 3.3 Run the complete iOS test suite on an available simulator and keep it green.
- [x] 3.4 Install or launch the built app on an available simulator and visually confirm the approved icon appears on the system surface.
- [x] 3.5 Run `openspec validate integrate-app-icon --strict` and mark completed tasks in this checklist.
