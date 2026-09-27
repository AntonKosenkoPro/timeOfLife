## MODIFIED Requirements

### Requirement: Log Time sheet shares the unified field order and gesture rule

CREATE mode SHALL use the same card order as the unified entry form (entry-editor capability): Name → Start → End → Categories → Notes, with Start and End as separate cards each carrying its own date + time pills and inline single-open picker. Defaults, validity gate, picker styles (graphical date, wheel time), and save behavior are unchanged. The all-native-gestures-must-work rule (entry-editor capability) SHALL apply to CREATE mode as well as EDIT/LOCKED.

#### Scenario: Create mode card order

- **WHEN** the Log Time sheet opens from History for logging new time
- **THEN** it shows a Name card, a Start card with date and time pills, an End card with date and time pills, a Categories card, and a Notes card — in that order — and nothing else
