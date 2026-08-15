## Context

See `proposal.md` for motivation. `NumericTimerReadout` currently conditionally inserts the saved-state checkmark as the first child of the same vertical stack that lays out the timer text and caption. Even though Track gives the component a fixed outer height, adding that child changes the stack's total height and shifts the timer text downward within the frame. The existing Track contract requires the numeric readout to keep a stable position across states.

## Goals / Non-Goals

**Goals:**

- Keep the timer text and caption at identical positions before and after a successful stop.
- Preserve the brief blue checkmark above the timer and the existing saved-state timing.
- Keep the confirmation decorative while the combined timer element continues to expose the saved state to accessibility.

**Non-Goals:**

- Changing timer state transitions, save behavior, haptics, or confirmation duration.
- Redesigning the Track screen or changing primary-control geometry.
- Adding localization, persistence, API, or backend behavior.

## Decisions

### Render saved feedback outside the timer's layout flow

Keep the timer text and caption in the stable layout container and place the checkmark in an overlay at a fixed position above that container. An overlay does not contribute to the measured size of the timer stack, so showing or hiding the mark cannot recenter or displace the numeric text.

A permanently allocated placeholder was considered, but it would add unused vertical space to every non-saved state and could move the baseline position users already see. Conditional opacity on a placeholder would also keep an otherwise decorative element in the layout and require additional accessibility handling. The overlay is the smallest change that preserves current non-saved geometry.

### Keep accessibility semantics on the timer state

Treat the checkmark as decorative and keep the existing combined timer accessibility label/value as the source of saved-state feedback. This avoids a duplicate or context-free "checkmark" announcement while preserving the meaningful saved status.

## Risks / Trade-offs

- [The overlay could clip at large accessibility text sizes or within a constrained preview] -> Position it within the existing fixed Track readout region and verify ready, running, and saved layouts at supported Dynamic Type sizes.
- [A layout-only regression may be difficult to cover with state-model unit tests] -> Add the narrowest practical view/layout regression check and perform a simulator transition check if no existing snapshot harness can assert geometry.
