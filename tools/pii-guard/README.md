# pii-guard — keep your personal data out of public repos

A layered guard against your personal data (chat ids, real name, emails, server IPs,
host labels) or secret-shaped strings leaking into a **public** GitHub repo.

This exists because an agent working across a private vault and several public repos
will eventually copy a snippet from one into the other — and a leak into a public repo
is permanent (clones, forks and scrapers cache it long after you delete the commit).

## ⚠ Configure it before you trust it

`pii-secret-scan.sh` ships with the identifier patterns **blanked out** — a denylist of
someone else's identifiers protects nobody. Open it and fill in the `FILL ME` block
with your own (chat ids, emails, surname, server IPs, host labels). The generic
secret-**shape** patterns (API keys, bot tokens, private keys) work with no setup.

Never put a live secret *value* in `PATTERNS` — this file is committed. Match secrets
by shape, as the generic block does. A key worth blocking is a key worth rotating.

## Why "visibility-aware"

The same string can be fine in one repo and a permanent leak in another, so the hook
decides by **repo visibility**:

| Repo | Behaviour |
|------|-----------|
| Confirmed `public` (via `gh api`) | **Block** the commit, print the offending additions |
| Private | Pass silently — your vault legitimately holds this data |
| Unknown (no `gh`, no network) | Pass with an advisory note |

It also allowlists any remote matching `personal-os` outright, and **fails open** on
any error: a guard that blocks your vault's auto-backup is worse than the leak it
prevents.

## Parts

| File | Role |
|------|------|
| `pii-secret-scan.sh` | The denylist + scanner. Modes: default (tree), `--staged`, `--history`. Single source of truth for what counts as PII. |
| `hooks/pre-commit` | Visibility-aware pre-commit: blocks staged PII on public repos, passes private/unknown. |
| `install.sh` | Arm the hook in one repo's `.git/hooks` (chains any existing hook). Idempotent. |

## Layers of protection

1. **Server-side, every public repo:** turn on GitHub secret-scanning **push
   protection**. It blocks provider-detectable secrets at push time, unbypassably,
   with zero install — but it does **not** catch custom PII (your chat id, name,
   server IPs). That gap is what this hook fills.
2. **This vault's box:** wire the hook globally so every public-repo commit an agent
   makes is gated:
   `git config --global core.hooksPath <vault>/tools/pii-guard/hooks`
   The vault itself stays insulated (its own `core.hooksPath = harness/hooks`, armed
   by `harness/install.sh`) and keeps its advisory lint.
3. **Every other machine you commit from:** run `tools/pii-guard/install.sh <repo>` in
   each public-repo clone, or set it globally as above. **Also set your git author to
   a noreply identity** so commits stop embedding your real work email:
   `git config --global user.email "<id>+<user>@users.noreply.github.com"`.

## Usage

```sh
tools/pii-guard/pii-secret-scan.sh .              # scan a working tree
tools/pii-guard/pii-secret-scan.sh --staged .     # what THIS commit would add
tools/pii-guard/pii-secret-scan.sh --history .    # every blob across all refs (slow)
tools/pii-guard/install.sh ~/code/some-public-repo
```

Exit 0 = clean, 1 = hits found (printed).

## Maintenance

- **New identifier?** Add it to `PATTERNS` in `pii-secret-scan.sh` — the hook and every
  audit pick it up immediately.
- **Before making any private repo public**, run `pii-secret-scan.sh --history .` on it
  first. A commit-time hook cannot retroactively protect history.
- False positive: `git commit --no-verify`.
- **What this does NOT do:** rewrite existing history, or scrub commit-author metadata.
  A leak already in history survives a working-tree scrub — the fix is `git filter-repo`
  plus a force-push, and for a leaked *credential*, rotation. Rotate first; scrubbing is
  the slower, less important half.
