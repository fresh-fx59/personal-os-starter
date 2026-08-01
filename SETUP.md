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

### 6. (Optional) Turn on the hooks

All three ship inert until you wire them up — do it now, or delete them.

**checkpoint** — the one to keep even if you skip the rest. Before you `/clear`, the
`checkpoint` skill writes the session's state into its project note's `## Current
state`; `checkpoint-restore.sh` re-injects exactly that section into the next session.
Nothing to configure beyond registering the hook (below) — the skill writes the pointer
at `~/.claude/last-checkpoint` itself. Verify it end-to-end whenever you change it:

```sh
printf '%s\n' "$PWD/projects/active/some-note.md" > ~/.claude/last-checkpoint
echo '{"source":"clear"}' | .claude/hooks/checkpoint-restore.sh   # prints the section
echo '{"source":"startup"}' | .claude/hooks/checkpoint-restore.sh # silent, exit 0
```

**limit-anchor** — stop your usage window resetting at a useless time of day. The
five-hour window starts on your *first request*, so one throwaway question at
06:40 makes it expire at 11:40, mid-morning. Anchor it to a grid you chose
instead:

```sh
tools/limit-anchor/anchor-ping.test.sh                  # 27 tests, no API calls
tools/limit-anchor/install.sh --first-anchor 07:00 --dry-run   # inspect the grid
tools/limit-anchor/install.sh --first-anchor 07:00      # systemd / launchd / cron
```

Pick `--first-anchor` to be roughly when your day starts; the other three anchors
follow from it. Why four and not five, and why they are 5h03m apart rather than
5h, is in `tools/limit-anchor/README.md` — both answers are counter-intuitive and
worth reading before you edit the grid.

**pii-guard** — stop your personal data reaching a public repo:

```sh
$EDITOR tools/pii-guard/pii-secret-scan.sh   # fill in the FILL ME block: your ids,
                                             # emails, surname, server IPs
tools/pii-guard/pii-secret-scan.sh .         # should print: clean
tools/pii-guard/install.sh ~/code/some-public-repo   # arm it per repo…
git config --global core.hooksPath "$PWD/tools/pii-guard/hooks"   # …or globally
```

The vault itself is allowlisted, and keeps its own advisory hook from step 3.
Details and the layered strategy: `tools/pii-guard/README.md`.

**secret-read-guard** — stop an agent printing a secret into the transcript. It
assumes secrets are rendered as one file per secret (`/run/secrets/<name>`, the
sops-nix convention); point `SECRETS_DIR` elsewhere if yours differ.

```sh
export SECRET_USE_DIR="$PWD/.claude/skills/secret-use"   # absolute; also editable in the hook
bash .claude/hooks/secret-read-guard.test.sh             # 37 tests
bash .claude/skills/secret-use/secret-use.test.sh        # 26 tests
ln -s "$PWD/.claude/hooks/secret-read-guard.sh" ~/.claude/hooks/   # committed copy IS the live one
```

Then register it as a `PreToolUse` hook — copy the `hooks` block from
`.claude/settings.json.example` into your `~/.claude/settings.json` and replace
`<VAULT>` with this directory's absolute path. Rationale and the wrapper table:
`.claude/skills/secret-use/SKILL.md` and `docs/conventions.md`.

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
6. Offer the optional guards (step 6). **`pii-guard`'s denylist needs the user's own
   identifiers** — ask for them, don't guess; run the two test suites and report the
   counts. For `limit-anchor`, **ask what time their working day starts** and pass that
   as `--first-anchor`; don't invent a grid, and don't skip `--dry-run`.
7. Stop and hand back. The user owns the content; you set up the harness.
