## Purpose

Stable device identity with per-device refresh families: a durable device id sent with every session request, refresh tokens scoped to one device, reuse detection and revocation that never touch other devices, and lock-not-wipe on session loss.

## ADDED Requirements

### Requirement: Stable device identifier
The system SHALL generate a stable device identifier (UUID) on first sign-in, persist it in the Keychain across app reinstalls, send it as `X-Device-Id` on verify, Apple sign-in, refresh, and logout, and mint a new identifier only when the device fingerprint changes during restore-on-new-phone.

#### Scenario: Identifier survives reinstall
- **WHEN** the app is deleted and reinstalled on the same device and the user signs in again
- **THEN** the same device identifier is reused from the Keychain and sent as `X-Device-Id` on verify

#### Scenario: New phone mints a new identifier
- **WHEN** the user restores their session on a new phone whose device fingerprint differs
- **THEN** a new device identifier is minted for that device and used for all subsequent session requests

### Requirement: Per-device refresh families
The system SHALL persist a `device_id` on every issued refresh token, so each device's refresh tokens form a distinct family. Rotation SHALL stay within the issuing device's family, and a refresh token SHALL never be issued with an empty device identifier.

#### Scenario: Rotation stays within the family
- **WHEN** a device rotates its refresh token
- **THEN** the new token belongs to the same device family, and no other device's tokens are affected

#### Scenario: No anonymous family
- **WHEN** the backend issues any refresh token
- **THEN** it is recorded against a concrete device identifier, never an empty one

### Requirement: Reuse detection scoped per-device
The system SHALL, on refresh-token reuse, revoke only the offending device's refresh family — never all of the user's sessions across devices.

#### Scenario: Stale token kills only its family
- **WHEN** a replayed (already-rotated) refresh token is presented by one device while a second device holds an active session
- **THEN** only the first device's family is revoked and the second device's session keeps working

### Requirement: Logout revokes only the calling device
The system SHALL, on logout, revoke only the refresh family identified by the request's `X-Device-Id`, leaving other devices' sessions intact.

#### Scenario: Other device survives logout
- **WHEN** the user logs out on one phone while another phone remains signed in
- **THEN** only the calling phone's family is revoked; the other phone's session remains valid

### Requirement: Refresh TTL enforcement
The system SHALL reject refresh attempts whose device family has exceeded the refresh-token TTL.

#### Scenario: Expired family is rejected
- **WHEN** a device presents a refresh token after its family's TTL has elapsed
- **THEN** the refresh is rejected with an authentication error and no new tokens are issued

### Requirement: Revoked or exhausted session locks, never wipes
The system SHALL, on session revocation or exhaustion, lock the app to the auth gate with all local account files intact. Re-login SHALL resume the existing account file when an authentication slot is free.

#### Scenario: Locked to auth gate with files intact
- **WHEN** the backend revokes the active session and the app detects it
- **THEN** the app locks to the auth gate, all local database files remain untouched, and after re-login the same account resumes without data loss

### Requirement: No device quota counting in this change
The system SHALL NOT count devices, enforce a device limit, or present a device picker in this change; device quota counting is an explicit non-requirement deferred to issue #46.

#### Scenario: Extra device is not rejected
- **WHEN** a user signs in from an additional device beyond any hypothetical quota
- **THEN** the sign-in succeeds normally; no device-limit error is returned and no picker is shown