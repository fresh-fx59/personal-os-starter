# Conventions

Detailed habits referenced from `AGENTS.md`. The frontmatter schema itself lives in
`harness/schema.md`; this file covers everything around it.

## Naming

- Content filenames are `kebab-case.md`: lowercase, words joined by hyphens. The
  linter enforces this. Example: `harden-the-vps.md`.
- Decision records are numbered: `NNNN-short-title.md`, e.g.
  `0001-personal-os-harness.md`.
- Folder catalogs are always `index.md`.

## Frontmatter

See `harness/schema.md` for the schema. Always set `status` honestly and bump
`updated` whenever you touch a note.

### status meanings

- `idea` — captured, not started.
- `active` — being worked now.
- `blocked` — waiting on a human or an external thing; say what, in the body.
- `done` — finished; no further work expected.
- `archived` — kept for the record, no longer relevant.

## Linking

- Relate notes with Obsidian wikilinks: `[[note-name]]` or `[[folder/note-name]]`.
- Link every new note from its folder's `index.md` so the catalog stays complete.
- Use the full `[[folder/note]]` form when a basename would be ambiguous.
- In docs and templates, write example links inside backticks so the linter does
  not treat them as real (and therefore broken) links.

## Note structure

- Open with an H1 that matches the `title`.
- **Projects** keep a `## Current state` section — **overwritten in place**, never
  appended to. It is current-truth only: what is live, decided, and true *right now*,
  opening with `As of YYYY-MM-DD`. History belongs in Timeline / Decision log. The
  linter enforces its presence, because the alternative is a fresh session replaying
  a hundred Timeline lines to work out what is true today.
- **Projects and incidents** keep two running sections, treated as first-class
  artifacts:
  - **Timeline** — dated entries of what happened or what was done.
  - **Decision log** — each meaningful choice, the options weighed, and why.
  - Scale the ceremony to the work: a small change needs only a Timeline line, while
    complex work keeps a full Decision log.
- Record unknowns under `## Open questions` instead of guessing silently.

## Verifying

Run `npm run lint` before you call a note done; fix every `✗`. The pre-commit hook
runs the same check **advisorily** — it never blocks your obsidian-git backup.
Warnings (`•`) are for the gardener, not blockers.

---

The sections below are working conventions for the *agent*, not the note schema.
They are the habits that survived contact with real work; keep, edit, or delete them
to fit yours.

## Constrain inputs to keep code simple (input gates)

When downstream logic turns complex to handle an *unconstrained* input, prefer an
**input gate** — a format or uniqueness constraint at the entry point that removes
the hard cases *by construction* — over growing the algorithm to cope with them. The
gate is generic; the payoff is a simpler, more reliable core and fewer edge cases.
This matters most on money-critical and security-critical paths. Choose the input so
the check can be trivial; when a legacy input can't be changed, gate it explicitly.

Worked example — promo codes. Require a code to be **unique and not an ordinary
word**. Detection then collapses to a case-insensitive **whole-word** match: no
intent disambiguation, no LLM signal, no marker gymnastics. `SAVE2026` is a good code
(nothing collides with it); `SAVE` is a bad one — it *is* an ordinary word, so "how do
I save?" is indistinguishable from a redemption. For a legacy ordinary-word code that
can't be renamed, require an explicit marker around it instead.

## Using a secret at runtime — go through a wrapper, never `cat` it

An agent should **never** put a secret path literal in a command (or Read/Grep/Glob a
path under the secrets directory). The value then lands in `ps`, shell history, logs,
and the session transcript — four places you cannot scrub.

This vault ships the enforcement and the alternative:

- **The guard.** `.claude/hooks/secret-read-guard.sh` is a `PreToolUse` hook that
  **denies** such a call and hands the agent an intent-aware nudge naming the right
  wrapper. The deny reason is fed back to the model, which self-corrects on the same
  turn — no human prompt, so autonomous work never halts. It **fails open** on any
  error: it runs on every tool call and must never wedge a legitimate one.
