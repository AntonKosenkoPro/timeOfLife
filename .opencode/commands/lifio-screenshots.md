---
description: "Capture Lifio App Store screenshots locally (genuine Live Activity pixels + review-only panels)"
---

Load the `lifio-local-screenshots` skill (`.agents/skills/lifio-local-screenshots/SKILL.md`) via the skill tool and follow it end to end: full bundle by default (3 devices × 5 locales, strictly sequential, ~20 min), or a subset when arguments name devices/locales (e.g. `/lifio-screenshots iphone69 en` means `--devices iphone69 --locales '["en"]'`). Review-only outputs under an out root outside git; owner template + caption approval still required before anything is publish-ready. Never weaken a guard to turn red green; fail-closed statuses are the honest output.

$ARGUMENTS
