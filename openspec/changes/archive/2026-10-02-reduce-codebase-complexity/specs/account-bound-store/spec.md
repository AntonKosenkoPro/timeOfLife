## MODIFIED Requirements

### Requirement: Running timer survives logout and account switch
The system SHALL keep a running timer's draft state (elapsed time, entry text, ordered categories) in its account's file across logout or account switch, and SHALL resume it when that account becomes active again. There is no activity entity — the resumed state is the timer draft, never an activity.

#### Scenario: Timer resumes after returning to its account
- **WHEN** a timer is running in account A, the user logs out and signs in as B, then later signs back in as A
- **THEN** account A's file still holds the running timer draft, and on return the timer UI resumes with the elapsed time, text, and categories intact; account B never sees A's timer