- **The wrappers.** `.claude/skills/secret-use/` — each reads the secret *inside* the
  script, so the value never touches argv/stdout/logs:

  | Need | Wrapper |
  |------|---------|
  | any header-auth HTTP API | `secret-curl.sh <name> 'Authorization: Bearer %s' <url>` |
  | run a program with a secret | `with-secret.sh <name> --file-env VAR -- <cmd>` (or `--env VAR`) |
  | send one email (Resend) | `resend-send.sh --to … --subject … --text …` |
  | send one Telegram message | `tg-send.sh <bot-token-secret> <chat_id> <text>` |
  | check a secret is set | `secret-status.sh <name>` → `set` / `unset` |
  | a human asked to SEE a value | `reveal-secret.sh <name>` (audit-logged) |

**General recipe for any new secret use:** move the read into a wrapper; keep the
secret path out of the agent's command. `secret-curl.sh` / `with-secret.sh` are the
generic core — a new service usually needs no new file. Point `SECRETS_DIR` at
wherever your secrets are rendered (default `/run/secrets`, the sops-nix convention).

## Model & effort economy (agents)

Compute is a budget: spend it where quality is bought, not where the work is
mechanical.

- **Pick model *and* effort per task.** Cheap/fast models at low effort for mechanical
  work — scraping, extraction to a schema, per-item verification, bulk classification,
  format conversion. Strong models at high effort only where judgment, synthesis, or
  final quality matters. State the choice in the plan so it is reviewable.
- **Subagents by default.** Fan work out to subagents to save main-context tokens; the
  main loop orchestrates and decides — it does not grind through files itself.
- **Parallelize only when effective.** Parallel is for independent file-sets or
  independent questions; serialize anything sharing state (one repo clone, one test
  DB, one branch). Cap concurrency at roughly `cores − 2`.

## Workflow authoring — reliable structured output

Measured over 36 days of transcripts on the vault this starter came from: workflow
`agent(prompt, {schema})` calls force a structured-output tool call, and it failed
**35.1%** of the time (990 of 2,819 calls) — the worst error rate of any tool. The root
cause was **weak-model placeholder emissions** (a subagent returning the literal
string `"test"`), not schema shape.

When you author a schema-returning `agent()` call:

- **Restate enum literals in the prompt.** They otherwise live only inside the
  JSONSchema, which the model weights less than prompt text.
- **Include one fully-filled example object** matching the schema, in the prompt.
- **Order the agent to emit the structured-output call as its first and only action** —
  no prose, no placeholder, before anything else.
- **Keep the schema strict.** Don't loosen it or drop required fields to make it pass —
  strictness is what *catches* a placeholder; loosening just lets garbage through
  silently.
- **Add a placeholder guard in the workflow itself.** After collecting results, reject
  any schema-valid return whose required free-text fields look like a placeholder, and
  re-run that item:

  ```js
  const PLACEHOLDER = /^(test|todo|tbd|placeholder|xxx|n\/a|none|na|\s*)$/i
  const isPlaceholder = v => typeof v === 'string' && PLACEHOLDER.test(v.trim())
  // after agent(...): if any required free-text field isPlaceholder(...), retry that item
  ```

- **Don't "fix" reliability by upgrading a whole subagent run to a frontier model** —
  that multiplies its cache-read cost 5–15× to dodge one terminal turn. Escalate only
  the specific failing call.

## Code navigation (code repos)

How to navigate the code repos driven from this vault, token-efficiently. All of this
was measured, not assumed.

- **`rg`/`grep` is the default for ALL search** — including "find every caller", "every
  def/class", "real call vs comment mention". On find/reference/overview tasks a
  capable agent with grep matched or beat both `ast-grep` and an LSP MCP server. Add a
  quick `Read` of a few lines to tell a real call from a comment — that judgment is
  cheaper and more reliable than a fancier tool.
- **Don't reach for `ast-grep` to *find* things.** Forcing it on search tasks cost 2–5×
  more: the agent burns turns on AST-pattern syntax, then cross-checks with grep
  anyway. Keep it for structural **rewrites / codemods**, where its edge shows only at
  large mechanical scale (one `ast-grep -p 'ident' -r 'new' -U` vs N manual edits, plus
  guaranteed precision when decoys are too many to eyeball). Use simple identifier /
  expression patterns with `--update-all`, not hand-built multi-line patterns.
- **CLI-first over a resident MCP server.** A resident server taxes every turn with its
  tool definitions — dead weight on the many headless turns that are log or DB
  reasoning, not symbol navigation.
- **Delegate wide reads to a search subagent** with an explicit "find references /
  callers / blast radius of X" brief; it externalizes the traversal and returns the
  conclusion, not the file dumps.
