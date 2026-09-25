# Bug-fix process (mandatory)

No diagnosis from guesses. Every bug fix follows these steps in order; stop and
ask the human wherever the step says so.

## Steps

1. **Reproduce the bug** — on a simulator/device against a known backend
   (local: `docker-compose up -d postgres` + `go run ./cmd/server` from
   `backend/`) and a known app build. Record exact repro steps + build.
2. **Not reproducible → ask the human** (build, backend, steps, data state).
   Do not proceed on assumptions.
3. **Explain from evidence** — debug with logs, not guesses:
   - iOS: Console.app / `log` with predicate
     `subsystem == "com.antonkosenko.timeoflifeapp"` (sync: category `sync`).
     Note: the Profile "Sync failed" message carries no endpoint — the failing
     request must come from logs or a proxy capture, never from the message.
   - Backend: server access logs (method + path + status); `backend/api/openapi.yaml`
     (S10) is the authoritative contract — verify the route exists there first.
   - Unit level: a failing-path test with a mock is evidence; a hypothesis is not.
4. **Only a guess → ask the human.** Name each hypothesis as such and stop.
5. **OpenSpec proposal for the fix** (`openspec new change <name>` or the
   `openspec-propose` skill; proposal → delta specs → design → tasks;
   `openspec validate <change> --strict`). Review it with the human and **wait
   for their explicit command** before applying.
6. **Red tests first** — write tests reproducing the bug; they must fail
   before the fix.
7. **Implement the fix** (mark `tasks.md` as you go; S5 stays in force:
   linters + warning-as-error build + both suites green).
8. **Re-verify by reproducing** — run the step-1 repro again on the fixed build.
9. **Corner cases** — enumerate unhandled variants of the bug explicitly.
10. **Tests for the corner cases.**
11. **Fix the corner cases.**
12. **Summary + offer to archive** (`openspec archive <change>`, then update
    `docs/project-context.md` routing + `openspec/README.md`).
