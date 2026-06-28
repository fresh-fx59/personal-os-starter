# obsidian-git setup

This vault is designed to back itself up with the **Git** community plugin by
Vinzent03 (id `obsidian-git`). It auto-commits and pushes your notes to your own
remote with no manual steps.

## Install it

1. Obsidian → **Settings → Community plugins → Browse**.
2. Search for **Git** (by Vinzent03), install, then enable it.
3. Make sure this vault is already a git repository with an `origin` remote
   pointing at *your own* private repo (see `SETUP.md`).

## What it does here

- **Auto-commit** every few minutes when the vault has changes.
- **Auto-push** to `origin` on the same cadence, so work lands on your remote
  with no manual steps.
- **Pull before push**, to avoid diverging when editing from more than one machine.
- Commit messages use a template like `vault backup: {{date}}`.

## Recommended settings

Settings live in `.obsidian/plugins/obsidian-git/data.json` and can be changed in
Obsidian → Settings → Community plugins → Git → options. Sensible starting values:

| Key | Value | Meaning |
|-----|-------|---------|
| `autoSaveInterval` | `10` | minutes between auto-commits (0 = off) |
| `autoPushInterval` | `10` | minutes between auto-pushes (0 = off) |
| `autoPullOnBoot` | `true` | pull when Obsidian starts |
| `pullBeforePush` | `true` | fetch + merge before pushing |
| `commitMessage` | `vault backup: {{date}}` | commit message template |

## First-run notes

- If git prompts for credentials on push, make sure the `origin` remote can
  authenticate — the GitHub CLI (`gh`) credential helper is the easiest path.
- The repo's git pre-commit hook is **advisory** and finds Node even under the
  GUI's minimal PATH, so it never blocks the plugin's commits.
