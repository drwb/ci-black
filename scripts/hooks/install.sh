#!/usr/bin/env bash
# One-time installer for repo-local git hooks.
# Symlinks scripts/hooks/* into .git/hooks/ so updates to the tracked
# script propagate automatically (no copy-and-forget drift).

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
src_dir="$repo_root/scripts/hooks"
dst_dir="$repo_root/.git/hooks"

mkdir -p "$dst_dir"

for hook in pre-push; do
    src="$src_dir/$hook"
    dst="$dst_dir/$hook"
    # Relative symlink target — survives re-cloning to a different path.
    # `.git/hooks/<hook>` → `../../scripts/hooks/<hook>`.
    rel="../../scripts/hooks/$hook"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        echo "⚠ $dst exists and is not a symlink — backing up to $dst.bak"
        mv "$dst" "$dst.bak"
    fi
    ln -sf "$rel" "$dst"
    chmod +x "$src"
    echo "✓ installed $hook → $rel"
done
