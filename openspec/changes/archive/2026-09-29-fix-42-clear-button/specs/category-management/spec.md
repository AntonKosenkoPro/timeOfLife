## MODIFIED Requirements

### Requirement: Category-editor name field has a clear button

The category-editor name field SHALL offer a trailing clear (`×`) button visible only when the field is focused AND holds non-empty text, with the same Apple-standard look (small dim `xmark.circle.fill`, 44 pt tap target). One tap SHALL clear the draft name; field validation re-evaluates. The shared field component's clear affordance is opt-in per call site and defaults to off (the email-OTP field has none).

#### Scenario: Category name clear hidden when unfocused or empty

- **WHEN** the category-editor name field is empty or unfocused
- **THEN** no clear button is shown

#### Scenario: Category name clear clears the draft name

- **WHEN** the category-editor name field is focused and holds text
- **THEN** a trailing `×` is visible, and one tap empties the field
