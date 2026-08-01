# tools/

Small, self-contained CLI tools the vault's agents use. Each has its own README;
this file is the index.

`tools/` is **excluded from the note linter** — it holds code with ordinary
documentation, not knowledge notes, so it is not held to the frontmatter schema.

| Tool | What it does |
|------|--------------|
| [`limit-anchor/`](limit-anchor/README.md) | Fires one cheap ping every five hours so the Claude subscription's rolling usage window opens **at times you chose**, not whenever your first message of the day landed. Installs a systemd user timer, a launchd agent, or cron lines. |
| [`pii-guard/`](pii-guard/README.md) | Visibility-aware pre-commit hook + scanner that blocks your personal data and secret-shaped strings from entering a **public** repo. **Configure the denylist before trusting it.** |
| [`tg-export/`](tg-export/README.md) | Zero-dependency parser turning a Telegram Desktop HTML export into JSONL, plus `search` / `window` / `thread` / `stats` subcommands for mining a large chat history inside a token budget. Paired with the `telegram-export-mining` skill. |

## Adding a tool here

Keep the bar: a tool earns a place in the vault when an agent will reach for it
again, and it works without a bespoke environment. Give it a README with a usage
block and its gotchas, tests if it parses anything, and add a row above.

Tools that are specific to *your* infrastructure — ssh wrappers for your hosts,
deploy scripts for your flake, monitoring queries against your Prometheus — belong
here too, but they are exactly what you should **not** copy into a public repo.
They encode hostnames, IPs, and account names. Write them for yourself; keep
`pii-guard` armed.
