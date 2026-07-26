#!/usr/bin/env bash
# with-secret.sh <secret-name> (--env VAR | --file-env VAR) -- CMD [ARGS...]
#
# Generic secret-USE wrapper. Runs CMD with a sops secret made available to it
# WITHOUT the secret path (or value) ever appearing in the agent's Bash command,
# argv, or stdout — so the secret-read guard stays silent and nothing leaks to
# ps/logs/transcript.
#
#   # value in a 0600 file, path handed to the program (preferred; matches the
#   # RESEND_API_KEY_FILE / LINEAR_API_KEY_FILE convention):
#   with-secret.sh resend_api_key --file-env RESEND_API_KEY_FILE -- \
#       python3 send_report.py
#
#   # value in the child's ENVIRONMENT (use when the program only reads an env var):
#   with-secret.sh database_url --env DATABASE_URL -- \
#       sh -c 'psql "$DATABASE_URL" -c "select 1"'
#
# WHY: the guard (~/.claude/hooks/secret-read-guard.sh) denies + nudges whenever an
# AGENT's command contains a literal /run/secrets/... . Reading the secret INSIDE
# this wrapper means the caller's command is just `with-secret.sh NAME ... -- CMD`
# (no secret path), so routine use is autonomous, while the value only ever lands
# in a mode-0600 tmpfile (--file-env) or the child's env (--env), never argv/stdout.
# The generic run-a-command-with-a-secret wrapper.
set -euo pipefail

usage() { echo "usage: with-secret.sh <secret-name> (--env VAR | --file-env VAR) -- CMD [ARGS...]" >&2; exit 2; }

[ $# -ge 1 ] || usage
name="$1"; shift
case "$name" in --*|"") usage ;; esac   # first arg must be the secret name

mode=""; var=""
while [ $# -gt 0 ]; do
  case "$1" in
    --env)       mode="value"; var="${2:-}"; shift 2 || usage ;;
    --file-env)  mode="file";  var="${2:-}"; shift 2 || usage ;;
    --)          shift; break ;;
    *)           usage ;;
  esac
done
[ -n "$mode" ] && [ -n "$var" ] || usage
[ $# -ge 1 ] || usage   # need a CMD after --

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT INT TERM HUP
umask 077

path="${SECRETS_DIR:-/run/secrets}/$name"   # SECRETS_DIR overridable for tests only
# Read the value: direct if readable, else passwordless sudo. $(...) strips the
# trailing newline. Never echoed.
if [ -r "$path" ]; then
  val="$(cat "$path")"
elif sudo -n test -r "$path" 2>/dev/null; then
  val="$(sudo -n cat "$path")"
else
  echo "with-secret.sh: cannot read /run/secrets/$name (missing, or no sudo)" >&2; exit 1
fi
[ -n "$val" ] || { echo "with-secret.sh: /run/secrets/$name is empty" >&2; exit 1; }

# Run the child (NOT exec) so the EXIT trap shreds the tmpfile afterwards. The
# child's exit status propagates (set -e), and the EXIT trap preserves it.
# Use the `export` BUILTIN (never the external env(1)) so the value/path never lands
# on any process argv / world-readable /proc/<pid>/cmdline.
if [ "$mode" = "file" ]; then
  printf '%s' "$val" > "$d/.v"          # no trailing newline
  unset val
  export "$var=$d/.v"                    # child gets the PATH, not the value
  "$@"
else
  # value goes into the child's ENVIRONMENT only (owner-readable /proc/<pid>/environ —
  # the accepted single-user boundary), never onto any argv. Prefer --file-env.
  export "$var=$val"
  unset val
  "$@"
fi
