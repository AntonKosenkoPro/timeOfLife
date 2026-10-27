## ADDED Requirements

### Requirement: Revert-forward rollback

A bad release SHALL be recovered by reverting the offending commit(s) on `main` and cutting a new tag through the internal channel first — never by moving or deleting a pushed tag. Rollback of an installed public build is a new version containing old code, verified internally before re-release.

#### Scenario: Bad public release recovered

- **WHEN** `release/v0.3.0` is found bad after shipping
- **THEN** the fix is a `git revert` on `main`, a new `internal/v0.3.1` tag verified in TestFlight Internal, followed by `release/v0.3.1` — the `release/v0.3.0` tag stays where it points

#### Scenario: Pushed tag is never moved

- **WHEN** any tag matching `internal/*`, `release/*`, or `backend/*` has been pushed
- **THEN** it SHALL NOT be force-moved or deleted to "reuse" the name; a new tag name carries the correction

## MODIFIED Requirements

### Requirement: Marketing version follows semantic versioning

The released marketing version SHALL be a three-component semantic version `MAJOR.MINOR.PATCH` (e.g. `1.0.0`). Release tags carry the marketing version with an optional fourth-dot re-upload sequence (`internal/v0.2.7`, `internal/v0.2.7.2`); the sequence is NOT part of the marketing version and defaults to 1 when absent.

#### Scenario: First bump normalizes the version

- **WHEN** the current version is the legacy two-component `1.0`
- **THEN** the next released marketing version is a three-component version strictly greater than `1.0.0`

#### Scenario: Non-semver input is rejected

- **WHEN** a tag's marketing component is not `X.Y.Z` numeric semver (e.g. `internal/v1.0`, `release/v1.0.0-beta`)
- **THEN** the build refuses it with a clear message and archives nothing

#### Scenario: Re-upload sequence is distinct from marketing

- **WHEN** a second TestFlight upload is needed for the same marketing version
- **THEN** a new tag with an incremented fourth-dot sequence (e.g. `internal/v0.2.7.2`) triggers it; the stamped marketing version stays `0.2.7` while the App Store Connect build number increases

### Requirement: Manual tag-triggered releases

A release SHALL be triggered only by the owner pushing a signed tag from `main` — no workflow, bot, or second human can cut one. On acceptance the tag-triggered Cloud workflow stamps the marketing version, an increasing build number, and the channel at build time; nothing version-related is committed to `main`. `project.yml` carries only a dev dummy version for local builds.

#### Scenario: Owner tag triggers a channel build

- **WHEN** the owner pushes signed `internal/v0.2.7` (or `release/v0.3.0`) pointing at a `main` commit
- **THEN** the matching Cloud workflow tests, archives, and delivers to TestFlight Internal (or External/App Store) with the stamped marketing version

#### Scenario: Non-owner or bot tag cannot release

- **WHEN** a tag in these namespaces is pushed by anyone (or any token) other than the owner
- **THEN** the tag ruleset rejects the push and no build is triggered

#### Scenario: Mistyped tag builds nothing

- **WHEN** a pushed tag matches no namespace pattern (e.g. `v0.2.7`, `internl/v0.2.7`)
- **THEN** no Cloud release workflow triggers (fail-closed)

### Requirement: Tag namespaces and channel routing

iOS release tags SHALL live in exactly two namespaces: `internal/*` (dogfood → TestFlight Internal group, no Beta review) and `release/*` (public → TestFlight External / App Store). Every tag SHALL be annotated and signed, created only on `main`, and never moved once pushed. The tag message records the intent (e.g. what was verified, what the public notes are).

#### Scenario: Internal tag routes to the internal group

- **WHEN** signed `internal/v0.2.7` is pushed
- **THEN** the internal Cloud workflow archives and the build appears in the TestFlight Internal group only

#### Scenario: Public tag routes to the public destination

- **WHEN** signed `release/v0.3.0` is pushed
- **THEN** the public Cloud workflow archives and the build goes to TestFlight External / App Store submission

### Requirement: Profile version label shows commit SHA and channel

The Profile version footer SHALL render `v<marketing> (<7-char-SHA>)` where the parenthetical is the first 7 hex characters of the built commit's SHA, plus ` • Internal` on internal-channel builds. Debug builds SHALL append the existing localized suffix (`v0.0.0-dev (a1b2c3d) • Debug`). A dirty working tree SHALL NOT alter the label — the footer reports the base commit's SHA with no dirty marker. When the SHA is unavailable at build time (no `.git`, shallow export, script failure), the footer SHALL render the existing `"?"` placeholder.

#### Scenario: Internal build shows its channel

- **WHEN** an internal-channel build is produced from commit `a1b2c3d...` with marketing version `0.2.7`
- **THEN** the Profile footer reads `v0.2.7 (a1b2c3d) • Internal`

#### Scenario: Public build shows no channel

- **WHEN** a Release build is produced from commit `a1b2c3d...` with marketing version `0.3.0`
- **THEN** the Profile footer reads `v0.3.0 (a1b2c3d)`

#### Scenario: Missing SHA falls back to placeholder

- **WHEN** the SHA cannot be determined at build time
- **THEN** the Profile footer reads `v0.2.7 (?)` (plus channel/debug suffixes as applicable)
