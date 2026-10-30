## Purpose

Provide an English screenshot montage for the Lifio landing page by reusing approved app captures, without introducing website changes or a second marketing dataset.

## ADDED Requirements

### Requirement: Montage uses approved English pilot captures

The deliverable SHALL be one English-language montage of selected owner-approved iPhone pilot screenshots. It MUST reuse the pilot's fictional data and actual app rendering rather than reconstructing the interface or inventing features. Its composition SHALL communicate the Track, Insights, and History story, and any optional English captions MUST remain consistent with screenshot/listing claims.

#### Scenario: Montage is prepared after pilot approval
- **WHEN** the pilot has owner approval and the montage is composed
- **THEN** every source frame is traceable to an approved English pilot frame hash, its data is consistent with the pilot, and no unshipped UI or capability is added

#### Scenario: Unapproved or non-English source is selected
- **WHEN** a montage input is unapproved, belongs to another dataset version, or is not English
- **THEN** export fails validation rather than silently substituting it

### Requirement: Composition is reproducible and separately reviewed

The montage SHALL have a text recipe recording its canvas dimensions, source hashes, frame selection/order, scaling/cropping, placement, background, optional captions, and export format. It SHALL have a separate owner review after pilot approval. Before that review, output MUST be labeled draft rather than final landing artwork.

#### Scenario: Approved montage is regenerated
- **WHEN** the same recipe, source frames, and recorded renderer version are supplied
- **THEN** the exported montage has the declared dimensions and composition without app-content retouching, and source provenance remains verifiable

#### Scenario: Montage review is pending
- **WHEN** composition has been exported but owner approval has not been recorded
- **THEN** the handoff identifies it as a draft and does not claim landing-page publication

### Requirement: Handoff is asset-only and keeps binaries out of git

The workflow SHALL deliver the montage binary and preview externally with a text manifest and handoff instructions. It MUST NOT modify landing-page code, add a gallery, publish the site, create additional language versions, or commit binary assets without separate explicit owner authorization.

#### Scenario: Asset handoff completes
- **WHEN** the owner approves the montage
- **THEN** the handoff includes the external asset location, dimensions, hashes, source approval reference, and recipe, while website code and deployment remain unchanged
