#!/usr/bin/env bash
# Install the pii-guard pre-commit hook into a target git repo.
#
#   tools/pii-guard/install.sh [repo-path]   (default: current directory)
#
# Installs a small shim at <repo>/.git/hooks/pre-commit that execs the shared,
# versioned hook by absolute path. If a pre-commit hook already exists (and isn't
# ours), it is preserved as pre-commit.local and chained. Idempotent.
set -euo pipefail

# Absolute path to THIS vault's copy of the hook — the shim execs it, so every repo
# you arm shares one versioned hook + denylist and updates with a single edit here.
GUARD_HOOK="$(cd "$(dirname "$0")/hooks" && pwd)/pre-commit"
REPO="${1:-.}"
GITDIR="$(git -C "$REPO" rev-parse --git-dir 2>/dev/null)" || { echo "not a git repo: $REPO" >&2; exit 1; }
HOOKS="$REPO/$GITDIR/hooks"; mkdir -p "$HOOKS"
DEST="$HOOKS/pre-commit"
SIG="# pii-guard-shim"

if [ -f "$DEST" ] && ! grep -q "$SIG" "$DEST" 2>/dev/null; then
  mv "$DEST" "$HOOKS/pre-commit.local"
  echo "existing pre-commit preserved as pre-commit.local (will be chained)"
fi

cat > "$DEST" <<EOF
#!/usr/bin/env bash
$SIG
"$GUARD_HOOK" "\$@" || exit 1
[ -x "\$(dirname "\$0")/pre-commit.local" ] && "\$(dirname "\$0")/pre-commit.local" "\$@"
exit 0
EOF
chmod +x "$DEST"
echo "pii-guard armed in $REPO (.git/hooks/pre-commit → $GUARD_HOOK)"
