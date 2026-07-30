#!/bin/bash
# Restores the fork's own changes inside the vendored TelegramCore.
#
# Why this exists: submodules/telegram-ios is a git submodule pinned to a commit of
# overtake/Telegram-iOS, which we cannot push to. The parent repo does not track anything inside
# it, and `git submodule update` reverts the whole tree — silently deleting our added files and
# undoing our hooks.
#
# Two kinds of change are restored:
#   1. NEW files          -> fork-patches/telegramcore/*.swift, copied in
#   2. HOOKS in upstream files -> fork-patches/telegramcore-hooks.patch, git-applied
#
# Idempotent — running it twice is a no-op. Run it after every fresh clone and after every
# `git submodule update`.
#
#   ./fork-patches/apply-telegramcore-patches.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/fork-patches/telegramcore"
PATCH="$ROOT/fork-patches/telegramcore-hooks.patch"
SUBMODULE="$ROOT/submodules/telegram-ios"
DEST="$SUBMODULE/submodules/TelegramCore/Sources"

if [ ! -d "$DEST" ]; then
    echo "ERROR: $DEST not found."
    echo "Run 'git submodule update --init --recursive' first."
    exit 1
fi

# ---- 1. new files -------------------------------------------------------------
echo "New files:"
copied=0
unchanged=0

for file in "$SRC"/*.swift; do
    [ -e "$file" ] || continue
    name="$(basename "$file")"
    target="$DEST/$name"

    if [ -f "$target" ] && cmp -s "$file" "$target"; then
        echo "  = $name (already current)"
        unchanged=$((unchanged + 1))
    else
        cp "$file" "$target"
        echo "  + $name -> TelegramCore/Sources/"
        copied=$((copied + 1))
    fi
done

echo "  $copied copied, $unchanged already current."

# Verify every mirror matches its destination byte for byte.
fail=0
for file in "$SRC"/*.swift; do
    [ -e "$file" ] || continue
    name="$(basename "$file")"
    if ! diff -q "$file" "$DEST/$name" > /dev/null; then
        echo "ERROR: $name differs after copy."
        fail=1
    fi
done

# ---- 2. hooks in upstream files -----------------------------------------------
echo "Hooks in upstream files:"
if [ ! -f "$PATCH" ]; then
    echo "  (no patch file — nothing to apply)"
elif git -C "$SUBMODULE" apply --reverse --check "$PATCH" 2> /dev/null; then
    # The patch reverses cleanly, so it is already applied.
    echo "  = telegramcore-hooks.patch (already applied)"
elif git -C "$SUBMODULE" apply --check "$PATCH" 2> /dev/null; then
    git -C "$SUBMODULE" apply "$PATCH"
    echo "  + telegramcore-hooks.patch applied"
else
    echo "ERROR: telegramcore-hooks.patch does not apply cleanly and is not already applied."
    echo "The submodule has probably moved to a new upstream commit — re-apply the hooks by hand"
    echo "(see FENIXUZ_HOOKS.md 'Bot token login') and regenerate the patch with:"
    echo "  git -C submodules/telegram-ios diff -- submodules/TelegramCore/Sources/State/ > fork-patches/telegramcore-hooks.patch"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi

echo "All TelegramCore fork patches verified."
