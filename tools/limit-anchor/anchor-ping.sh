#!/usr/bin/env bash
# limit-anchor / anchor-ping.sh
#
# Fire one tiny, token-less `claude -p` so the Claude subscription's rolling
# 5-hour usage window OPENS AT A TIME YOU CHOSE instead of whenever your first
# real message of the day happens to land.
#
# The window is not a quota that refills on a clock you control: it starts on
# your first request and expires five hours later. Anchor it on a fixed grid and
# a reset is always near when you sit down; leave it unanchored and a window you
# opened at 06:40 for one throwaway question expires at 11:40 — in the middle of
# the afternoon you actually needed it.
#
# Run this from a timer (see install.sh). It is deliberately cheap: haiku, no
# tools, no session persistence, one word of output.
#
# Requires: bash, claude (>= 2.1.186), jq. Linux and macOS.
#
# Environment (all optional — install.sh writes them into anchor.conf):
#   CLAUDE_BIN                     path to the claude CLI            [claude]
#   CC_ANCHOR_MODEL                model for the ping                [haiku]
#   CC_ANCHOR_TIMEOUT              hard cap in seconds on one ping   [900]
#   CC_ANCHOR_PING_CWD             scratch cwd for the ping          [~/.cache/limit-anchor-ping]
#   CC_ANCHOR_STAMP_GUARD_STATE    1 = also stamp a pause-at-threshold
#                                  guard's state file (see README)   [0]
#   CC_LIMIT_GUARD_STATE           that state file                   [~/.claude/rate-limit-state.json]
#   CC_LIMIT_GUARD_THRESHOLD       stamp only at/above this percent  [98]
#   CC_LIMIT_GUARD_STATE_TTL       treat state older than this as stale [21600]
#
# Always exits 0: a timer unit that goes red because the API was busy is noise.
set -u
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CC_ANCHOR_CONF:-$SELF_DIR/anchor.conf}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
MODEL="${CC_ANCHOR_MODEL:-haiku}"
PING_TIMEOUT="${CC_ANCHOR_TIMEOUT:-900}"
PING_CWD="${CC_ANCHOR_PING_CWD:-$HOME/.cache/limit-anchor-ping}"
STAMP="${CC_ANCHOR_STAMP_GUARD_STATE:-0}"
STATE="${CC_LIMIT_GUARD_STATE:-$HOME/.claude/rate-limit-state.json}"
THRESHOLD="${CC_LIMIT_GUARD_THRESHOLD:-98}"
STATE_TTL="${CC_LIMIT_GUARD_STATE_TTL:-21600}"

# ---- portability shims (GNU coreutils vs BSD/macOS) -------------------------
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
_utc()   { date -u -d "@$1" '+%Y-%m-%d %H:%M UTC' 2>/dev/null \
           || date -u -r "$1" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || echo "@$1"; }

# Best-effort mutual exclusion with any other writer of the state file (an
# interactive statusline snapshot, a second ping). Both sides do a
# read-modify-write; interleaving them can drop a window. Never block for long —
# the lock is a nicety, the ping is not worth stalling a timer over.
_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$STATE.lock" 2>/dev/null && flock -w 2 9 2>/dev/null || :
  else
    i=0
    while [ "$i" -lt 20 ] && ! mkdir "$STATE.lock.d" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
  fi
}
_unlock() {
  if command -v flock >/dev/null 2>&1; then exec 9>&- 2>/dev/null || :
  else rmdir "$STATE.lock.d" 2>/dev/null || :; fi
}

# ---- the ping ---------------------------------------------------------------
mkdir -p "$PING_CWD" && cd "$PING_CWD" || exit 0

if [ -n "${CC_ANCHOR_FAKE_OUT:-}" ]; then
  # Test seam only: replay a canned stream-json transcript instead of calling the
  # API, so the state-stamping logic below can be exercised offline.
  out="$(cat "$CC_ANCHOR_FAKE_OUT" 2>/dev/null)"; rc=${CC_ANCHOR_FAKE_RC:-0}
