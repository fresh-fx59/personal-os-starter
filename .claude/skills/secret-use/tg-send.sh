#!/usr/bin/env bash
# tg-send.sh <token-secret-name> <chat_id> <text>
#
# Send one Telegram message via a bot token WITHOUT exposing the token. The token
# sits in the URL PATH (/bot<TOKEN>/sendMessage), which would leak into argv/ps if
# built inline — so it is read inside this script and the full URL is placed in a
# mode-0600 curl -K config. chat_id + text (non-secret) go on the command line.
#
#   tg-send.sh alert_bot_token 123456789 "deploy finished ✅"
#
# <token-secret-name> is required (many bot tokens exist — no safe default). See
# references/telegram-operator-chat-ids for which chat_id goes with which bot.
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: tg-send.sh <token-secret-name> <chat_id> <text>" >&2; exit 2; }
name="$1"; chat="$2"; text="$3"

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT INT TERM HUP
umask 077

path="${SECRETS_DIR:-/run/secrets}/$name"   # SECRETS_DIR overridable for tests only
if [ -r "$path" ]; then
  TOKEN="$(cat "$path")"
elif sudo -n test -r "$path" 2>/dev/null; then
  TOKEN="$(sudo -n cat "$path")"
else
  echo "tg-send.sh: cannot read /run/secrets/$name (missing, or no sudo)" >&2; exit 1
fi
[ -n "$TOKEN" ] || { echo "tg-send.sh: /run/secrets/$name is empty" >&2; exit 1; }

# URL (with the token) goes in a -K config so the token is never in argv/ps.
printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TOKEN" > "$d/.c"
unset TOKEN

curl -sS -K "$d/.c" -d chat_id="$chat" --data-urlencode "text=$text"
