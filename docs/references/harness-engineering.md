# Harness engineering — the idea behind this vault

This Personal OS is an adaptation of the ideas in OpenAI's post **"Harness
engineering: leveraging Codex in an agent-first world."**

> **Read the original — it is the source of truth, not this summary:**
> <https://openai.com/index/harness-engineering/>

This file deliberately **links to** the original rather than reproducing it. The
post is OpenAI's copyrighted writing; please read it at the source and don't paste
its full text into public repos or articles (this starter doesn't, and adopters
shouldn't either). What follows is a short, in-our-own-words summary of the few
principles this vault actually encodes — just enough to make the repo
self-explanatory. (Linking the post instead of storing it is a deliberate exception to
this vault's own "system of record" rule, made for copyright — the principles it relies
on are summarized here so the repo still stands on its own.)

## The idea in one paragraph

A "harness" is the environment, conventions, and feedback loops that let an agent
do reliable work — and they live *in the repository*, not in any one model or chat
session. Get the harness right and you can swap the agent or the model underneath
and lose nothing. OpenAI built an entire product this way: people set the intent and
the acceptance criteria, the agents produce the work, and the repository is what
makes it durable.

## The principles this vault borrows

- **You decide, the agent builds.** People decide *what* and *why*; the agent
  produces the artifact. When the agent gets stuck, the question is "what capability
  is missing from the harness?" — not "how do I prompt harder?"
- **The repository is the system of record.** If it isn't written in the repo, the
  agent can't act on it — not the chat thread, not the doc in someone's drive, not
  the command you ran once. Encode it as committed markdown or lose it.
- **A short index, not an encyclopedia.** One giant instructions file rots, crowds
  out context, and can't be verified. So the entry point (`AGENTS.md`) stays a short
  table of contents that points to deeper docs — progressive disclosure.
- **Guarantee the structure, not the wording.** Guarantee the shape (schema,
  naming, links) mechanically, but leave voice and content free — let the harness
  police the form so no one has to police the substance.
- **Block only on real breakage.** Only genuine breakage should stop you. A
  slightly-off note is cheap to fix afterward, but a gate that blocks you stalls
  real work — so most checks here warn rather than fail.
- **Move the rule into the linter.** When the same mistake recurs, move the rule from
  prose into the linter so it can't recur — judgment encoded once, then applied
  automatically to every note.
- **Garbage collection.** Drift compounds if you ignore it; clear it with a small
  recurring "gardening" pass rather than a big painful purge later.

## How this vault maps to those principles

| Principle | Where it lives here |
|-----------|---------------------|
| A short index, not an encyclopedia | `AGENTS.md` (capped at 120 lines by the linter) |
| System of record | the whole repo; obsidian-git auto-backup |
| Guarantee the structure | `harness/lint-notes.mjs` + `harness/schema.md` |
| Block only on real breakage | pre-commit hook is advisory; only schema errors fail `npm run lint` |
| Move the rule into the linter | edit `lint-notes.mjs` to add a new rule |
| Garbage collection | `harness/garden.md` + `npm run garden` |

For the operating principles in full, see `docs/core-beliefs.md`.
