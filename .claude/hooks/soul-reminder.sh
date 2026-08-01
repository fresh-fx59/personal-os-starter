#!/usr/bin/env bash
# soul-reminder.sh — UserPromptSubmit hook: re-anchor the SOUL.md reply contract
# every turn. Plain stdout on exit 0 is injected as context; static, no deps,
# always exits 0 (fails open). ~90 tokens/turn.
# HARD RULE: keep this ONE short block — growing it recreates the wall-of-text
# problem it exists to fix. Full rules live in personal-os/SOUL.md.
cat <<'EOF'
Reply contract (SOUL.md): line 1 = DONE/ACTION NEEDED/DECISION NEEDED/BLOCKED/FYI + bottom line <=15 plain words (code/infra DONE states live-state). Body <=6 short lines, plain words, data verbatim. Last block `From you:` = nothing OR numbered copy-paste steps, zero rationale inside. Max ONE question per message. Gloss all shorthand. Facts beat agreement.
EOF
exit 0
