#!/usr/bin/env bash
# Tests for limit-anchor. Offline: the ping's API call is replaced by a canned
# stream-json transcript via CC_ANCHOR_FAKE_OUT, so nothing here spends tokens.
#
#   ./anchor-ping.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PING="$DIR/anchor-ping.sh"
INSTALL="$DIR/install.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
contains() { # name haystack needle
  case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "[$2] does not contain [$3]" ;; esac
}

event() { # rateLimitType utilization resetsAt status -> canned transcript
  printf '{"type":"system","subtype":"init"}\n'
  printf '{"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"%s","utilization":%s,"resetsAt":%s,"status":"%s"}}\n' "$1" "$2" "$3" "$4"
  printf '{"type":"result","result":"pong"}\n'
}

run_ping() { # state-file  transcript-file  [extra env assignments...]
  local st="$1" tr="$2"; shift 2
  env CC_ANCHOR_CONF=/nonexistent CC_ANCHOR_FAKE_OUT="$tr" \
      CC_ANCHOR_PING_CWD="$TMP/cwd" CC_ANCHOR_STAMP_GUARD_STATE=1 \
      CC_LIMIT_GUARD_STATE="$st" "$@" bash "$PING" 2>&1
}

echo "grid computation"
out="$("$INSTALL" --first-anchor 07:00 --dry-run 2>&1 | head -1)"
check "07:00 -> 5h03m grid" "anchor grid (local time): 07:00 12:03 17:06 22:09" "$out"

out="$("$INSTALL" --first-anchor 22:00 --dry-run 2>&1 | head -1)"
check "wraps past midnight" "anchor grid (local time): 22:00 03:03 08:06 13:09" "$out"

out="$("$INSTALL" --first-anchor 09:05 --dry-run 2>&1 | head -1)"
check "carries minutes over the hour" "anchor grid (local time): 09:05 14:08 19:11 00:14" "$out"

"$INSTALL" --first-anchor 25:00 --dry-run >/dev/null 2>&1 \
  && bad "rejects hour 25" "exited 0" || ok "rejects hour 25"
"$INSTALL" --first-anchor 7am --dry-run >/dev/null 2>&1 \
  && bad "rejects non HH:MM" "exited 0" || ok "rejects non HH:MM"
"$INSTALL" --dry-run >/dev/null 2>&1 \
  && bad "requires --first-anchor" "exited 0" || ok "requires --first-anchor"

out="$("$INSTALL" --first-anchor 07:00 --cron --dry-run 2>&1)"
contains "cron output has a 12:03 line" "$out" "3 12 * * *"

echo
echo "unit generation does not touch the system in --dry-run"
before="$(ls "$HOME/.config/systemd/user" 2>/dev/null | grep -c limit-anchor || true)"
"$INSTALL" --first-anchor 07:00 --dry-run >/dev/null 2>&1
after="$(ls "$HOME/.config/systemd/user" 2>/dev/null | grep -c limit-anchor || true)"
check "no units written" "$before" "$after"

echo
echo "state stamping"
FUTURE=$(( $(date +%s) + 9000 ))
PAST=$(( $(date +%s) - 60 ))

# 1. a merely-approaching window must NOT be treated as a limit
st="$TMP/s1.json"; tr="$TMP/t1.json"; event five_hour 0.57 "$FUTURE" allowed_warning > "$tr"
out="$(run_ping "$st" "$tr")"
contains "allowed_warning at 57% leaves state alone" "$out" "guard state untouched"
[ -f "$st" ] && bad "no state file created at 57%" "file exists" || ok "no state file created at 57%"

# 2. at/above threshold it stamps the real rounded utilization
st="$TMP/s2.json"; tr="$TMP/t2.json"; event five_hour 0.991 "$FUTURE" allowed_warning > "$tr"
out="$(run_ping "$st" "$tr")"
contains "99% is stamped" "$out" "five_hour at 99%"
check "used_percentage is the real number" "99" "$(jq -r '.five_hour.used_percentage' "$st")"
check "resets_at recorded" "$FUTURE" "$(jq -r '.five_hour.resets_at' "$st")"