else
  # `timeout` is the load-bearing bound here, NOT the retry watchdog. On a hard
  # 429 the CLI runs its own internal api_retry loop and will happily sit on a
  # multi-hour retry_delay; CLAUDE_CODE_RETRY_WATCHDOG=0 does not stop it. Keep
  # the timeout below whatever your timer's own start-timeout is.
  out="$(env CLAUDE_CODE_RETRY_WATCHDOG=0 timeout "$PING_TIMEOUT" \
    "$CLAUDE_BIN" -p 'Reply with exactly: pong' --model "$MODEL" \
    --output-format stream-json --verbose --no-session-persistence --tools "" 2>&1)"
  rc=$?
fi

# stream-json is the only headless output format that carries rate_limit_event.
rle="$(printf '%s\n' "$out" \
  | jq -c 'select(.type? == "rate_limit_event") | .rate_limit_info | select(type == "object")' 2>/dev/null \
  | head -1)"

echo "anchor-ping: rc=$rc rate_limit_info=${rle:-none}"
[ "$rc" -ne 0 ] && printf '%s\n' "$out" | tail -5

[ "$STAMP" = "1" ] || exit 0
[ -n "$rle" ] || exit 0

# ---- optional: stamp a pause-at-threshold guard's state file ----------------
# Decide on the authoritative NUMBER, never the status string. The API reports
# status "allowed_warning" — request still ALLOWED, rc=0 — when a window merely
# APPROACHES its cap. Reading that as "limited" once stamped 100% at 56% real
# usage; the guard then denied every tool call for ninety minutes. So: stamp the
# real rounded utilization, and only when it is at/above the same threshold the
# guard itself acts on. Below that, leave the file for a fresher snapshot to own.
# The 0..1.5 range check makes a future units change (0..100) fail OPEN.
read -r wtype resets pct < <(jq -r --argjson thr "$THRESHOLD" '
  (.rateLimitType // "")  as $w
  | ((.resetsAt // -1)    | if type=="number" then floor else -1 end) as $r
  | ((.utilization // -1) | if (type=="number" and . >= 0 and . <= 1.5) then (.*100|round) else -1 end) as $p
  | if ($w=="five_hour" or $w=="seven_day") and ($r>0) and ($p>=$thr)
    then ($w+" "+($r|tostring)+" "+($p|tostring)) else "" end
' <<<"$rle" 2>/dev/null)

now="$(date +%s)"
if [ -n "${wtype:-}" ] && [ -n "${resets:-}" ] && [ -n "${pct:-}" ] \
   && [ "$resets" -gt "$now" ] && [ "$resets" -lt 4102444800 ]; then
  mkdir -p "$(dirname "$STATE")" 2>/dev/null || :
  _lock
  # MERGE into an existing FRESH, valid-object snapshot rather than clobbering
  # it: writing only our one window could erase the OTHER window somebody else
  # recorded and silently downgrade a correct long-window pause. Start from {}
  # when the file is missing, stale, or malformed.
  base='{}'
  if [ -f "$STATE" ]; then
    smt="$(_mtime "$STATE")"
    if [ $(( now - smt )) -le "$STATE_TTL" ]; then
      b="$(jq -c 'select(type=="object")' "$STATE" 2>/dev/null)" && [ -n "$b" ] && base="$b"
    fi
  fi
  payload="$(jq -cn --argjson base "$base" --arg w "$wtype" --argjson p "$pct" --argjson r "$resets" \
    '$base + {($w): {used_percentage:$p, resets_at:$r}}' 2>/dev/null)"
  if [ -n "$payload" ] && tmp="$(mktemp "$STATE.XXXXXX" 2>/dev/null)"; then
    if printf '%s\n' "$payload" >"$tmp" 2>/dev/null; then
      mv -f "$tmp" "$STATE" 2>/dev/null || rm -f "$tmp"
      echo "anchor-ping: $wtype at ${pct}% (>= $THRESHOLD) — merged into guard state until $(_utc "$resets")"
    else
      rm -f "$tmp"
    fi
  fi
  _unlock
else
  echo "anchor-ping: not limited (status=$(jq -r '.status // "?"' <<<"$rle"), util=$(jq -r '.utilization // "?"' <<<"$rle")) — guard state untouched"
fi

exit 0
