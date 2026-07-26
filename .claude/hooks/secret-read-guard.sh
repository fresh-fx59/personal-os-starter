#!/usr/bin/env bash
# secret-read-guard.sh — Claude Code PreToolUse hook
#
# Purpose: when a Bash/Read tool call would reveal a secret VALUE inline (a rendered
# sops secret under /run/secrets/, a `sops decrypt`, or age/sops key material), DENY
# the call and hand the agent an intent-aware nudge naming the correct wrapper. The
# `deny` decision is fed back to the model, which self-corrects on the same turn —
# NO operator prompt, fully autonomous (unlike the old `ask`, which halted).
#
# Contract (Claude Code PreToolUse hook):
#   - stdin: one JSON object: {"tool_name": "...", "tool_input": {...}, ...}
#   - To DENY (block + tell the model why): print exactly
#       {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<reason>"}}
#     to stdout and exit 0. The model reads <reason> and picks a wrapper instead.
#   - To ALLOW: print nothing and exit 0.
#   - FAIL-OPEN: on ANY error (bad JSON, missing fields, python3 missing/crashing) —
#     print nothing and exit 0. This runs on every tool call in every session; it must
#     never wedge a legitimate call.
#
# The JSON payload is fed to python on STDIN (not argv) so a >128KB command can never
# hit MAX_ARG_STRLEN and fail the exec (which would fail-open past a real reveal).
# Path matching is dot/glob/trailing-slash tolerant and normalises Read paths, so
# /run/sec*/x, d=/run/secrets;cat "$d"/x, and /run/./secrets/x are all caught. The
# sops/decrypt matcher is anchored to a command boundary and uses only linear scans
# (no catastrophic backtracking).
#
# The nudge names wrapper paths ABSOLUTELY, so any session on the machine can invoke
# them regardless of its cwd. Set VAULT_DIR below to your vault's absolute path (or
# export SECRET_USE_DIR to override at runtime).
#
# Wiring: keep this file in the vault (versioned) and symlink it into the agent's hook
# directory — e.g. `ln -s <vault>/.claude/hooks/secret-read-guard.sh ~/.claude/hooks/`
# — so one edit updates both the committed copy and the live hook. Register it as a
# PreToolUse hook for Bash/Read/Grep/Glob in your settings.json.

set -u

INPUT="$(cat 2>/dev/null || true)"

PYSRC="$(cat <<'PYEOF'
import json
import re
import sys
import os

# CONFIGURE ME: absolute path to this vault's wrapper directory. It must be absolute —
# the nudge is read by an agent whose cwd is unknown.
SU = os.environ.get("SECRET_USE_DIR") or os.path.expanduser("~/personal-os/.claude/skills/secret-use")

# /run/secrets in its evasive spellings: trailing-slash-optional, extra/interior
# slashes and dot-segments (/run//secrets, /run/./secrets), and a glob on the dir
# (/run/sec*, /run/secret?, /run/sec[r]...). [./]* is a single char-class star —
# linear, no catastrophic backtracking.
SECRET_PATH_RE = re.compile(r'/run/[./]*sec(?:rets?\b|[a-z]*[*?\[])')
SECRET_NAME_RE = re.compile(r'/run/[./]*secrets?/([A-Za-z0-9_.\-]+)')
# `sops <decrypt>` at a command boundary only (avoids denying a commit message that
# merely mentions "sops decrypt"); linear scan, no `.*`, no catastrophic backtracking.
SOPS_DECRYPT_RE = re.compile(r'(?:^|[;|&\n(]|\bsudo\s+)\s*sops\s+(?:-d\b|--decrypt\b|decrypt\b)')
SSH_KEY_RE = re.compile(r'ssh_host_ed25519_key(?!\.pub)')


def generic(name):
    n = name or "<name>"
    return (
        f" To USE the value, go through a wrapper so it never touches ps/logs: "
        f"`{SU}/with-secret.sh {n} --file-env VAR -- <cmd>`. "
        f"To check it is set: `{SU}/secret-status.sh {n}`. "
        f"If a human EXPLICITLY asked to SEE the raw value: `{SU}/reveal-secret.sh {n}` "
        f"(autonomous, audit-logged). "
        f"If you were only SEARCHING for the string (grep/find/ls) you do not need the "
        f"file — drop the '/run/secrets/' prefix from your pattern, or use secret-status.sh."
    )


