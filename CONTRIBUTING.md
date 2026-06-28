# Contributing

This is a **starter template** — most people will fork it and make it their own
rather than contribute back. That's the intended use. But if you want to improve
the starter itself, here's how.

## What belongs here

- Improvements to the **harness**: the linter, schema, templates, hooks, gardener.
- Clearer **docs**: setup, conventions, the harness summary.
- Fixes that keep the starter **generic and data-free**.

## What does not belong here

- **No personal content.** No real projects, incidents, areas, or decisions — not
  even as examples. The starter ships empty content folders on purpose.
- **No secrets, hostnames, IPs, or identifying data**, ever (see `docs/SECURITY.md`).
- **No verbatim third-party text.** Link to sources; don't paste their articles.

## Before you open a PR

```sh
npm run lint     # must print "✓ verify passed" with no errors
```

Keep `AGENTS.md` under 120 lines (the linter enforces it — it's a short index,
not an encyclopedia). If you add a rule, encode it in `harness/lint-notes.mjs` and
mention it in `docs/conventions.md`.
