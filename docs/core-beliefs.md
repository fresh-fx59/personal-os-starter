# Core beliefs

The opinionated, mechanical principles that keep this vault legible to the next
agent — our adaptation of the ideas in OpenAI's harness-engineering post. Short,
durable, rarely changed.

1. **You decide, the agent builds.** People set intent, priorities, and acceptance
   criteria; agents produce the notes. When an agent struggles, the fix is almost
   never "try harder" — ask *what capability is missing* and add it to the harness.

2. **The repository is the system of record.** If knowledge isn't committed here as
   markdown, it doesn't exist. Chat threads, things in your head, a command you ran
   once — encode them or lose them.

3. **A short index, not an encyclopedia.** `AGENTS.md` is a small, stable table of
   contents; depth lives in `docs/` behind links. When everything is a rule, nothing
   is.

4. **Guarantee the structure, not the wording.** Enforce the invariants centrally —
   schema, naming, links — and leave the local choices free. Within those boundaries
   voice and content are yours; the harness guards the shape so you don't have to
   police the substance.

5. **Fixing later beats blocking now.** Only schema breakage blocks a commit. Broken
   links and staleness are warnings to garden later, not gates.

6. **Move the rule into the linter.** When a written convention keeps getting missed
   and the same mistake recurs, move the rule from prose into `harness/lint-notes.mjs`
   — judgment encoded once, then applied automatically to every note.

7. **Pay debt down continuously.** Drift compounds quietly if you ignore it. The
   gardener runs little and often, not in painful Friday-afternoon bursts.

8. **Prefer boring, legible structure.** Plain markdown, stable conventions, few
   moving parts. The next agent — and the next model — should be able to reason
   about the whole vault from the repo alone.

When one of these stops being true, change it here first, then change the code that
enforces it.
