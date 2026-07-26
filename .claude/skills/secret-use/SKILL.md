---
name: secret-use
description: Use whenever you need to USE a secret at runtime — send email via Resend, send a Telegram message, call an LLM or any header-auth HTTP API, or query a Postgres DB — instead of reading the secret file inline (which the secret-read guard DENIES + nudges). Covers with-secret.sh, secret-curl.sh, resend-send.sh, tg-send.sh, secret-status.sh, and the one sanctioned reveal path reveal-secret.sh. Also read this when the guard denied a command and told you to come here.
---

# secret-use — run operations with a secret without leaking it

The **secret-read guard** (`../../hooks/secret-read-guard.sh`) **denies** any Bash/Read/Grep/Glob call
that would print a secret value inline — a literal path under the secrets directory, a `sops -d`, or age
key material — and feeds you a nudge pointing here. It is **autonomous**: no human prompt, so when you
get that deny, just re-run through the right wrapper below.

The wrappers read the secret *inside the script*, so your command carries no secret-path literal (guard
stays silent) and the value never reaches `ps`/argv/stdout/logs — it only ever lands in a mode-0600 file
or a `curl -K` config that is shredded on exit.

**Rule of thumb:** you almost never need the *value* — you need the *effect* (an email sent, an API
called, a query run). Reach for a wrapper. `reveal-secret.sh` is only for when a human explicitly asked
to SEE a raw value.

## The wrappers (all in this directory; invoke by absolute path from any session)

| Wrapper | Use it to | Example |
|---------|-----------|---------|
| `secret-curl.sh` | any header-auth HTTP API call | `secret-curl.sh llm_api_key 'Authorization: Bearer %s' https://api.example.com/v1/models` |
| `with-secret.sh` | run any program with a secret in a `*_FILE` path or env var | `with-secret.sh database_url --env DSN -- sh -c 'psql "$DSN" -c "select 1"'` |
| `resend-send.sh` | send one email via Resend | `resend-send.sh --to me@x.com --subject Hi --text-file /tmp/body.txt` |
| `tg-send.sh` | send one Telegram message (bot token) | `tg-send.sh alert_bot_token 123456789 "done ✅"` |
| `secret-status.sh` | check a secret is set (no reveal) | `secret-status.sh resend_api_key` → `set`/`unset` |
| `reveal-secret.sh` | **only** when a human asked to SEE the value | `reveal-secret.sh some_service_api_key --reason "paste into vendor console"` |

`secret-curl.sh` and `with-secret.sh` are the **generic core** — a new service normally needs no new
file. `resend-send.sh` and `tg-send.sh` are thin conveniences built on them, worth having only because
those two calls recur constantly.

`secret-curl.sh`'s header template takes exactly one `%s`:

| Template | Used by |
|----------|---------|
| `'Authorization: Bearer %s'` | Resend, OpenAI, most APIs |
| `'x-api-key: %s'` | Anthropic |
| `'x-goog-api-key: %s'` | Gemini (**not** Bearer) |
| `'Authorization: %s'` | APIs wanting a raw key with no scheme |

## Which secret gets which wrapper

Classify each secret once, when you add it:

**use-wrapper** — the agent legitimately performs an outward operation, so there is a wrapper and the
value need never be seen: email keys, bot tokens, LLM/API keys, database URLs.

**reveal-only** — there is **no wrapper** because a reveal *is* the dangerous act. Key-encryption keys,
signing/session secrets, Fernet keys, API `session_string` / `api_id` / `api_hash`, bare role passwords,
VPN auth keys, and any age/sops host key. If a human genuinely asks for one, `reveal-secret.sh` prints it
and writes a loud audit line to `~/.claude/logs/secret-reveals.log`.

## Setup

1. Point the wrappers at wherever your secrets are rendered: `SECRETS_DIR` (default `/run/secrets`, the
   sops-nix convention). One file per secret, named after it.
2. Set `SECRET_USE_DIR` (or edit the `SU =` line in the guard) to this directory's **absolute** path —
   the nudge is read by an agent whose cwd is unknown.
3. Register the guard as a `PreToolUse` hook for `Bash`, `Read`, `Grep`, and `Glob` in your
   `settings.json`, and symlink it into `~/.claude/hooks/` so the committed copy *is* the live one.

## Notes

- Reading order: the secret is read directly if the file is readable by your user, else via passwordless
  `sudo -n cat`. Both stay inside the wrapper.
- `SECRETS_DIR` doubles as the **test-only** override used by `secret-use.test.sh`.
- Tests: `./secret-use.test.sh` (stand-in: dummy secret + fake `curl`, no live API or email) proves the
  value never reaches argv and that the request shapes are right. Guard tests:
  `../../hooks/secret-read-guard.test.sh`.
