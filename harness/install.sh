#!/bin/sh
# Re-arm the verify hook after a fresh clone (core.hooksPath is not cloned).
set -e
git config core.hooksPath harness/hooks
chmod +x harness/hooks/pre-commit harness/lint-notes.mjs 2>/dev/null || true
echo "verify hook armed: core.hooksPath = harness/hooks"
echo "run 'npm run lint' any time to verify the vault."
