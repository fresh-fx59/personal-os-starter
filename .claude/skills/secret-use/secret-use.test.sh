#!/usr/bin/env bash
# secret-use.test.sh — stand-in tests for the secret-use wrappers.
#
# Proves the SECURITY MECHANICS with NO live secret and NO live API:
#   - the secret value never appears in the child/curl argv (would leak to ps)
#   - the value is delivered only via a 0600 file / curl -K config / env var
#   - request shapes match production
# Uses SECRETS_DIR to point at a dummy secret, a fake `curl` on PATH that records
# its own argv + any -K config, and a HOME override for the reveal audit log.
#
# Run: ./secret-use.test.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }

command -v jq >/dev/null || { echo "SKIP: jq not installed (resend-send needs it)"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
SECRET_VAL="SEKRET-VALUE-12345"
mkdir -p "$WORK/secrets"; printf '%s' "$SECRET_VAL" > "$WORK/secrets/dummy"
export SECRETS_DIR="$WORK/secrets"

# Fake curl: clears+records argv to $ARGV_LOG, copies any -K config to $KCFG_LOG
# and any --data-binary @file to $BODY_LOG, prints a canned body, exits 0.
FAKEBIN="$WORK/bin"; mkdir -p "$FAKEBIN"
export ARGV_LOG="$WORK/curl.argv" KCFG_LOG="$WORK/curl.kcfg" BODY_LOG="$WORK/curl.body"
cat > "$FAKEBIN/curl" <<'CURL'
#!/usr/bin/env bash
: > "$ARGV_LOG"; rm -f "$KCFG_LOG" "$BODY_LOG"
args=("$@")
for a in "${args[@]}"; do printf '%s\n' "$a" >> "$ARGV_LOG"; done
i=0
while [ $i -lt ${#args[@]} ]; do
  case "${args[$i]}" in
    -K) cp "${args[$((i+1))]}" "$KCFG_LOG" 2>/dev/null ;;
    --data-binary) v="${args[$((i+1))]}"; [ "${v#@}" != "$v" ] && cp "${v#@}" "$BODY_LOG" 2>/dev/null ;;
  esac
  i=$((i+1))
done
echo '{"id":"fake-message-id"}'
CURL
chmod +x "$FAKEBIN/curl"
export PATH="$FAKEBIN:$PATH"

leaks(){ [ -f "$1" ] && grep -qF "$SECRET_VAL" "$1"; }   # true if the value leaked into file $1

# ---- with-secret.sh --file-env ---------------------------------------------
recf="$WORK/recf.sh"; cat > "$recf" <<'R'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$O_ARGV"; cat "$TK_FILE" > "$O_FILE"
R
chmod +x "$recf"
O_ARGV="$WORK/f.argv" O_FILE="$WORK/f.file" "$HERE/with-secret.sh" dummy --file-env TK_FILE -- "$recf" a1 a2
if leaks "$WORK/f.argv"; then no "with-secret --file-env: value NOT in child argv" "leaked"; else ok "with-secret --file-env: value NOT in child argv"; fi
if [ "$(cat "$WORK/f.file" 2>/dev/null)" = "$SECRET_VAL" ]; then ok "with-secret --file-env: 0600 file holds value"; else no "with-secret --file-env: file holds value" "got '$(cat "$WORK/f.file" 2>/dev/null)'"; fi

# ---- with-secret.sh --env --------------------------------------------------
rece="$WORK/rece.sh"; cat > "$rece" <<'R'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$O_ARGV"; printf '%s' "$TK" > "$O_ENV"
R
chmod +x "$rece"
O_ARGV="$WORK/e.argv" O_ENV="$WORK/e.env" "$HERE/with-secret.sh" dummy --env TK -- "$rece" b1
if leaks "$WORK/e.argv"; then no "with-secret --env: value NOT in child argv" "leaked"; else ok "with-secret --env: value NOT in child argv"; fi
if [ "$(cat "$WORK/e.env" 2>/dev/null)" = "$SECRET_VAL" ]; then ok "with-secret --env: value delivered via env"; else no "with-secret --env: env delivery" "got '$(cat "$WORK/e.env" 2>/dev/null)'"; fi

# ---- secret-curl.sh --------------------------------------------------------
"$HERE/secret-curl.sh" dummy 'Authorization: Bearer %s' http://127.0.0.1:9/x >/dev/null
if leaks "$ARGV_LOG"; then no "secret-curl: key NOT in curl argv" "leaked"; else ok "secret-curl: key NOT in curl argv"; fi
if grep -qF "Authorization: Bearer $SECRET_VAL" "$KCFG_LOG" 2>/dev/null; then ok "secret-curl: bearer header in -K config"; else no "secret-curl: header in -K config" "$(cat "$KCFG_LOG" 2>/dev/null)"; fi

# ---- resend-send.sh --dry-run (no read, no send) ---------------------------
dry="$("$HERE/resend-send.sh" --to a@b.com --subject Hi --text hello --secret dummy --dry-run 2>&1)"
if grep -q 'POST https://api.resend.com/emails' <<<"$dry" && grep -q '"text": "hello"' <<<"$dry"; then ok "resend-send --dry-run: shows request shape"; else no "resend-send --dry-run" "$dry"; fi
if grep -qF "$SECRET_VAL" <<<"$dry"; then no "resend-send --dry-run: value not shown" "leaked"; else ok "resend-send --dry-run: value not shown"; fi

# ---- resend-send.sh (real path, fake curl) ---------------------------------
"$HERE/resend-send.sh" --to a@b.com --subject Hi --text hello --secret dummy >/dev/null
if leaks "$ARGV_LOG"; then no "resend-send: key NOT in curl argv" "leaked"; else ok "resend-send: key NOT in curl argv"; fi
if grep -qF "Authorization: Bearer $SECRET_VAL" "$KCFG_LOG" 2>/dev/null; then ok "resend-send: bearer via -K config"; else no "resend-send: bearer" "$(cat "$KCFG_LOG" 2>/dev/null)"; fi
if grep -q '^--data-binary$' "$ARGV_LOG" && grep -q '"text": "hello"' "$BODY_LOG" 2>/dev/null; then ok "resend-send: posts JSON body via --data-binary"; else no "resend-send: body" "$(cat "$BODY_LOG" 2>/dev/null)"; fi

# ---- tg-send.sh ------------------------------------------------------------
"$HERE/tg-send.sh" dummy 12345 "hi there" >/dev/null
if leaks "$ARGV_LOG"; then no "tg-send: token NOT in curl argv" "leaked"; else ok "tg-send: token NOT in curl argv"; fi
if grep -qF "https://api.telegram.org/bot$SECRET_VAL/sendMessage" "$KCFG_LOG" 2>/dev/null; then ok "tg-send: token only in -K url"; else no "tg-send: url" "$(cat "$KCFG_LOG" 2>/dev/null)"; fi
if grep -q '^chat_id=12345$' "$ARGV_LOG"; then ok "tg-send: chat_id on command line (non-secret)"; else no "tg-send: chat_id" ""; fi

# ---- secret-status.sh ------------------------------------------------------
s1="$("$HERE/secret-status.sh" dummy)"; r1=$?
if [ "$s1" = "set" ] && [ "$r1" -eq 0 ]; then ok "secret-status: present -> set/0"; else no "secret-status set" "out=$s1 rc=$r1"; fi
s2="$("$HERE/secret-status.sh" no_such_secret)"; r2=$?
if [ "$s2" = "unset" ] && [ "$r2" -eq 1 ]; then ok "secret-status: absent -> unset/1"; else no "secret-status unset" "out=$s2 rc=$r2"; fi

# ---- reveal-secret.sh ------------------------------------------------------
mkdir -p "$WORK/home"
rv="$(HOME="$WORK/home" "$HERE/reveal-secret.sh" dummy --reason "unit test" 2>"$WORK/reveal.err")"
if [ "$rv" = "$SECRET_VAL" ]; then ok "reveal-secret: prints the value (this IS a reveal)"; else no "reveal-secret: value" "got '$rv'"; fi
RLOG="$WORK/home/.claude/logs/secret-reveals.log"
if grep -q 'secret=dummy' "$RLOG" 2>/dev/null && grep -q 'reason=unit test' "$RLOG" 2>/dev/null; then ok "reveal-secret: audit line written"; else no "reveal-secret: audit" "$(cat "$RLOG" 2>/dev/null)"; fi
if grep -q 'DELIBERATE SECRET REVEAL' "$WORK/reveal.err"; then ok "reveal-secret: loud stderr banner"; else no "reveal-secret: banner" "$(cat "$WORK/reveal.err")"; fi
perm="$(stat -c '%a' "$RLOG" 2>/dev/null || echo '?')"
if [ "$perm" = "600" ]; then ok "reveal-secret: audit log is 0600"; else no "reveal-secret: log perms" "got $perm"; fi

# ---- HARDENING fixes (adversarial review) ----------------------------------
leaks_val(){ [ -f "$1" ] && grep -qF "$2" "$1"; }

# secret-curl.sh: a key containing " \ % (and a literal %s) must reach the header VERBATIM
SPECIAL='ab"c\d%se%f'
printf '%s' "$SPECIAL" > "$WORK/secrets/special"
"$HERE/secret-curl.sh" special 'Authorization: Bearer %s' http://127.0.0.1:9/x >/dev/null
if grep -qF "Authorization: Bearer $SPECIAL" "$KCFG_LOG" 2>/dev/null; then ok 'secret-curl: special-char key (" \\ %) verbatim in header'; else no "secret-curl: special-char key" "$(cat "$KCFG_LOG" 2>/dev/null)"; fi
if leaks_val "$ARGV_LOG" "$SPECIAL"; then no "secret-curl: special key not in argv" "leaked"; else ok "secret-curl: special key not in argv"; fi

# resend-send.sh: --text is ALWAYS literal (even starting with @), plus -file / -stdin
o="$("$HERE/resend-send.sh" --to a@b.com --subject S --text '@literal-mention' --secret dummy --dry-run 2>&1)"
grep -q '"text": "@literal-mention"' <<<"$o" && ok "resend-send: --text '@...' stays literal" || no "resend-send: literal @" "$o"
echo "filebody" > "$WORK/tb.txt"
o="$("$HERE/resend-send.sh" --to a@b.com --subject S --text-file "$WORK/tb.txt" --secret dummy --dry-run 2>&1)"
grep -q '"text": "filebody"' <<<"$o" && ok "resend-send: --text-file reads a file" || no "resend-send: --text-file" "$o"
o="$(printf 'stdinbody' | "$HERE/resend-send.sh" --to a@b.com --subject S --text-stdin --secret dummy --dry-run 2>&1)"
grep -q '"text": "stdinbody"' <<<"$o" && ok "resend-send: --text-stdin reads stdin" || no "resend-send: --text-stdin" "$o"

# with-secret.sh --env must NOT hand the value to the external env(1) (world-readable /proc/cmdline)
fe="$WORK/fakeenv"; mkdir -p "$fe"
cat > "$fe/env" <<'E'
#!/bin/bash
printf '%s\n' "$@" >> "$ENVCALL_LOG"; exec /usr/bin/env "$@"
E
chmod +x "$fe/env"; export ENVCALL_LOG="$WORK/envcall.log"; : > "$ENVCALL_LOG"
PATH="$fe:$PATH" "$HERE/with-secret.sh" dummy --env TK -- true
if leaks_val "$ENVCALL_LOG" "$SECRET_VAL"; then no "with-secret --env: no env(1) argv exposure" "value passed to env(1)"; else ok "with-secret --env: no env(1) argv exposure"; fi

echo ""; echo "=== Summary ==="; echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
