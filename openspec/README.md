# OpenSpec — this repo's workflow

This repo is **spec-driven** (`openspec/config.yaml`, `schema: spec-driven`). OpenSpec manages
change proposals as artifacts (proposal → specs → design → tasks) and folds accepted changes
into baseline specs via `openspec archive`. Use `openspec --help`; this directory is AI-editable,
but the CLI stays the source of truth.

## Concepts: baselines, deltas, archives

| Layer | Location | Meaning |
|---|---|---|
| **Baseline specs** | `openspec/specs/<capability>/spec.md` | The current merged contract. Today: `app-shell`, `timer-capture-experience`, `category-management`. **Never edit directly** — behavior changes go through a change. |
| **Active change (deltas)** | `openspec/changes/<change>/` | A proposal in flight. Its `specs/<capability>/spec.md` files are delta specs (ADDED/MODIFIED requirements) not yet in the baseline. Active change: **`local-first-sync-architecture`** (local-first store, sync client, provenance, and Controls). Check its `tasks.md` and `openspec status --change <name>`. |
| **Archives** | `openspec/changes/archive/<change>/` | Completed changes; their deltas were already folded into the baselines by `openspec archive`. Read them only for history. Today: `redesign-track-experience`, `keep-timer-position-on-stop`, `unify-activity-preparation-flow`, `refine-selected-activity-from-track`, `add-category-management`. |

**Which contract is in force?** The baselines plus the delta specs of the active change
(deltas are the newest intent). Check the active change's `tasks.md` before implementing
anything and mark tasks `[x]` as you complete them — `openspec status --change <change>` tracks progress.

## Workflow

1. **Read the context first**: `docs/project-context.md` is the canonical repo context
   (architecture, API contract, incomplete surfaces, standards). `openspec/config.yaml`
   injects it into artifact instructions; `AGENTS.md` is the short entrypoint.
2. **Propose** a change: `openspec new change <name>` (or the `openspec-propose` skill).
   Fill in `proposal.md`, then the delta specs (`specs/<capability>/spec.md`), `design.md`,
   and `tasks.md`. Run `openspec validate <change> --strict` to check coherence.
3. **Implement**: drive `tasks.md` to completion (see `openspec instructions apply --change <name>`).
4. **Archive** when complete: `openspec archive <change>` folds the deltas into the baseline
   specs and moves the change to `openspec/changes/archive/`. Then update
   `docs/project-context.md` (routing + "Incomplete / deferred") and this README.

## Key commands

```bash
openspec list                                  # active changes + progress
openspec list --specs                          # baseline specs
openspec status --change <change>              # artifact/task completion
openspec validate --all                         # validate every change and spec
openspec validate <change> --strict             # validate one change
openspec show <change-or-spec>                   # read an artifact
openspec context                               # resolved root context
openspec instructions <artifact|apply|archive> --change <change>   # what the CLI expects
openspec archive <change>                      # fold deltas into baselines
```

The `openspec/` directory contains this guide, `config.yaml`, baseline `specs/`, and active or
archived `changes/`. The CLI generates or updates workflow adapters on demand.

## Repo conventions that affect changes

- **Baselines never edited directly**; every behavior change adds a delta to a change.
- **Incomplete UI surfaces must not be claimed done**: app-wide activity/history UndoToast/shake-to-undo, the "Enable
  Sync" `AuthFlowView` sheet (Profile currently does a silent `restoreSession()`), "via
  <Source>" labels, and the iOS 18 lock-screen ControlWidget are open tasks in
  `local-first-sync-architecture/tasks.md`. Category-scoped undo in Manage Categories is
  implemented (archived `add-category-management`) and does not close the app-wide undo tasks.
- **OpenAPI is the authoritative API contract** (`backend/api/openapi.yaml`, S10): endpoint
  changes update both sides + the spec.
- Per-iteration revising process (linters, tests, docs): `docs/project-context.md` → S5.
