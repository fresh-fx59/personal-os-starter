#!/usr/bin/env bash
# resend-send.sh --to ADDR [--to ADDR...] --subject STR <BODY> [--from STR] [--secret NAME] [--dry-run]
#
# Send one email via Resend WITHOUT exposing the API key. The key is read inside
# secret-curl.sh, so the agent's command carries no secret-path literal and the read
# guard stays silent. See SKILL.md.
#
# Exactly one BODY form (input-gated — a literal body is ALWAYS literal, even if it
# starts with '@' or '-'):
#   --text STR | --html STR            literal body
#   --text-file F | --html-file F      body from a file
#   --text-stdin | --html-stdin        body from stdin
#
#   resend-send.sh --to me@example.com --subject "Digest" --text-file /tmp/digest.txt
#   echo "<h1>hi</h1>" | resend-send.sh --to a@b.com --subject Hi --html-stdin
#   resend-send.sh --to a@b.com --subject Test --text "@handles are fine" --dry-run
#
# Defaults: --secret resend_api_key, --from the sender domain you verified in Resend.
set -euo pipefail

SECRET="resend_api_key"
# CONFIGURE ME: a sender you have verified in Resend (an unverified From is rejected).
FROM="${RESEND_FROM:-Personal OS <noreply@example.com>}"
SUBJECT=""; CKEY=""; RAWBODY=""; DRY=0
TO=()

set_body() {  # $1=text|html  $2=literal|file|stdin  $3=value (literal/file)
  [ -z "$CKEY" ] || { echo "resend-send.sh: give exactly one body (--text/--html + -file/-stdin variants)" >&2; exit 2; }
  CKEY="$1"
  case "$2" in
    literal) RAWBODY="$3" ;;
    file)    RAWBODY="$(cat -- "$3")" ;;
    stdin)   RAWBODY="$(cat)" ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --to)          TO+=("${2:?}"); shift 2 ;;
    --subject)     SUBJECT="${2:?}"; shift 2 ;;
    --text)        set_body text literal "${2:?}"; shift 2 ;;
    --html)        set_body html literal "${2:?}"; shift 2 ;;
    --text-file)   set_body text file "${2:?}"; shift 2 ;;
    --html-file)   set_body html file "${2:?}"; shift 2 ;;
    --text-stdin)  set_body text stdin; shift ;;
    --html-stdin)  set_body html stdin; shift ;;
    --from)        FROM="${2:?}"; shift 2 ;;
    --secret)      SECRET="${2:?}"; shift 2 ;;
    --dry-run)     DRY=1; shift ;;
    *) echo "resend-send.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[ "${#TO[@]}" -ge 1 ] || { echo "resend-send.sh: need at least one --to" >&2; exit 2; }
[ -n "$SUBJECT" ] || { echo "resend-send.sh: need --subject" >&2; exit 2; }
[ -n "$CKEY" ]    || { echo "resend-send.sh: need a body (--text/--html or -file/-stdin variant)" >&2; exit 2; }

command -v jq >/dev/null || { echo "resend-send.sh: jq required" >&2; exit 1; }

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT INT TERM HUP
umask 077

to_json="$(printf '%s\n' "${TO[@]}" | jq -R . | jq -s .)"
jq -n --argjson to "$to_json" --arg from "$FROM" --arg subject "$SUBJECT" \
      --arg content "$RAWBODY" --arg ckey "$CKEY" \
  '{from:$from, to:$to, subject:$subject} + {($ckey): $content}' > "$d/body.json"

if [ "$DRY" -eq 1 ]; then
  echo "DRY-RUN: POST https://api.resend.com/emails"
  echo "  Authorization: Bearer <secret /run/secrets/$SECRET, not shown>"
  echo "  Content-Type: application/json"
  echo "  body:"; cat "$d/body.json"; echo
  exit 0
fi

# key read inside secret-curl.sh -> never in this command's argv. NOT exec: our
# EXIT trap must shred body.json (and let secret-curl.sh shred its own -K config).
"$(dirname "$0")/secret-curl.sh" "$SECRET" 'Authorization: Bearer %s' \
  -X POST https://api.resend.com/emails \
  -H 'Content-Type: application/json' \
  --data-binary @"$d/body.json"
