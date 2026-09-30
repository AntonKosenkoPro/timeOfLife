## Purpose

Defines how the app's version is numbered, bumped, and tagged so every TestFlight build is traceable from the Profile row back to a single repo commit.

## Requirements

### Requirement: Marketing version follows semantic versioning
The released marketing version SHALL be a three-component semantic version `MAJOR.MINOR.PATCH` (e.g. `1.0.0`). The existing two-component `1.0` is normalized to three components on the first bump and SHALL NOT reappear afterward.

#### Scenario: First bump normalizes the version
- **WHEN** the current version is the legacy two-component `1.0`
- **THEN** the next released marketing version is a three-component version strictly greater than `1.0.0`

#### Scenario: Non-semver input is rejected
- **WHEN** a requested version is not `X.Y.Z` numeric semver (e.g. `1.0`, `v1.0.0`, `1.0.0-beta`)
- **THEN** the release flow refuses it with a clear message and changes nothing

### Requirement: Manual release bump with automatic build number
A release SHALL be triggered manually with the desired marketing version as its only version parameter. The flow SHALL refuse the request unless it runs on the `main` branch, the requested version is valid semver strictly greater than the current version, and the working tree is clean. On acceptance it SHALL set the marketing version to the requested value, increment the build number by exactly +1, and record both in a single commit on `main`.

#### Scenario: Successful bump
- **WHEN** version `1.0.0` is requested on `main` while the current version is lower and the tree is clean
- **THEN** a single commit lands on `main` with marketing version `1.0.0` and the build number incremented by one

#### Scenario: Downgrade or repeat is rejected
- **WHEN** the requested version is equal to or lower than the current version
- **THEN** the flow refuses it with a clear message and changes nothing

#### Scenario: Off-main or dirty tree is rejected
- **WHEN** the flow is triggered outside `main` or with uncommitted changes present
- **THEN** the flow refuses to run and changes nothing

#### Scenario: Re-upload without a new marketing version
- **WHEN** a second TestFlight upload is needed for the same marketing version (e.g. a tester fix)
- **THEN** the build number is incremented without changing the marketing version, keeping the upload acceptable to App Store Connect

### Requirement: Release tag convention
Every marketing-version bump commit on `main` SHALL carry exactly one annotated tag named `v<marketing-version>` (e.g. `v1.0.0`) pointing at the bump commit. Tags SHALL be created only on `main` and SHALL never be moved once pushed. Rebuild commits (same marketing version, incremented build — the re-upload case above) SHALL NOT create or move a tag: the existing `v<marketing-version>` tag keeps identifying the marketing release while the build number identifies the exact commit.

#### Scenario: Tag lands with the bump
- **WHEN** a release bump commit lands on `main` for version `1.0.0`
- **THEN** the annotated tag `v1.0.0` points at that commit and is pushed

#### Scenario: Rebuild reuses the existing tag
- **WHEN** a rebuild commit lands for the same marketing version with a higher build number
- **THEN** no tag is created or moved, and the existing `v1.0.0` tag still points at the original bump commit

#### Scenario: Tag matches the app label
- **WHEN** a tester reads the Profile version row `1.0.0 (4)` from a TestFlight build
- **THEN** the tag `v1.0.0` plus the build number identifies the exact commit the build came from
