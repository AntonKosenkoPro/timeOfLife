# Evidence — fix-tab-bar-return-jump (iPhone 17e, iOS 26.4, UITEST_SCREEN=signedIn)

Identical script both runs: Track → name "Gym" → Start → History → Profile → Back.

- `before-track-profile-back.mp4` — Track Profile→Back on the pre-fix tree.
- `before-history-profile-back-running.mp4` — History Profile→Back with running
  timer + compact timer on the pre-fix tree. Frame-diff fingerprint (8fps):
  slide burst (g-010/011) → near-still (g-012/013) → SECOND burst g-014
  (114k): the floating bar fades in late and the compact timer jumps up from
  the bottom edge (g-013 bottom-docked → g-015 daylight). The reported glitch.
- `after-history-profile-back-running.mp4` — identical script on the fixed
  tree. Fingerprint: ONE burst (h-009→h-013 slide) then monotonic decay to
  still (h-014: 112 → 0); h-012 already shows bar + compact timer in final
  position mid-slide. No second spike. Periodic ~8-frame ticks are the live
  compact-timer seconds — expected, present in both.

Also verified live (describe trees): NamePicker push hides the bar (path
route), Done applies the draft and pops with the bar back, swipe-cancel
stays hidden on Profile, swipe-commit restores History + bar + timer.
No lifecycle supplement added (3.2): no lagging gesture found.
