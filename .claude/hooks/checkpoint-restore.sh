#!/usr/bin/env bash
# SessionStart(clear) restore. After a /clear, re-inject the last checkpoint's
# "## Current state" so the fresh session resumes without the old transcript.
# Reads the pointer written by the /checkpoint skill (~/.claude/last-checkpoint).
# Non-breaking by construction: emits nothing unless source==clear AND a valid
# checkpoint note with a Current-state section exists. Any failure => silent exit 0.
export LC_ALL=C

input=$(cat 2>/dev/null)
# Only after an explicit /clear. If the source field is absent (older CC), the
# settings.json matcher "clear" is the gate; here we require it when present.
src=$(jq -r '.source // empty' <<<"$input" 2>/dev/null)
[ "$src" = "clear" ] || exit 0

ptr="$HOME/.claude/last-checkpoint"
[ -f "$ptr" ] || exit 0
note=$(head -1 "$ptr" 2>/dev/null)
[ -n "$note" ] && [ -f "$note" ] || exit 0

# Extract the "## Current state" section up to the next "## " heading.
state=$(awk '/^## Current state/{f=1;print;next} f&&/^## /{exit} f{print}' "$note" 2>/dev/null)
[ -n "$state" ] || exit 0

ctx=$(printf 'Resumed after /clear. Last checkpoint: %s\n\n%s\n\n(Read the full note to continue where you left off.)' "$note" "$state")

# SessionStart adds this string to the fresh session's context.
jq -cn --arg c "$ctx" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null \
  || printf '%s\n' "$ctx"   # fallback: plain stdout is also injected on SessionStart
