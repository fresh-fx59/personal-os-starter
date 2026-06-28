# ARCHITECTURE — how this vault is built

This vault is a **harness** in the sense of OpenAI's harness-engineering post
(summary + link: `docs/references/harness-engineering.md`): the environment,
conventions, and feedback loops that let an agent do reliable work live *in the
repository*, not in any one model. Swap the agent; the harness stays.

## The three layers

1. **Knowledge (the "application")** — `projects/`, `incidents/`, `areas/`,
   `references/`, `decisions/`. The actual notes. This is what the OS is *for*.
2. **The map & rules (system of record)** — `AGENTS.md` (entry point) and `docs/`
   (beliefs, conventions, the harness summary). Progressive disclosure: a small,
   stable entry point that points to deeper truth.
3. **Mechanical enforcement (feedback loop)** — `harness/`: a zero-dependency
   linter (`lint-notes.mjs`) wired to a git pre-commit hook, plus the gardener.

## Data flow: how work becomes durable

task → pick folder + copy template → fill frontmatter + body (with a decision
log) → `npm run lint` (verify; self-correct on the remediation hints) → link from
the folder index → obsidian-git auto-commits + pushes → human reviews in Obsidian
or on GitHub → the gardener periodically prunes stale notes and broken links.

## Why these choices (from the post)

- **A short index, not an encyclopedia.** A monolithic AGENTS.md rots and crowds
  context, so it's a ~100-line table of contents; detail lives in `docs/` and is linked.
- **Guarantee the structure, not the wording.** Enforce the shape centrally — schema,
  naming, links — and leave the local choices (voice, content) free.
- **Block only on real breakage.** `npm run lint` fails on schema errors; the pre-commit
  hook is advisory and never blocks the auto-backup — a nit you can fix later
  should never stall a backup.
- **Move rules into the linter.** When a convention matters, it moves from
  `docs/conventions.md` into the linter.
- **Garbage collection.** Drift is cleared continuously by the gardener, not in
  painful bursts.

## Alternatives considered

- **Mirror a product codebase** (`design-docs/`, `specs/`, `exec-plans/`). Faithful to
  the source post, but shaped for shipping software, not for how a person files
  personal knowledge. Rejected for a layout organized around projects, incidents, and
  decisions.
- **Folders plus the git plugin, no linter.** Simpler, but with no mechanical
  enforcement an agent-written vault drifts into inconsistency — the exact failure the
  harness exists to prevent. Rejected.
- **Heavier harness machinery** (proof bundles, capability manifests, dependency
  graphs). Out of scope for a personal vault — more to maintain than it earns.
  Rejected (YAGNI).

**Consequences:** every note follows one schema, so any agent can read and extend the
vault; the harness lives in the repo, so switching agents or models loses nothing; new
rules are added by editing one small linter. The cost is a little ceremony per note
(frontmatter + linking), mitigated by `templates/`.

To set this up yourself, see `SETUP.md`.
