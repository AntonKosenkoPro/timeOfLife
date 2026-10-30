# Lifio

A personal time-tracking app for iOS — minimal-effort tracking of where your time goes. **Local-first and account-bound:** sign in once (mandatory), then your device is the source of truth; the Go backend is the identity + optional sync relay.

Status: **pre-release** — try the beta via [TestFlight](https://testflight.apple.com/join/zy7fZuEy), or read how it works at [lifio.antonkosenko.pro](https://lifio.antonkosenko.pro) ([privacy policy](https://lifio.antonkosenko.pro/privacy)).

Current scope: **auth MVP** (passwordless email-OTP or Sign in with Apple, per-device sessions) and the **Track experience** — a three-tab shell (Track/History/Insights) with a centered numeric timer, a plain-text name field with exact-text Recents chips, a live tag selector while running, a Profile destination, and a compact cross-tab running timer. There is no activity entity: entries own their text, ordered categories, and notes.

## The app in one minute

1. **Log in** — the app launches into the auth flow (email OTP or Sign in with Apple); no anonymous use exists. After sign-in you land in Track.
2. **Name it** — type a name or tap a recent chip (exact match inherits that entry's categories; typing never starts timing).
3. **Start** — the centered numeric timer counts up while the device stays awake.
4. **Stop** — saves the entry on your device; it syncs to the relay on foreground/connectivity/manual "Sync now", and everything works fully offline.
5. **Switch tabs freely** — a running timer stays visible above the tab bar on History and Insights with return-to-Track and in-place Stop.

## Contribute

Start here: [`CONTRIBUTING.md`](CONTRIBUTING.md) (quickstart, environment, driving AI agents, checks & CI, releases). Manual device checklists (Sign in with Apple, Live Activities): [`docs/manual-testing.md`](docs/manual-testing.md).

| Doc | What it's for |
|---|---|
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Human contributor guide |
| [`docs/project-context.md`](docs/project-context.md) | Canonical architecture + repo context (for AI agents, S7) |
| [`AGENTS.md`](AGENTS.md) | Concise AI-agent entrypoint |
| [`docs/manual-testing.md`](docs/manual-testing.md) | Device smoke checklists |
| [`Requirements/FURPS/`](Requirements/FURPS/) | Requirements (FURPS+ table + use cases) |
| [`Design/`](Design/) | Text-based design system (colors, components, screens) |
| [`docs/screenshot-capture.md`](docs/screenshot-capture.md) | App Store screenshot capture runbook (draft pre-release tooling; see also `Design/SCREENSHOTS.md`) |
| [`backend/api/openapi.yaml`](backend/api/openapi.yaml) | Authoritative API contract (OpenAPI 3.0, S10) |