# 3. merging preserves a window this ping did not report
st="$TMP/s3.json"; tr="$TMP/t3.json"
echo '{"seven_day":{"used_percentage":99,"resets_at":'"$FUTURE"'}}' > "$st"
event five_hour 0.99 "$FUTURE" allowed_warning > "$tr"
out="$(run_ping "$st" "$tr")"
check "seven_day survives" "99" "$(jq -r '.seven_day.used_percentage' "$st")"
check "five_hour added" "99" "$(jq -r '.five_hour.used_percentage' "$st")"

# 4. a stale snapshot is replaced, not merged into
st="$TMP/s4.json"; tr="$TMP/t4.json"
echo '{"seven_day":{"used_percentage":99,"resets_at":'"$FUTURE"'}}' > "$st"
touch -d '1970-01-02' "$st" 2>/dev/null || touch -t 197001020000 "$st"
event five_hour 0.99 "$FUTURE" allowed_warning > "$tr"
run_ping "$st" "$tr" >/dev/null
check "stale seven_day dropped" "null" "$(jq -r '.seven_day' "$st")"

# 5. out-of-range utilization (a units change to 0..100) must fail OPEN
st="$TMP/s5.json"; tr="$TMP/t5.json"; event five_hour 99 "$FUTURE" allowed > "$tr"
out="$(run_ping "$st" "$tr")"
contains "utilization=99 is not read as 99%" "$out" "guard state untouched"
[ -f "$st" ] && bad "no state file from bogus units" "file exists" || ok "no state file from bogus units"

# 6. a reset time already in the past is nonsense — ignore it
st="$TMP/s6.json"; tr="$TMP/t6.json"; event five_hour 0.99 "$PAST" allowed_warning > "$tr"
out="$(run_ping "$st" "$tr")"
[ -f "$st" ] && bad "past resetsAt ignored" "file exists" || ok "past resetsAt ignored"

# 7. an unknown window type is ignored
st="$TMP/s7.json"; tr="$TMP/t7.json"; event one_minute 0.99 "$FUTURE" allowed_warning > "$tr"
run_ping "$st" "$tr" >/dev/null
[ -f "$st" ] && bad "unknown window type ignored" "file exists" || ok "unknown window type ignored"

# 8. stamping is off by default — the starter ships no guard to read it
st="$TMP/s8.json"; tr="$TMP/t8.json"; event five_hour 0.99 "$FUTURE" allowed_warning > "$tr"
out="$(env CC_ANCHOR_CONF=/nonexistent CC_ANCHOR_FAKE_OUT="$tr" CC_ANCHOR_PING_CWD="$TMP/cwd" \
        CC_LIMIT_GUARD_STATE="$st" bash "$PING" 2>&1)"
[ -f "$st" ] && bad "stamping is opt-in" "file exists" || ok "stamping is opt-in"
contains "still logs the rate-limit info" "$out" "rate_limit_info="

# 9. no rate_limit_event at all is a normal, quiet outcome
st="$TMP/s9.json"; tr="$TMP/t9.json"; printf '{"type":"result","result":"pong"}\n' > "$tr"
out="$(run_ping "$st" "$tr")"
contains "no event reported as none" "$out" "rate_limit_info=none"

# 10. malformed transcript must not crash or write anything
st="$TMP/s10.json"; tr="$TMP/t10.json"; printf 'not json at all\n<html>\n' > "$tr"
out="$(run_ping "$st" "$tr")"; rc=$?
check "garbage input still exits 0" "0" "$rc"
[ -f "$st" ] && bad "garbage writes nothing" "file exists" || ok "garbage writes nothing"

# 11. a failed ping is reported but never fails the timer
st="$TMP/s11.json"; tr="$TMP/t11.json"; printf 'error: overloaded\n' > "$tr"
out="$(run_ping "$st" "$tr" CC_ANCHOR_FAKE_RC=1)"; rc=$?
check "nonzero ping still exits 0" "0" "$rc"
contains "failure is logged" "$out" "rc=1"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
