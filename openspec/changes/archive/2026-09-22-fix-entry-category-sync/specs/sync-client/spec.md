## ADDED Requirements

### Requirement: Dependency-ordered outbox drain

The sync client SHALL drain `category` outbox rows before `entry` rows, preserving `created_at, id` order within each resource. Because `POST /entries` rejects unknown `category_ids` with 422, pushing categories first ensures referenced categories exist on the relay before entries that carry them.

#### Scenario: Entry queued before its category still pushes category first
- **WHEN** the outbox holds an entry create whose `created_at` precedes its category create
- **THEN** the drain pushes the category create before the entry create and the cycle completes

### Requirement: Push validation_error recovery for unknown categories

On an entry create/update push receiving `validation_error` with `category_ids` details, the sync client SHALL fetch the relay categories, drop unknown ids from the queued payload keeping the remainder (secret-free log), rewrite the outbox payload, retry the push exactly once, and clear the row on success. If no id is pruned or the retry fails, the cycle SHALL fail loudly with the push error and keep remaining rows queued. The following pull converges the local copy via LWW.

#### Scenario: Entry with unknown category is pruned on push
- **WHEN** the drain pushes an entry create referencing a category id absent from the relay
- **THEN** the payload is pruned to the known remainder, the push retries and succeeds, the outbox clears, and the cycle completes idle

#### Scenario: Unprunable validation still fails
- **WHEN** the entry push fails with `validation_error` but every id is already known (or the retry fails)
- **THEN** the cycle fails with the push error and rows stay queued for retry
