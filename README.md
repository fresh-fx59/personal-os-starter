# Personal OS

A personal knowledge vault that doubles as an **agent harness**. You — and your AI
agent — document projects, incidents, and decisions here as versioned markdown. It
opens in [Obsidian](https://obsidian.md) and backs itself up to a private GitHub
repo automatically.

The point: give an agent (Claude, Codex, anything) a repository it can read,
extend, and reason about — so your knowledge survives the chat session it was
created in. If it isn't written down in the repo, the agent can't act on it.

This is a **starter template**. Clone it, make it yours, point it at your own
private remote. Nothing here is specific to anyone — it ships with the structure
and the rules, and none of your data.

## Set it up in minutes

See **[`SETUP.md`](SETUP.md)** — it's written so you can either follow it yourself
or hand the repo to your coding agent and say *"set up my Personal OS."*

The short version:

```sh
# 1. Get the files (use this as a template, or clone then re-point the remote)
git clone https://github.com/<you>/personal-os-starter.git my-personal-os
cd my-personal-os

# 2. Arm the verify hook and check it's healthy
sh harness/install.sh
npm run lint

# 3. Open the folder as an Obsidian vault, install the Git community plugin,
#    and point origin at your own PRIVATE repo. (Details in SETUP.md.)
```

## How it works

- **Open it in Obsidian** — Obsidian → *Open folder as vault* → pick this directory.
- **It backs itself up** — the [obsidian-git](https://github.com/Vinzent03/obsidian-git)
  community plugin auto-commits on an interval and pushes to your `origin` remote.
  See `docs/references/obsidian-git-setup.md`.
- **It stays consistent** — a zero-dependency linter validates every note's
  frontmatter, naming, and links:

  ```sh
  npm run lint      # verify — fails on schema errors (pre-commit runs it advisorily)
  npm run garden    # also surface stale notes to tidy up
  ```

## What ships with it

Beyond the note structure, the vault includes the working pieces an agent needs to
operate safely — all tested, all optional:

| Piece | Why it's here |
|-------|---------------|
| [`SOUL.md`](SOUL.md) + [`hooks/soul-reminder.sh`](.claude/hooks/soul-reminder.sh) | The operator **reply contract**: every answer opens with `DONE`/`ACTION NEEDED`/`DECISION NEEDED`/`BLOCKED`/`FYI` + the bottom line, and ends with a `From you:` block; facts beat agreement. Loaded every session via `CLAUDE.md`, re-anchored each turn by the hook, and the linter fails if it's ever unwired. Ships as the real, lived-in file from the source vault — distilled from mining 271 sessions for the moments the operator had to say "I didn't understand". Rewrite *Who you are* for your own operator. |
| [`.claude/skills/checkpoint/`](.claude/skills/checkpoint/SKILL.md) + [`hooks/checkpoint-restore.sh`](.claude/hooks/checkpoint-restore.sh) | Save a session's state into a note *before* you `/clear`, then have the fresh session auto-reload just that section. Continuity lives in git, not in a giant transcript — this is the prime directive applied to the agent's own context. |
| [`tools/limit-anchor/`](tools/limit-anchor/README.md) | Keep your session warm *on your schedule*: a five-hourly ping that anchors the subscription's rolling usage window to a grid you chose, so a reset never lands mid-afternoon. One command to install on systemd, launchd, or cron. 27 tests. |
| [`tools/pii-guard/`](tools/pii-guard/README.md) | Visibility-aware pre-commit hook: blocks your personal data and secret-shaped strings from entering a **public** repo, passes silently on private ones. **Fill in its denylist — it ships blank.** |
| [`.claude/hooks/secret-read-guard.sh`](.claude/hooks/secret-read-guard.sh) | A `PreToolUse` hook that denies any agent command which would print a secret inline, and nudges it to the right wrapper. Autonomous (no prompt), fails open. 37 tests. |
| [`.claude/skills/secret-use/`](.claude/skills/secret-use/SKILL.md) | The wrappers that guard points at — call an API, run a program, send mail or a message with a secret, without the value ever reaching `ps`, logs, or the transcript. 26 tests. |
| [`tools/tg-export/`](tools/tg-export/README.md) + [`telegram-export-mining`](.claude/skills/telegram-export-mining/SKILL.md) | Turn a Telegram Desktop export into JSONL and mine a 40k-message history inside a token budget, without a naive scraper silently losing a fifth of it. 22 tests. |

Everything here is generic. The infrastructure-specific tooling that lives in the
vault this was extracted from — ssh wrappers, deploy scripts, monitoring queries —
is deliberately left out: those encode hostnames and accounts, and are exactly what
`pii-guard` exists to keep out of a public repo.

## Where to start reading

`AGENTS.md` is the map and `SOUL.md` is the voice (Claude Code loads both through
the `CLAUDE.md` that imports them). Then `docs/core-beliefs.md` and `docs/conventions.md`.
`ARCHITECTURE.md` explains how the vault is built, and
`docs/references/harness-engineering.md` explains the idea behind it.

## Credits & inspiration

- Built on the ideas in OpenAI's **["Harness engineering: leveraging Codex in an
  agent-first world"](https://openai.com/index/harness-engineering/)** — linked,
  not reproduced; please read it at the source.
- Inspired by the **[LLM under the hood](https://t.me/llm_under_hood)** Telegram
  channel.

## License

MIT — see [`LICENSE`](LICENSE). Adopt it, fork it, make it yours.
