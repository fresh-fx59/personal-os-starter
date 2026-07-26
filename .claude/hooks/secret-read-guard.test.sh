#!/usr/bin/env bash
# secret-read-guard.test.sh — unit tests for secret-read-guard.sh.
#
# DENY cases:  exit 0 AND stdout contains "permissionDecision":"deny" (+ optional nudge substring)
# ALLOW cases: exit 0 AND stdout is completely empty
#
# Run: ./secret-read-guard.test.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/secret-read-guard.sh"
PASS_COUNT=0; FAIL_COUNT=0

# assert_deny <name> <json> [nudge-substring]
assert_deny() {
    local name="$1" json="$2" want="${3:-}"
    local out status
    out="$(printf '%s' "$json" | "$HOOK")"; status=$?
    if [ "$status" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
        if [ -z "$want" ] || printf '%s' "$out" | grep -qF "$want"; then
            echo "PASS (DENY):  $name"; PASS_COUNT=$((PASS_COUNT + 1)); return
        fi
        echo "FAIL (DENY):  $name — missing nudge substring: $want"
        echo "    stdout=$out"; FAIL_COUNT=$((FAIL_COUNT + 1)); return
    fi
    echo "FAIL (DENY):  $name"; echo "    exit=$status stdout=$out"; FAIL_COUNT=$((FAIL_COUNT + 1))
}

# assert_allow <name> <json>
assert_allow() {
    local name="$1" json="$2"
    local out status
    out="$(printf '%s' "$json" | "$HOOK")"; status=$?
    if [ "$status" -eq 0 ] && [ -z "$out" ]; then
        echo "PASS (ALLOW): $name"; PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL (ALLOW): $name"; echo "    exit=$status stdout=$out"; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "=== DENY cases (block + autonomous nudge, no operator prompt) ==="

assert_deny "Bash: cat /run/secrets literal" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /run/secrets/broker_api_key"}}'

assert_deny "Bash: command substitution read" \
    '{"tool_name":"Bash","tool_input":{"command":"x=$(cat /run/secrets/app_admin_password); echo done"}}'

assert_deny "Bash: resend key -> resend-send.sh hint" \
    '{"tool_name":"Bash","tool_input":{"command":"curl -H \"Authorization: Bearer $(cat /run/secrets/resend_api_key)\" x"}}' \
    'resend-send.sh'

assert_deny "Bash: generic api key -> secret-curl.sh hint" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /run/secrets/some_service_api_key"}}' \
    'secret-curl.sh'

assert_deny "Bash: bot token -> tg-send.sh hint" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /run/secrets/alert_bot_token"}}' \
    'tg-send.sh'

assert_deny "Bash: LLM key -> secret-curl.sh hint" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /run/secrets/llm_api_key"}}' \
    'secret-curl.sh'

assert_deny "Bash: database_url -> with-secret.sh psql hint" \
    '{"tool_name":"Bash","tool_input":{"command":"psql \"$(cat /run/secrets/database_url)\""}}' \
    'with-secret.sh'

assert_deny "Bash: sops -d decrypt" \
    '{"tool_name":"Bash","tool_input":{"command":"sops -d secrets/prod.yaml"}}' \
    'sops'

# age/sops key material: use a form that hits the key-material branch, not sops -d
assert_deny "Bash: age key material (SOPS_AGE_KEY)" \
    '{"tool_name":"Bash","tool_input":{"command":"echo $SOPS_AGE_KEY"}}' \
    'KEY MATERIAL'

assert_deny "Bash: age keys.txt read" \
    '{"tool_name":"Bash","tool_input":{"command":"cat ~/.config/sops/age/keys.txt"}}' \
    'KEY MATERIAL'

assert_deny "Read: file under /run/secrets" \
    '{"tool_name":"Read","tool_input":{"file_path":"/run/secrets/some_service_api_key"}}' \
    'secret-curl.sh'

echo ""
echo "=== DENY: path-evasion hardening (adversarial review) ==="

assert_deny "Bash: glob /run/sec*/" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /run/sec*/some_service_api_key"}}'
assert_deny "Bash: glob /run/secret?/" \
    '{"tool_name":"Bash","tool_input":{"command":"base64 /run/secret?/some_service_api_key"}}'
assert_deny "Bash: variable indirection (bare /run/secrets, no trailing slash)" \
    '{"tool_name":"Bash","tool_input":{"command":"d=/run/secrets; cat \"$d\"/some_service_api_key"}}'
assert_deny "Bash: dot-segment /run/./secrets/" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /run/./secrets/some_service_api_key"}}'
assert_deny "Read: dot-segment /run/./secrets/" \
    '{"tool_name":"Read","tool_input":{"file_path":"/run/./secrets/some_service_api_key"}}'
assert_deny "Read: leading double-slash //run/secrets/" \
    '{"tool_name":"Read","tool_input":{"file_path":"//run/secrets/some_service_api_key"}}'
assert_deny "Bash: interior double-slash /run//secrets/" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /run//secrets/some_service_api_key"}}'
assert_deny "Grep: path under /run/secrets (content mode would leak)" \
    '{"tool_name":"Grep","tool_input":{"pattern":".","path":"/run/secrets/some_service_api_key","output_mode":"content"}}' \
    'secret-curl.sh'
assert_deny "Glob: path at /run/secrets" \
    '{"tool_name":"Glob","tool_input":{"pattern":"*","path":"/run/secrets"}}'

echo ""
echo "=== ALLOW cases (wrappers + ordinary commands stay silent) ==="

assert_allow "Bash: resend-send.sh wrapper" \
    '{"tool_name":"Bash","tool_input":{"command":".claude/skills/secret-use/resend-send.sh --to a@b.com --subject Hi --text ok"}}'

assert_allow "Bash: with-secret.sh wrapper" \
    '{"tool_name":"Bash","tool_input":{"command":"with-secret.sh resend_api_key --file-env K -- python3 x.py"}}'

assert_allow "Bash: secret-curl.sh wrapper" \
    '{"tool_name":"Bash","tool_input":{"command":"secret-curl.sh llm_api_key '"'"'Authorization: Bearer %s'"'"' https://api.example.com/v1/models"}}'

assert_allow "Bash: tg-send.sh wrapper" \
    '{"tool_name":"Bash","tool_input":{"command":"tg-send.sh alert_bot_token 123456789 hi"}}'

assert_allow "Bash: secret-status.sh wrapper" \
    '{"tool_name":"Bash","tool_input":{"command":"secret-status.sh resend_api_key"}}'

assert_allow "Bash: reveal-secret.sh wrapper (sanctioned channel)" \
    '{"tool_name":"Bash","tool_input":{"command":"reveal-secret.sh some_service_api_key --reason paste-into-vendor-console"}}'

assert_allow "Bash: env-sourcing script (no literal)" \
    '{"tool_name":"Bash","tool_input":{"command":"set -a; . scripts/load-env.sh; set +a; python -m pytest"}}'

assert_allow "Bash: plain git/ls" \
    '{"tool_name":"Bash","tool_input":{"command":"git status && ls -la"}}'

assert_allow "Read: ordinary vault file" \
    '{"tool_name":"Read","tool_input":{"file_path":"/home/you/personal-os/AGENTS.md"}}'

assert_allow "Edit: not a read tool, even with /run/secrets path" \
    '{"tool_name":"Edit","tool_input":{"file_path":"/run/secrets/whatever"}}'

assert_allow "Malformed JSON (fail-open)" 'not json'

echo ""
echo "=== ALLOW: fail-closed false-positive fixes (only fire when really dangerous) ==="

assert_allow "Bash: commit message mentioning 'sops decrypt' (not a boundary)" \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add sops decrypt wrapper script\""}}'
assert_allow "Bash: echo mentioning sops -d in a string" \
    '{"tool_name":"Bash","tool_input":{"command":"echo \"use with-secret.sh instead of sops -d\""}}'
