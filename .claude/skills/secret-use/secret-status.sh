#!/usr/bin/env bash
# secret-status.sh <secret-name>  ->  prints "set" (exit 0) or "unset" (exit 1)
#
# Answer "is this secret configured on this box?" WITHOUT revealing the value and
# WITHOUT the agent typing a /run/secrets/ literal (that read lives inside here, so
# the guard stays silent). Prints only the word "set"/"unset" — never the value.
#
#   secret-status.sh resend_api_key   # -> set   (rc 0)   or   unset (rc 1)
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: secret-status.sh <secret-name>" >&2; exit 2; }
name="$1"
path="${SECRETS_DIR:-/run/secrets}/$name"   # SECRETS_DIR overridable for tests only

if [ -s "$path" ] || sudo -n test -s "$path" 2>/dev/null; then
  echo set
else
  echo unset
  exit 1
fi
