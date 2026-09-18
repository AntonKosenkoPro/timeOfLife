## MODIFIED Requirements

### Requirement: Approved artwork is the shipped app icon
The iOS application SHALL use the approved icon artwork from `Design/icon/ios/` without substituting placeholder or system-provided imagery.

#### Scenario: Installed app is shown by the operating system
- **WHEN** the Lifio application is installed on a supported iPhone or iPad
- **THEN** the operating system displays the approved Lifio artwork as the application icon

#### Scenario: App Store presentation is prepared
- **WHEN** the application icon catalog is validated for distribution
- **THEN** the 1024-by-1024 App Store slot resolves to the approved marketing artwork
