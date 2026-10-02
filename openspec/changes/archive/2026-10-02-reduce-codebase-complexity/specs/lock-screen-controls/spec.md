## MODIFIED Requirements

### Requirement: No authentication required
The Control's App Intent SHALL use `IntentAuthenticationPolicy.alwaysAllowed`, so the intent executes when the device is locked without prompting for Face ID, Touch ID, or passcode. The intent SHALL perform no account authentication of its own: device unlock is the authorization for operating on the active account's file. The intent operates only when an account file is active (the device has been unlocked at least once since boot and a signed-in account is bound); with no active account file the intent SHALL fail gracefully without prompting, writing nothing.

#### Scenario: Tapped while device is locked
- **WHEN** the device is locked (but has been unlocked at least once since boot) and the user taps the Control
- **THEN** the intent executes, writes to the active account's file in the shared container, and returns; no authentication prompt is shown

#### Scenario: No auth prompt for account state
- **WHEN** the user taps the Control regardless of the signed-in account's identity
- **THEN** the intent never prompts for, verifies, or refreshes the user's account session; it acts only on whichever account file is active

#### Scenario: No active account file fails gracefully
- **WHEN** the user taps the Control with no active account file (signed out / never unlocked since boot)
- **THEN** the intent performs no write, shows no auth prompt, and returns the existing graceful-failure result