def wrapper_hint(name):
    n = (name or "").lower()
    if "resend" in n:
        return f"send email with `{SU}/resend-send.sh --to … --subject … --text …`"
    if "bot_token" in n or ("telegram" in n and "bot" in n):
        return f"send a Telegram message with `{SU}/tg-send.sh {name} <chat_id> <text>`"
    if "gemini" in n:  # Gemini REST needs x-goog-api-key, NOT Bearer
        return f"call the API with `{SU}/secret-curl.sh {name} 'x-goog-api-key: %s' <url> …`"
    if any(k in n for k in ("llm", "openai", "anthropic", "api_key", "token")):
        return (f"call the API with "
                f"`{SU}/secret-curl.sh {name} 'Authorization: Bearer %s' <url> …`")
    if "database_url" in n or "_dsn" in n or n.endswith("dsn"):
        return (f"run the query with "
                f"`{SU}/with-secret.sh {name} --env DSN -- sh -c 'psql \"$DSN\" -c …'`")
    return None


def reason_for_secret(name):
    lead = "Blocked: reading a secret value inline leaks it into ps/logs/transcript. "
    hint = wrapper_hint(name)
    if hint and name:
        lead += f"For /run/secrets/{name}: {hint}."
    return lead + generic(name)


def main():
    try:
        raw = sys.stdin.read()
        if not raw or not raw.strip():
            return
        try:
            data = json.loads(raw)
        except Exception:
            return
        if not isinstance(data, dict):
            return

        tool_name = data.get("tool_name")
        tool_input = data.get("tool_input")
        if not isinstance(tool_input, dict):
            tool_input = {}

        reason = None

        if tool_name == "Bash":
            command = tool_input.get("command")
            if isinstance(command, str):
                if SECRET_PATH_RE.search(command):
                    m = SECRET_NAME_RE.search(command)
                    reason = reason_for_secret(m.group(1) if m else None)
                elif SOPS_DECRYPT_RE.search(command):
                    reason = (
                        "Blocked: `sops decrypt` would reveal decrypted secret contents. "
                        "Runtime values are already rendered under /run/secrets/ — USE them via "
                        f"`{SU}/with-secret.sh <name> --file-env VAR -- <cmd>`, not by decrypting. "
                        "Decrypting or editing the encrypted files is a human operation."
                    )
                elif ("SOPS_AGE_KEY" in command
                      or ("keys.txt" in command and "age" in command)
                      or SSH_KEY_RE.search(command)):
                    reason = (
                        "Blocked: this references age/sops KEY MATERIAL (the master key). It is "
                        "never needed for normal operations and must not be revealed — stop and "
                        "reconsider what you actually need; use a secret-use wrapper for runtime values."
                    )

        else:
            # File-reading tools whose path arg could point at a secret: Read.file_path,
            # Grep.path, Glob.path. (Defense-in-depth: /run/secrets is root-0700 so these
            # tools already get EACCES today, but a mis-permissioned secret would leak.)
            pkey = {"Read": "file_path", "Grep": "path", "Glob": "path"}.get(tool_name)
            if pkey:
                p = tool_input.get(pkey)
                if isinstance(p, str) and p:
                    norm = re.sub(r'^/+', '/', os.path.normpath(p))
                    if norm == "/run/secrets" or norm.startswith("/run/secrets/"):
                        name = norm[len("/run/secrets/"):].strip("/") or None
                        reason = reason_for_secret(name)

        if reason is None:
            return

        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }
        sys.stdout.write(json.dumps(out, separators=(",", ":")))
    except Exception:
        return


main()
PYEOF
)"

# Feed the payload on STDIN (bash builtin printf has no argv size limit; the pipe has
# none either), so a huge command can never fail the exec and fail-open past a reveal.
OUTPUT="$(printf '%s' "$INPUT" | python3 -c "$PYSRC" 2>/dev/null)"
PY_STATUS=$?

if [ "$PY_STATUS" -ne 0 ]; then
    exit 0
fi

if [ -n "$OUTPUT" ]; then
    printf '%s' "$OUTPUT"
fi

exit 0