assert_allow "Bash: public ssh host key (.pub is not secret)" \
    '{"tool_name":"Bash","tool_input":{"command":"cat /etc/ssh/ssh_host_ed25519_key.pub"}}'

echo ""
echo "=== robustness: no ReDoS hang, no fail-open on huge command ==="

# ReDoS: a long 'sops'+'a'*N command must return well under the 10s timeout.
# (generate the big string INSIDE python so nothing large crosses argv)
redos_json="$(python3 -c 'import json; cmd="sops "+"a"*200000; print(json.dumps({"tool_name":"Bash","tool_input":{"command":cmd}}))')"
t0=$(date +%s%N); printf '%s' "$redos_json" | "$HOOK" >/dev/null; t1=$(date +%s%N)
ms=$(( (t1 - t0) / 1000000 ))
if [ "$ms" -lt 3000 ]; then echo "PASS (PERF): ReDoS-safe (${ms}ms < 3000ms)"; PASS_COUNT=$((PASS_COUNT+1)); else echo "FAIL (PERF): guard took ${ms}ms (possible ReDoS)"; FAIL_COUNT=$((FAIL_COUNT+1)); fi

# Huge command (>128KB) that DOES read a secret must still DENY (no fail-open via argv limit).
huge_json="$(python3 -c 'import json; cmd="cat /run/secrets/some_service_api_key # "+"x"*200000; print(json.dumps({"tool_name":"Bash","tool_input":{"command":cmd}}))')"
huge_out="$(printf '%s' "$huge_json" | "$HOOK")"
if printf '%s' "$huge_out" | grep -q '"permissionDecision":"deny"'; then echo "PASS (DENY): 200KB command still denied (no argv fail-open)"; PASS_COUNT=$((PASS_COUNT+1)); else echo "FAIL (DENY): huge command fail-opened"; echo "    out=${huge_out:0:120}"; FAIL_COUNT=$((FAIL_COUNT+1)); fi

out_empty="$(printf '' | "$HOOK")"; status_empty=$?
if [ "$status_empty" -eq 0 ] && [ -z "$out_empty" ]; then
    echo "PASS (ALLOW): Empty stdin (fail-open)"; PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "FAIL (ALLOW): Empty stdin (fail-open)"; echo "    exit=$status_empty stdout=$out_empty"; FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""; echo "=== Summary ==="; echo "PASS: $PASS_COUNT   FAIL: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
