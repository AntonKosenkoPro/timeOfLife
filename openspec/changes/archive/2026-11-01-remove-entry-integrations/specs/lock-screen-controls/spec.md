## REMOVED Requirements

### Requirement: Lock-screen start/stop Control
**Reason**: The unimplemented ControlWidget capture feature is abandoned rather than deferred.
**Migration**: Start remains in the app. Existing Live Activity Stop links open the app's ordinary Stop flow; Live Activities are not retired.

### Requirement: No authentication required
**Reason**: The abandoned background Control intent has no supported execution path.
**Migration**: Live Activity links use normal system app opening and the app's existing authentication/account gate. No unauthenticated extension writer replaces the Control.

### Requirement: Graceful failure when database inaccessible
**Reason**: A Control-specific database-opening path is no longer supported.
**Migration**: Keep app-side no-write behavior for missing account/inaccessible storage and the existing local data-protection contract.

### Requirement: Control reads running state from shared container
**Reason**: No Control renders or reads the database.
**Migration**: The app persists the running draft and publishes Live Activity content through the retained Live Activity lifecycle. No new extension database reader is introduced.

### Requirement: Availability guard for iOS 18+
**Reason**: Deployment support must not depend on a retired feature.
**Migration**: Re-home the iOS 18 minimum and absence of pre-iOS-18 runtime branches in the `app-shell` requirement “Minimum supported iOS version”.

### Requirement: Outbox integration
**Reason**: The abandoned Control never creates entries.
**Migration**: Keep the app's transactional outbox, including for entries saved after a Live Activity Stop link opens the app.
