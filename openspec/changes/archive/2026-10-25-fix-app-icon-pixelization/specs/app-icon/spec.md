# app-icon Specification (delta)

## Purpose

Harden the shipped icon artwork so it stays crisp through Apple's listing derivatives and at small render sizes. Baseline requirements (approved artwork, role coverage, `Design/icon/ios/` traceability) are unchanged.

## ADDED Requirements

### Requirement: Listing derivatives preserve the glyph

The shipped 1024 marketing artwork SHALL survive store-listing processing (downscale to ~150px plus lossy recompression) with the `^▬` brand glyph still clean-edged and near-white, without texture mottling.

#### Scenario: TestFlight public listing renders the beta icon
- **WHEN** the TestFlight public listing serves its processed icon derivative
- **THEN** the white glyph renders without dullness or blotchy background noise at the listing's display size

#### Scenario: Derivative compared against the master
- **WHEN** the served listing derivative is diffed against the master artwork resized to the same dimensions
- **THEN** glyph-interior luminance stays near-white and edge transitions stay within antialiasing width (thresholds recorded in `tasks.md` verification)

### Requirement: Small slots render with antialiased edges

Home-screen and system slots derived from the master SHALL preserve antialiased edges (no 1px hard steps from naive downsampling) at 120px and 180px.

#### Scenario: Home-screen icon is inspected at pixel level
- **WHEN** the 120px / 180px slot PNGs are edge-profiled across the glyph
- **THEN** straight edges show multi-pixel antialiased transitions matching a high-quality downsample of the master, not single-step jumps

#### Scenario: Icon renders on device
- **WHEN** the app is installed on a supported iPhone
- **THEN** the home-screen and TestFlight-app icon renders crisp with no visible pixelization at standard viewing distance
