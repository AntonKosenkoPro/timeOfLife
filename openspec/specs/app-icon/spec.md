# app-icon Specification

## Purpose

Defines the approved visual identity used for the Lifio iOS application icon and the platform configurations in which that identity must be available.

## Requirements

### Requirement: Approved artwork is the shipped app icon
The iOS application SHALL use the approved icon artwork from `Design/icon/ios/` without substituting placeholder or system-provided imagery.

#### Scenario: Installed app is shown by the operating system
- **WHEN** the Lifio application is installed on a supported iPhone or iPad
- **THEN** the operating system displays the approved Lifio artwork as the application icon

#### Scenario: App Store presentation is prepared
- **WHEN** the application icon catalog is validated for distribution
- **THEN** the 1024-by-1024 App Store slot resolves to the approved marketing artwork

### Requirement: Supported iOS icon roles are complete
The iOS application SHALL provide valid approved artwork for every app-icon role declared for its supported iPhone, iPad, CarPlay, and App Store configurations, including all required scales.

#### Scenario: Asset catalog is compiled
- **WHEN** the iOS target compiles its asset catalog
- **THEN** every declared app-icon slot resolves to an image with the required dimensions and scale
- **THEN** compilation reports no missing or unassigned app-icon image warnings

### Requirement: Icon source is traceable
The project SHALL identify `Design/icon/ios/` as the authoritative source package for the shipped iOS app-icon catalog.

#### Scenario: A future icon update is prepared
- **WHEN** a maintainer needs to replace or regenerate the application icon assets
- **THEN** project documentation directs the maintainer to the approved source package and the target asset catalog

### Requirement: Listing derivatives preserve the glyph
The shipped 1024 marketing artwork SHALL survive store-listing processing (downscale to ~150px plus lossy recompression) with the `^▬` brand glyph still clean-edged and near-white, without texture mottling.

#### Scenario: TestFlight public listing renders the beta icon
- **WHEN** the TestFlight public listing serves its processed icon derivative
- **THEN** the white glyph renders without dullness or blotchy background noise at the listing's display size

#### Scenario: Derivative compared against the master
- **WHEN** the served listing derivative is diffed against the master artwork resized to the same dimensions
- **THEN** glyph-interior luminance stays near-white and edge transitions stay within antialiasing width (thresholds recorded in the originating change's `tasks.md` verification)

### Requirement: Small slots render with antialiased edges
Home-screen and system slots derived from the master SHALL preserve antialiased edges (no 1px hard steps from naive downsampling) at 120px and 180px.

#### Scenario: Home-screen icon is inspected at pixel level
- **WHEN** the 120px / 180px slot PNGs are edge-profiled across the glyph
- **THEN** straight edges show multi-pixel antialiased transitions matching a high-quality downsample of the master, not single-step jumps

#### Scenario: Icon renders on device
- **WHEN** the app is installed on a supported iPhone
- **THEN** the home-screen and TestFlight-app icon renders crisp with no visible pixelization at standard viewing distance
