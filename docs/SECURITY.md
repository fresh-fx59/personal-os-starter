# SECURITY

How this vault treats sensitive information, and the baseline posture for work
documented here. Generic by design — specific systems get their own note in
`areas/`, and incidents get one in `incidents/`.

## Secrets never live in the vault

- No passwords, API keys, private keys, tokens, or full credentials in any note.
- Reference secrets by *name and location* — e.g. "DB password in 1Password →
  prod" — never by value.
- If a secret is ever committed by mistake, treat it as compromised: rotate it,
  then scrub history. A private repo is still not a place to store secrets.

## What is safe to record

Hostnames, non-sensitive config, package versions, commands run (with secrets
redacted), decisions, and timelines. These are exactly what future-you needs.

## Incident hygiene

When documenting an incident, capture: what was observed, when; what was changed;
and how to verify the fix held. Paste logs only after removing tokens, credentials,
and any addresses you don't want in a backup that syncs off-machine.

## The repo itself

- If your vault holds anything personal, keep its GitHub remote **private**.
- obsidian-git pushes whatever is committed; `.gitignore` keeps volatile and
  local-only files out, but review what you stage when in doubt.
- Sharing your vault publicly? Scrub it first — hostnames, IPs, internal names,
  and dated incidents can be identifying even without secrets.
