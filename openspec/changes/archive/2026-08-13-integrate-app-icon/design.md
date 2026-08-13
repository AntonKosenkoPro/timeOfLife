## Context

See `proposal.md` for motivation and `specs/app-icon/spec.md` for the observable contract. The app target already selects the `AppIcon` asset catalog through Xcode's standard app-icon setting, but its catalog contains only an unassigned universal 1024-point slot. `Design/icon/ios/` contains 21 rendered PNGs plus a complete `Contents.json` covering iPhone, iPad, CarPlay, and iOS marketing roles.

The Xcode project is generated from `project.yml`; implementation must not hand-edit the generated project. This change does not touch SwiftUI colors, localization, data storage, or backend contracts.

## Goals / Non-Goals

**Goals:**
- Install the approved iOS icon package into the target's existing `AppIcon.appiconset` without image transformation.
- Keep source artwork and shipped catalog relationships explicit and reviewable.
- Validate both catalog metadata and image dimensions before relying on the Xcode build.

**Non-Goals:**
- Redesign, crop, recolor, optimize, or regenerate the supplied PNG files.
- Introduce alternate, dark, or tinted iOS icons beyond the supplied package.
- Add Android or web application targets.

## Decisions

### Copy the complete supplied iOS package into the existing catalog

The implementation will replace the placeholder `Contents.json` and copy all referenced PNGs from `Design/icon/ios/` into `Assets.xcassets/AppIcon.appiconset/`. Keeping the provided filenames and metadata together minimizes transcription errors and preserves the producer's device-role mapping.

Alternative considered: collapse the package to Xcode's single universal 1024-point icon and let the toolchain derive variants. This was rejected because the approved package deliberately includes device- and role-specific assets, the project supports iOS 15, and preserving explicit slots makes required coverage independently verifiable.

### Treat design assets as source material and the asset catalog as build input

`Design/icon/ios/` remains the authoritative approved package. The app catalog contains a checked-in copy because Xcode asset catalogs require their image files to reside in the app-icon set. `Design/README.md` will document this flow so future updates replace the source package first and then synchronize the catalog.

Alternative considered: point the catalog outside `Assets.xcassets` or add a build-time copy script. This was rejected because external references are not the standard asset-catalog model and a script would add build complexity for infrequent icon updates.

### Validate metadata, pixels, and compilation

Verification will check that every filename declared by `Contents.json` exists in the target catalog and has pixel dimensions equal to `size × scale`. Then XcodeGen, strict SwiftLint, an iOS build, and the iOS test suite will run according to the repository iteration contract. The image checks catch deterministic packaging errors; the build catches asset-compiler integration errors.

Alternative considered: rely only on visual inspection or build success. This was rejected because visual inspection does not prove exact dimensions and some catalog omissions can remain warnings rather than hard failures.

## Risks / Trade-offs

- [Duplicating source PNGs increases repository size] → Accept the small, bounded duplication so the approved package remains independently traceable and the Xcode catalog remains self-contained.
- [A future source update can drift from the shipped catalog] → Document the synchronization rule and verify referenced filenames and dimensions during implementation.
- [Legacy icon slots include more images than newer universal catalogs] → Preserve them because they are valid for the iOS 15+ deployment range and are already provided; revisit only alongside a deployment-target change.

## Migration Plan

1. Copy the supplied catalog metadata and referenced images into the existing app-icon set.
2. Validate file coverage and dimensions, regenerate the Xcode project, and run iOS quality checks.
3. Confirm the icon in a simulator installation as a manual smoke check when a simulator is available.

Rollback consists of restoring the previous placeholder app-icon catalog; no data or API migration is involved.
