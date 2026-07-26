# AGENTS.md — Personal OS

The map for any agent (or human) working in this vault. It's a small, stable
**table of contents**: it tells you where to look next, not everything at once. It
stays under 120 lines — a linter enforces that. When something here needs more than
a sentence, move it into `docs/` and link to it.

> Source of the ideas behind this vault: OpenAI, "Harness engineering: leveraging
> Codex in an agent-first world." Summary + link: `docs/references/harness-engineering.md`.
> Read it once. The harness itself is **agent-neutral** — Codex is just the subject of
> that post. Codex, Cursor, Gemini CLI, and Copilot read this `AGENTS.md` natively;
> Claude Code reads `CLAUDE.md`, which imports it.

## Prime directive

**You decide, the agent builds.** Your job is to turn work into durable,
versioned markdown the next agent can read. Anything not committed to this repo
does not exist — if it isn't written here, the agent can't act on it. No knowledge
stays in chat, in your head, or in a terminal you closed.

## Where things live

| Folder | What it holds |
|--------|---------------|
| `projects/` | Active and archived projects (first-class, with decision logs). |
| `incidents/` | Incident & post-mortem reports. |
| `areas/` | Ongoing responsibilities (servers, accounts, recurring duties). |
| `references/` | External knowledge captured as markdown. |
| `decisions/` | ADR-style decision records — why we chose things. |
| `docs/` | How this vault works: beliefs, conventions, the harness summary. |
| `templates/` | Copy these to start a new note. |
| `dashboards/` | Index / overview notes. |
| `harness/` | The verify step (`lint-notes.mjs`), schema, and gardener. |
| `tools/` | Small CLI tools the agents use — see `tools/README.md`. |
| `.claude/` | Agent skills (`skills/`) and guard hooks (`hooks/`). |

Each content folder has an `index.md` catalog. Start narrow, follow links.

## Commands

- `npm run lint` — verify the vault: frontmatter schema, kebab-case names, links.
  Fix every `✗` before calling a note done.
- `npm run garden` — the same checks plus stale-note and broken-link hints to tidy up.
- `sh harness/install.sh` — arm the advisory pre-commit verify hook after a clone.

## How to add or change a note

1. **Pick a home** and copy the matching file from `templates/`.
2. **Fill the frontmatter** (see `harness/schema.md`): `title, type, status,
   created, updated, tags, links`.
3. **Write the body.** Projects keep an overwrite-in-place **Current state** section
   (linter-enforced); projects and incidents keep a **Timeline** and **Decision log**.
4. **Link it** from the folder's `index.md` and from any related note.
5. **Bump `updated`** to today's date.
6. **Verify**: run `npm run lint`. Fix every `✗` error.
7. obsidian-git auto-commits and pushes — that is your save.

## What "done" means

- Frontmatter valid; `status` reflects reality (`idea|active|blocked|done|archived`).
- Linked from its folder `index.md`.
- `npm run lint` passes (no `✗`).
- Committed (obsidian-git handles this); a finished project moves to
  `projects/archived/`.

## Pick your own top priority

You set the rules of your own vault. A common, high-value one: **if `incidents/` has a
note with `status: active` that is a live problem, resolving it outranks whatever else
is on screen, unless you say otherwise.** Encode your own priority rule here.

## Tools & agent skills

`tools/` and `.claude/skills/` ship working, tested pieces — read their READMEs first.
The habits they encode: **`checkpoint`** saves session state into a note before `/clear`
(continuity lives in git, not in a transcript); **`pii-guard`** keeps personal data out
of public repos (fill in its denylist — it ships blank); **`secret-use`** +
`secret-read-guard.sh` stop an agent ever typing a secret path inline.

Keep skills and tools **here in the vault**, not in an agent's own config directory, and
symlink them in. They then work with any agent, and they are versioned and backed up.

## Verify before you hand over a command

**Time is expensive — never ask someone to run something you haven't proven works.**
Reproduce it on throwaway test data (fake inputs, a temp dir, dummy creds) and confirm
the *real* outcome, not that it "should" work. If a guard blocks the live target, verify
the *mechanics* on a stand-in and hand over only the proven command.

## Boundaries

- **Always:** run `npm run lint` and fix every `✗` before calling a note done; bump
  `updated`; link a new note from its folder `index.md`.
- **Ask first:** before pushing to a remote, before making any repo or note public,
  before deleting or archiving a note you didn't write.
- **Never:** commit secrets, tokens, or private keys; publish the vault without
  scrubbing it (hostnames, IPs, internal names, and dated incidents can identify you
  even without secrets — see `docs/SECURITY.md`); hand-edit files under `.obsidian/`.

## Constraints (enforced mechanically)

- Frontmatter schema, kebab-case filenames, ISO dates — see `harness/schema.md`.
- `npm run lint` fails on schema errors — fix every `✗`. The pre-commit hook runs
  it **advisorily** and never blocks your obsidian-git backup. Broken links, stale
  notes, and size stay warnings — a nit you can fix later should never stall a backup.
- Within those boundaries you have full freedom of voice and structure.

## When you're uncertain

Don't guess silently. Record the uncertainty **in the note** (an `## Open
questions` section); if it needs a human, set `status: blocked` and say what
you're waiting on. A blocked note with a clear question beats a confident wrong one.

## Improving the harness

When a convention is unclear, fix `docs/conventions.md`. When a rule should be
guaranteed, **move it into `harness/lint-notes.mjs`** — when a written convention
keeps getting missed, make it a check the linter enforces. The gardener runbook is
`harness/garden.md`; run `npm run garden` to surface stale notes.
