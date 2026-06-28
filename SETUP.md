# SETUP — stand up your Personal OS

This guide is written to be **runnable by a human or by an agent**. If you use a
coding agent (Claude Code, Codex, etc.), you can open this repo and say:

> "Read SETUP.md and set up my Personal OS. Use my GitHub account `<your-handle>`.
> Create a **private** repo for my vault. Ask me before pushing anything."

Otherwise, follow the steps yourself — it takes a few minutes.

## What you need

- [Obsidian](https://obsidian.md) (free).
- `git` and the [GitHub CLI](https://cli.github.com/) (`gh`) — or any way to create
  and push to a private GitHub repo.
- [Node.js](https://nodejs.org) 18+ (only for the linter; the vault itself is just
  markdown).

## Steps

### 1. Get the files

Use this repo as a **template** (GitHub → *Use this template*), or clone and
re-point the remote so your notes never push to the starter:

```sh
git clone https://github.com/<starter-owner>/personal-os-starter.git my-personal-os
cd my-personal-os
rm -rf .git            # drop the starter's history — this vault is yours now
git init
```

### 2. Make it your own private repo

Your vault will hold personal notes, so its remote must be **private**.

```sh
# with the GitHub CLI:
gh repo create my-personal-os --private --source=. --remote=origin

# or manually: create a private repo on github.com, then:
# git remote add origin git@github.com:<you>/my-personal-os.git
```

> ⚠️ **Never make your own vault public without scrubbing it.** Hostnames, IPs,
> internal names, and dated incidents can identify you even without secrets. See
> `docs/SECURITY.md`.

### 3. Arm the verify hook and check the vault is healthy

```sh
sh harness/install.sh    # points git at harness/hooks (not cloned by default)
npm run lint             # should print "✓ verify passed"
```

`npm run lint` is the **verify** step — it enforces the note schema. The pre-commit
hook runs the same check *advisorily* and never blocks a commit.

### 4. Open it in Obsidian and turn on auto-backup

1. Obsidian → **Open folder as vault** → pick `my-personal-os`.
2. **Settings → Community plugins → Browse** → install **Git** (by Vinzent03) →
   enable it.
3. It will auto-commit and push to your `origin` on an interval. Recommended
   settings and details: `docs/references/obsidian-git-setup.md`.

### 5. Make your first note

```sh
cp templates/project.md projects/active/my-first-project.md
```

Edit it: set the `title`, fill the frontmatter, write a line under **Goal**. Then
link it from `projects/index.md` and verify:

```sh
npm run lint
```

That's it — you have a working Personal OS.

## First commit

```sh
git add -A
git commit -m "chore: initialize my personal os"
git push -u origin main
```

(After this, obsidian-git handles commits and pushes for you.)

## Make it yours

- Edit `AGENTS.md` to set your own priorities and rules — it's *your* map.
- Add or change rules by editing `harness/lint-notes.mjs` (it's ~230 lines of
  dependency-free JS with comments).
- Read `docs/core-beliefs.md` for the operating principles, and
  `docs/references/harness-engineering.md` for the idea behind the whole thing.

## Works with any agent

This repo ships **`AGENTS.md`** — the cross-agent standard read natively by Codex,
Cursor, Gemini CLI, GitHub Copilot, Windsurf, Aider, and ~20 other tools — plus a
one-line **`CLAUDE.md`** that imports it (`@AGENTS.md`) so **Claude Code**, which reads
only `CLAUDE.md`, loads the same instructions. Edit `AGENTS.md`; both stay in sync. Put
any Claude-Code-only notes below the import line in `CLAUDE.md`.

Unix-only and want zero duplication? You can replace `CLAUDE.md` with a symlink
(`ln -s AGENTS.md CLAUDE.md`). The import is preferred, though — it works on Windows
(symlinks there need admin/Developer Mode) and can carry Claude-specific additions.

Personal, gitignored overrides: Claude Code reads `CLAUDE.local.md`; Codex reads
`AGENTS.override.md` (and a global `~/.codex/AGENTS.override.md`).

## For agents: a checklist

If you're an agent setting this up, do these in order and confirm each:

1. Confirm the target GitHub handle and that the new repo must be **private**.
2. Re-init git history (step 1) so the user's vault doesn't inherit starter commits.
3. Create the private repo (step 2). **Do not push until the user approves.**
4. Run `sh harness/install.sh` and `npm run lint`; report the output.
5. Tell the user to do the Obsidian + plugin steps (4) — you can't click in their GUI.
6. Stop and hand back. The user owns the content; you set up the harness.
