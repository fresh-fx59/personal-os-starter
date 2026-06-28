# Gardener runbook

Drift is inevitable in any agent-written corpus — OpenAI's post calls the fix
"garbage collection": pay debt down continuously in small increments rather than
in painful bursts. This is the recurring cleanup pass. Run it weekly, or whenever
the vault feels untidy.

## Steps

1. **Run the verifier in garden mode:**

   ```sh
   npm run garden
   ```

   Fix every `✗` error, then triage the `•` warnings below.

2. **Broken links** — create the missing note, fix the spelling, or drop the link.
3. **Stale notes** — for anything flagged "not updated in N days": refresh it, or
   set `status` to `done` / `archived` / `blocked` with a reason.
4. **Index coverage** — add any orphaned note to its folder's `index.md`.
5. **Oversized notes** — split 400+ line notes into focused, linked notes.
6. **Finished projects** — move from `projects/active/` to `projects/archived/`
   and flip `status: done`.
7. **Promote recurring fixes** — if you keep hand-fixing the same thing, encode it
   as a new rule in `harness/lint-notes.mjs` so it cannot recur.

## Doc-gardening (content freshness)

Skim `decisions/` and `docs/` for claims that no longer match reality. The post's
"doc-gardening agent" exists to catch exactly this: documentation that quietly
stops being true. Update or supersede stale records, and link the replacement.
