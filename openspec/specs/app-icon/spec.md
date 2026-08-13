# app-icon Specification

## Purpose

Defines the approved visual identity used for the Time of Life iOS application icon and the platform configurations in which that identity must be available.

## Requirements

### Requirement: Approved artwork is the shipped app icon
The iOS application SHALL use the approved icon artwork from `Design/icon/ios/` without substituting placeholder or system-provided imagery.

#### Scenario: Installed app is shown by the operating system
- **WHEN** the Time of Life application is installed on a supported iPhone or iPad
- **THEN** the operating system displays the approved Time of Life artwork as the application icon

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
