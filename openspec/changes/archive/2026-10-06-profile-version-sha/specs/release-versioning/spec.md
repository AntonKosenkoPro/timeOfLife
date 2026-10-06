## MODIFIED Requirements

### Requirement: Release tag convention
Every marketing-version bump commit on `main` SHALL carry exactly one annotated tag named `v<marketing-version>` (e.g. `v1.0.0`) pointing at the bump commit. Tags SHALL be created only on `main` and SHALL never be moved once pushed. Rebuild commits (same marketing version, incremented build — the re-upload case above) SHALL NOT create or move a tag: the existing `v<marketing-version>` tag keeps identifying the marketing release while the integer build number (retained solely as the App Store Connect upload identifier) identifies the upload sequence and the Profile label's short SHA identifies the exact commit.

#### Scenario: Tag lands with the bump
- **WHEN** a release bump commit lands on `main` for version `1.0.0`
- **THEN** the annotated tag `v1.0.0` points at that commit and is pushed

#### Scenario: Rebuild reuses the existing tag
- **WHEN** a rebuild commit lands for the same marketing version with a higher build number
- **THEN** no tag is created or moved, and the existing `v1.0.0` tag still points at the original bump commit

#### Scenario: Tag matches the app label
- **WHEN** a tester reads the Profile version row `1.0.0 (a1b2c3d)` from a TestFlight build
- **THEN** the 7-character SHA in the row identifies the exact commit the build came from (resolvable via `git show` / GitHub lookup), and the tag `v1.0.0` identifies the marketing release it belongs to

## ADDED Requirements

### Requirement: Profile version label shows commit SHA
The Profile version footer SHALL render `v<marketing> (<7-char-SHA>)` where the parenthetical is the first 7 hex characters of the built commit's SHA (`git rev-parse --short=7 HEAD` at build time), not the integer `CFBundleVersion`. Debug builds SHALL append the existing localized suffix (`v0.1.3 (a1b2c3d) • Debug`). A dirty working tree SHALL NOT alter the label — the footer reports the base commit's SHA with no dirty marker. When the SHA is unavailable at build time (no `.git`, shallow export, script failure), the footer SHALL render the existing `"?"` placeholder (`v0.1.3 (?)`).

#### Scenario: Release shows short SHA
- **WHEN** a Release build is produced from commit `a1b2c3d...` with marketing version `0.1.3`
- **THEN** the Profile footer reads `v0.1.3 (a1b2c3d)`

#### Scenario: Debug keeps its suffix
- **WHEN** a Debug build is produced from commit `a1b2c3d...` with marketing version `0.1.3`
- **THEN** the Profile footer reads `v0.1.3 (a1b2c3d) • Debug` (localized suffix unchanged)

#### Scenario: Dirty tree reports base commit
- **WHEN** a build is produced from a dirty tree based on commit `a1b2c3d...`
- **THEN** the Profile footer still reads `v0.1.3 (a1b2c3d)` with no suffix, marker, or alteration

#### Scenario: Missing SHA falls back to placeholder
- **WHEN** the SHA cannot be determined at build time
- **THEN** the Profile footer reads `v0.1.3 (?)`
