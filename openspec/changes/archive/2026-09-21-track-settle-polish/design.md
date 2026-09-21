# Design — track-settle-polish

## D1 — Swap after the slide, not inside it

A focused Start tap resigns the field immediately (haptic + tap-time
`startedAt` captured at once) and the running swap waits for the real
keyboard-`didHide` notification, with a 600 ms bounded fallback for
hardware keyboards that never notify. A fixed delay guesses wrong on
devices whose slide outlasts it (measured 404 ms on iPhone vs 350 ms
guess). Any field edit or chip tap before the swap fires cancels the
deferred start, so a stale draft can never start.

## D2 — Both branches mounted, inactive hidden

The below-button slot keeps Recents and the running `TagSelector` mounted
in a `ZStack` and hides the inactive branch via opacity (hit testing and
accessibility follow the visible branch). The slot therefore keeps the
taller branch's height in every state — a conditionally inserted branch
reintroduces the very jump the slot exists to prevent whenever the two
branches differ in height (2-row tags vs 1-row Recents ≈ 45 pt on device).
The selector's rows depend only on the category options, never on the
selection, so an empty idle selection renders at identical height.

## D3 — No self-animation on the swap

State swaps on Track render with no animation of their own
(`transaction(animation: nil)` on the bottom flow + `PrimaryButton`
`animateStateChanges: false`): tint, label, dimming, and spinner changes
cut instantly. The keyboard's own slide still moves the whole layout
together, which is expected system behavior — the bug was the button
moving *relative* to its layout.
