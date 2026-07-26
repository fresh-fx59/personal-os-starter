#!/usr/bin/env bash
# pii-secret-scan.sh — flag operator PII and secret-shaped strings.
#
# Modes:
#   pii-secret-scan.sh [path]            scan the tracked working tree (default path = .)
#   pii-secret-scan.sh --staged [path]   scan only lines ADDED in the current staged diff
#   pii-secret-scan.sh --history [path]   scan every blob across all refs (slow)
#
# Exit 0 = clean, 1 = hits found (prints them). Single source of truth for the
# denylist; reused by tools/pii-guard/hooks/pre-commit and by ad-hoc audits.
#
# ⚠ FIRST RUN: fill in YOUR identifiers below. The list ships with the personal
# patterns removed (placeholders marked FILL ME) — a shipped denylist of someone
# else's identifiers protects nobody. Until you fill it in, only the generic
# secret-SHAPE patterns fire.
#
# Keep the denylist current: add an identifier here the moment a new one appears
# (new email, phone, host, private IP, bot handle). See tools/pii-guard/README.md.
#
# NOTE: this file is itself committed, so the denylist is public in a public repo.
# That is the accepted trade (an email or a host label is low-harm and the guard is
# worthless without it) — but never put a live *secret* in PATTERNS. Match secrets by
# SHAPE, as the generic block below does. A key worth blocking is a key worth rotating.
set -uo pipefail

MODE="tree"; TARGET="."
for a in "$@"; do
  case "$a" in
    --staged)  MODE="staged" ;;
    --history) MODE="history" ;;
    *)         TARGET="$a" ;;
  esac
done

# Your distinctive identifiers + generic secret shapes. Word-boundary the ones where a
# bare number or name would over-match. Pick DISTINCTIVE markers: a common first name
# fires on every unrelated mention and trains you to ignore the hook — a surname, a
# full email, or a host label is the useful signal.
PATTERNS=(
  # ---- FILL ME: your identifiers (delete the ones you don't have) ----------
  # '\b1234567890\b'                        # your personal Telegram/Discord user id
  # '\b9876543210\b'                        # an alerting/escalation chat id
  # 'you@example\.com'                      # personal email
  # 'you@work\.example\.com'                # work email (leaks employer + real name)
  # '\bYourSurname\b'                       # surname as it appears in prompts/commits
  # '\bvmi1234567\b'                        # VPS host label from your provider
  # '\b203\.0\.113\.7\b'                    # a server's public IP
  # '\b100\.64\.0\.1\b'                     # a VPN/tailnet IP
  # '\byour-street-address\b'               # anything else that identifies you offline

  # ---- generic secret SHAPES (keep these; they need no configuration) ------
  '\b[0-9]{8,10}:[A-Za-z0-9_-]{35}\b'                # telegram bot token shape
  'sk-ant-[A-Za-z0-9_-]{20}'                         # anthropic key
  'sk-[A-Za-z0-9]{20,}'                              # openai key
  'AKIA[0-9A-Z]{16}'                                 # aws access key id
  'gh[pousr]_[A-Za-z0-9]{30,}'                       # github token
  'xox[baprs]-[A-Za-z0-9-]{10,}'                     # slack token
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'              # private key
)
JOINED=$(printf '%s|' "${PATTERNS[@]}"); JOINED="${JOINED%|}"

hits=0
case "$MODE" in
  staged)
    # Only additions in the staged diff (what THIS commit introduces).
    out=$(git -C "$TARGET" diff --cached -U0 --no-color 2>/dev/null \
          | grep '^+' | grep -vE '^\+\+\+' \
          | grep -nIE "$JOINED" 2>/dev/null | head -200)
    [ -n "$out" ] && { echo "$out"; hits=1; }
    ;;
  history)
    out=$(git -C "$TARGET" log --all -p 2>/dev/null | grep -nIE "$JOINED" 2>/dev/null | head -200)
    [ -n "$out" ] && { echo "$out"; hits=1; }
    ;;
  tree)
    if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
      out=$(git -C "$TARGET" grep -nIE "$JOINED" 2>/dev/null | head -200)
    else
      out=$(grep -rnIE "$JOINED" "$TARGET" 2>/dev/null | head -200)
    fi
    [ -n "$out" ] && { echo "$out"; hits=1; }
    ;;
esac

if [ "$hits" = "1" ]; then
  echo "PII/secret scan: HITS FOUND" >&2
  exit 1
else
  echo "PII/secret scan: clean" >&2
  exit 0
fi
