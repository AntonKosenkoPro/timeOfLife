# enable-sign-in-with-apple — Delta Spec

## Purpose

Pins the Sign in with Apple contract (F2): the welcome-screen Apple button as the primary auth path exchanging an Apple identity token for the app's standard session, config gating when the backend lacks Apple credentials, and the deployment preconditions (entitlement, code signing, `APPLE_CLIENT_ID`) that make the flow reachable in a real build.

## ADDED Requirements

### Requirement: Sign in with Apple is the primary auth path on Welcome

The Welcome screen SHALL present Sign in with Apple as the primary action, ahead of the secondary email/OTP path. Tapping the Apple button SHALL run the Apple authorization; on success the app SHALL exchange the obtained Apple identity token for a session and the app shell (Track) SHALL remain the root view. Dismissing the Apple sheet SHALL produce no error message; any other failure SHALL surface a localized error banner.

#### Scenario: Successful Apple sign-in

- **WHEN** the user taps the Sign in with Apple button and completes Apple's authorization sheet
- **THEN** the app sends the Apple identity token to `POST /api/v1/auth/apple`, receives the standard access + refresh token pair, persists the session, and the user lands in the app shell as signed-in

#### Scenario: User cancels the Apple sheet

- **WHEN** the user dismisses Apple's authorization sheet
- **THEN** the app returns to the Welcome screen with no error message

#### Scenario: Offline

- **WHEN** the device is offline and the user taps the Sign in with Apple button
- **THEN** the button is disabled (dimmed) and does not start the flow

### Requirement: Apple sign-in endpoint contract

The backend SHALL expose `POST /api/v1/auth/apple` accepting `{ identity_token }` and returning the same auth response (access + refresh tokens + user) as OTP verify. The server SHALL verify Apple's RS256 identity-token JWT against Apple's JWKS, validating signature, issuer, audience (the configured Bundle ID), and expiry, and SHALL upsert the user keyed by Apple's stable subject identifier, treating Apple users as email-verified. Invalid tokens SHALL return 401 `invalid_apple_token`; the endpoint SHALL be rate-limited per IP.

#### Scenario: Valid identity token

- **WHEN** a correctly signed, unexpired Apple identity token with audience matching `APPLE_CLIENT_ID` is posted
- **THEN** the server returns 200 with the standard token pair; a repeat sign-in with the same subject returns the same user ID and retains the first-seen email

#### Scenario: Invalid identity token

- **WHEN** an identity token fails signature, issuer, audience, or expiry validation
- **THEN** the server returns 401 with error code `invalid_apple_token`

#### Scenario: Rate limited

- **WHEN** the per-IP rate limit for Apple sign-in is exhausted
- **THEN** the server returns 429 `rate_limited`

### Requirement: Config gating

The `/auth/apple` route SHALL always be registered. When the server is not configured with `APPLE_CLIENT_ID`, the endpoint SHALL return 503 `apple_not_configured`; the iOS Welcome screen SHALL remain usable via the email/OTP path. When configured, `APPLE_CLIENT_ID` MUST equal the app's Bundle ID (`com.antonkosenko.timeoflifeapp`), which is the audience claim Apple embeds in the identity token.

#### Scenario: Backend without Apple configuration

- **WHEN** `POST /api/v1/auth/apple` is called on a server where `APPLE_CLIENT_ID` is unset
- **THEN** the server returns 503 with error code `apple_not_configured` and the OTP path remains fully functional

### Requirement: Deployment preconditions

Sign in with Apple SHALL be enabled for distribution by: (a) the `com.apple.developer.applesignin` entitlement in the app's entitlements file; (b) code signing with the Apple Developer team `7923U48U87` for Release/TestFlight builds while Debug/CI builds remain unsigned; (c) the App ID `com.antonkosenko.timeoflifeapp` in the Apple Developer portal with the Sign In with Apple capability enabled; and (d) `APPLE_CLIENT_ID=com.antonkosenko.timeoflifeapp` set on the production relay. Because the real Apple sheet, JWKS verification, and Private Relay email handling cannot be exercised by unit tests, a manual smoke checklist on a real device with a sandbox Apple ID SHALL be part of the feature's definition of done.

#### Scenario: Signed build presents the Apple sheet

- **WHEN** the app is built with the SIWA entitlement and signed with the configured team, and the user taps the Sign in with Apple button on a real device
- **THEN** Apple's native authorization sheet is presented

#### Scenario: Unsigned CI build still works

- **WHEN** CI builds the Debug configuration for the simulator
- **THEN** the build succeeds without a signing identity, and all unit tests (which use fake Apple providers) pass

#### Scenario: Production relay accepts real tokens

- **WHEN** the production backend runs with `APPLE_CLIENT_ID` set and receives a genuine Apple identity token from the signed app
- **THEN** the endpoint verifies it via Apple's live JWKS endpoint and returns 200 with tokens

#### Scenario: Smoke checklist verified before TestFlight

- **WHEN** the smoke checklist (real device, sandbox Apple ID, private-relay email, cancel path) has been executed and passed
- **THEN** the feature may be considered complete for distribution