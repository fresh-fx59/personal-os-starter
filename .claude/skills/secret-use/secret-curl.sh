#!/usr/bin/env bash
# secret-curl.sh <secret-name> '<header-template>' [curl-args...]
#
# Generic header-authenticated HTTP call. Reads /run/secrets/<secret-name> INSIDE
# this script and injects it into an auth header via a mode-0600 curl -K config,
# so the key is never in the agent's command, argv, or ps — and the guard stays
# silent. The generic bearer/header-API caller.
#
# <header-template> must contain exactly one %s, replaced by the secret value:
#   'Authorization: Bearer %s'   # Resend, OpenAI, most APIs
#   'Authorization: %s'          # Linear personal key (raw, no "Bearer")
#   'x-api-key: %s'              # Anthropic-style
#
# Examples:
#   secret-curl.sh resend_api_key 'Authorization: Bearer %s' \
#       -X POST https://api.resend.com/emails -H 'Content-Type: application/json' -d @body.json
#   secret-curl.sh llm_api_key 'Authorization: Bearer %s' \
#       https://api.example.com/v1/models
#
# See SKILL.md.
set -euo pipefail

[ $# -ge 2 ] || { echo "usage: secret-curl.sh <secret-name> '<header-template-with-%s>' [curl-args...]" >&2; exit 2; }
name="$1"; tmpl="$2"; shift 2
case "$tmpl" in *%s*) : ;; *) echo "secret-curl.sh: header-template must contain one %s" >&2; exit 2 ;; esac

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT INT TERM HUP
umask 077

path="${SECRETS_DIR:-/run/secrets}/$name"   # SECRETS_DIR overridable for tests only
if [ -r "$path" ]; then
  KEY="$(cat "$path")"
elif sudo -n test -r "$path" 2>/dev/null; then
  KEY="$(sudo -n cat "$path")"
else
  echo "secret-curl.sh: cannot read /run/secrets/$name (missing, or no sudo)" >&2; exit 1
fi
[ -n "$KEY" ] || { echo "secret-curl.sh: /run/secrets/$name is empty" >&2; exit 1; }

# Header goes in a -K config so the key is never in argv/ps. Substitute the key with
# bash pattern-replacement (NOT a printf format — a template '%' other than %s would
# corrupt it) and write the value UNQUOTED (curl reads the rest of the line literally,
# so a key byte like " or \ is not escape-processed/truncated).
header="${tmpl/'%s'/$KEY}"
printf 'header = %s\n' "$header" > "$d/.c"
unset KEY header

# NOT exec: the EXIT trap must shred the 0600 config (which holds the key) after
# curl returns. set -e propagates curl's exit; the trap preserves it.
curl -sS -K "$d/.c" "$@"
