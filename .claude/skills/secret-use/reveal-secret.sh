#!/usr/bin/env bash
# reveal-secret.sh <secret-name> [--reason "why"]
#
# The ONE sanctioned path to reveal a raw secret VALUE to the agent/transcript.
# Use ONLY when a human explicitly asked to SEE the value (e.g. paste a key into a
# provider console) — for USING a secret, use a wrapper (with-secret.sh /
# secret-curl.sh / resend-send.sh / tg-send.sh) so the value never leaks.
#
# It is autonomous (NO operator prompt) but LOUD and LOGGED: every reveal appends
# an audit line to ~/.claude/logs/secret-reveals.log and prints a banner to stderr.
# Its command carries no /run/secrets literal, so the guard stays silent — this is
# deliberately the blessed reveal channel.
set -euo pipefail

name=""; reason=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reason) reason="${2:-}"; shift 2 ;;
    --*)      echo "reveal-secret.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)        [ -z "$name" ] && name="$1" || { echo "reveal-secret.sh: one secret at a time" >&2; exit 2; }; shift ;;
  esac
done
[ -n "$name" ] || { echo "usage: reveal-secret.sh <secret-name> [--reason \"why\"]" >&2; exit 2; }

path="${SECRETS_DIR:-/run/secrets}/$name"   # SECRETS_DIR overridable for tests only
if [ -r "$path" ]; then
  val="$(cat "$path")"
elif sudo -n test -r "$path" 2>/dev/null; then
  val="$(sudo -n cat "$path")"
else
  echo "reveal-secret.sh: cannot read /run/secrets/$name (missing, or no sudo)" >&2; exit 1
fi

# Audit — record THAT a reveal happened (never the value).
logdir="$HOME/.claude/logs"; logf="$logdir/secret-reveals.log"
( umask 077; mkdir -p "$logdir"; : >> "$logf"; chmod 600 "$logf" 2>/dev/null || true )
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\tsecret=%s\tcwd=%s\tsession=%s\tppid=%s\treason=%s\n' \
  "$ts" "$name" "$PWD" "${CLAUDE_SESSION_ID:-${CLAUDE_SESSION:-unknown}}" "$PPID" "${reason:-}" \
  >> "$logf"

echo "⚠ DELIBERATE SECRET REVEAL: $name — logged to $logf${reason:+ (reason: $reason)}" >&2
printf '%s\n' "$val"
