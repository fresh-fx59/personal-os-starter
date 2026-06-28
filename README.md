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

## Where to start reading

`AGENTS.md` is the map (Claude Code loads it through the one-line `CLAUDE.md` that
imports it). Then `docs/core-beliefs.md` and `docs/conventions.md`.
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
