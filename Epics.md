# Time of Life — Development Roadmap (Epics)

A brainstormed roadmap of epics for future development, sequenced so each phase turns the current MVP into the product the README promises: **minimal-effort tracking of where your time goes** (widgets, shortcuts, integrations).

---

## Where the MVP leaves you

You can start/stop a timer against a free-text activity name, and it syncs offline-first. But there's no way to **review**, **repeat**, **categorize**, **start from outside the app**, or **manage your account**. Every epic below closes one of those gaps, ordered by how much it moves you toward "minimal-effort insight into where your time goes."

---

## Phase 1 — Make the timer screen a complete daily product

### Epic 1: Activity Catalog & Categories
- Persistent list of named activities with optional **category + color tag** (replaces throwaway free-text).
- **Suggestions** surfaced on the timer screen from your most-used/recent activities (one tap to prefill name).
- CRUD for activities/categories; default categories seeded on first run.
- *Why first:* the typed-name timer is the thing that gets old fastest; structured activities are the prerequisite for every later epic (history grouping, widgets targeting a specific activity, goals per category).
- *Backend:* `activities`, `categories` resources; entries gain `activity_id` (free-text stays as fallback for ad-hoc).

### Epic 2: History & Entries Management
- `HistoryView` (already named in `Design/SCREENS/TimeTracking.md` "Future extensions") — paginated list of entries grouped by day, with duration totals.
- **Edit / delete / resume** an entry; manual add (for forgotten sessions).
- Search + filter by activity/category/date range.
- *Why:* without review, tracking has no payoff — this is the single biggest retention lever. Depends on Epic 1 for grouping.

### Epic 3: Account & Profile
- Dedicated `AccountView` replacing the interim Sign-Out toolbar item (decision D12 already calls this out as interim).
- **Account deletion** (App Store 5.1.1v) — closes the deferred Apple `/auth/revoke` follow-up in `AGENTS.md`.
- Display name / email shown, session list + revoke (the deferred multi-device session UI), sign out.
- *Why:* required for App Store launch; clears known-deferred items in one place.

---

## Phase 2 — Minimal-effort via system surfaces (the differentiator)

### Epic 4: Home Screen & Lock Screen Widgets
- Small/medium/large widgets: **one-tap start** of a pinned activity, running-timer glance, today's totals.
- Widget → app deep link carrying the activity to start.
- *Why:* this is the literal promise in the README intro ("widgets… minimal-effort"). Highest novelty value, lands before competitors' parity matters.

### Epic 5: Siri Shortcuts & App Intents
- "Start [activity]" / "Stop timer" intents; donate shortcuts so Siri proactively suggests them.
- Shortcut to start a specific activity from Spotlight/Shortcuts automations (e.g. "when I arrive at gym").
- *Why:* second half of the README's "shortcuts" promise; composes with widgets for true friction-free tracking.

### Epic 6: Live Activity & Reminders
- **Live Activity** on the Dynamic Island / lock screen while a timer runs (start/stop from there).
- Background **reminder** if a timer has run suspiciously long (forgot to stop) or no session was logged today.
- *Why:* "forgot-to-stop" is the #1 pain of any timer app; Live Activity makes the running timer visible without opening the app.

---

## Phase 3 — Insight & retention (the "where your life goes" layer)

### Epic 7: Insights & Visualizations
- Daily / weekly / monthly rollups by category and activity; bar/heatmap/time-pie views.
- "This week vs last week" deltas; longest session, most-tracked activity.
- *Why:* the *meaning* of the data — the line between a timer and a time-of-life app. Depends on Epics 1–2.

### Epic 8: Goals, Budgets & Weekly Review
- Per-category weekly **time budgets** with over/under indicators; streaks for hitting goals.
- A weekly **Review** screen (push on Sundays) summarizing where time went and prompting reflection.
- *Why:* converts passive tracking into behavior change — the retention/storytelling hook.

### Epic 9: Data Export & Integrations
- CSV / JSON export of entries; Calendar (.ics) export; optional Calendar import to auto-suggest activities.
- Optional HealthKit-style "time in [category]" metric if desired.
- *Why:* trust (export = "I own my data") + the README's "integrations" promise.

---

## Phase 4 — Ship & harden

### Epic 10: Production Launch & Onboarding
- TestFlight/App Store distribution: enable signing in `project.yml`, add fastlane/gym archive+upload CI job (`AGENTS.md` marks the exact lines).
- First-launch **onboarding** (value pitch → permissions for widgets/notifications → first activity setup).
- Privacy policy, App Store metadata, screenshots for EN+RU.
- App Store compliance sweeps (account deletion already in Epic 3, ATT if analytics added).
- *Why:* everything above is a hobby project until this lands.

### Epic 11: Platform Hardening & Observability
- **Redis** backing for rate limiting before multi-instance (explicitly deferred in README).
- **Kafka** for events once an event-driven need exists (S1 / deferred) — only pull this in if Epics 7–9 create a real analytics pipeline.
- Structured **metrics + tracing** (Prometheus/OpenTelemetry), error alerting on the GCP VM.
- DB migration framework if schema growth outpaces auto-migrate.
- *Why:* deferred infra debt; do it when load/complexity forces it, not before.

### Epic 12: Privacy-Respecting Analytics
- Opt-in, anonymous usage funnel metrics (or Apple's built-in App Analytics to avoid a custom pipeline).
- *Why:* needed to decide which of the Phase 2/3 surfaces actually drive retention — but keep it opt-in to honor R1's security posture.

---

## Suggested sequencing & dependencies

```
Phase 1:  [E1 Catalog] → [E2 History] → [E3 Account]        ← makes MVP whole
Phase 2:  [E4 Widgets], [E5 Shortcuts], [E6 Live Activity]   ← the "minimal-effort" promise (parallelizable)
Phase 3:  [E7 Insights] ← E1,E2 ; [E8 Goals] ← E7 ; [E9 Export] ← E2
Phase 4:  [E10 Launch] ← E3 ; [E11 Harden] (when needed) ; [E12 Analytics] (opt-in)
```

---

## Cross-cutting decisions to make up front

- **Free-text vs structured activities** — Epic 1 should keep free-text as a first-class fallback (don't force categorization) or you'll add friction, which fights the whole premise.
- **Backend schema for entries** — adding `activity_id`/`category_id` to entries touches the OpenAPI spec (S10) and the offline sync contract; do it once, in Epic 1, so Epics 2/7/8 don't re-migrate.
- **Single-tenant vs multi-user scaling** — the app is per-user, so Phase 4 infra is only needed at real scale; don't over-build.