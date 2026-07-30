#!/bin/bash
# Restores the fork's own source files into the vendored TelegramCore.
#
# Why this exists: submodules/telegram-ios is a git submodule pinned to a commit of
# overtake/Telegram-iOS, which we cannot push to. Any file we add inside it is invisible
# to the parent repo and a `git submodule update` wipes it without warning. So the real
# copy is tracked here in the parent repo and this script puts it back.
#
# Idempotent — running it twice is a no-op. Run it after every fresh clone and after any
# `git submodule update`.
#
#   ./fork-patches/apply-telegramcore-patches.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/fork-patches/telegramcore"
DEST="$ROOT/submodules/telegram-ios/submodules/TelegramCore/Sources"

if [ ! -d "$DEST" ]; then
    echo "ERROR: $DEST not found."
    echo "Run 'git submodule update --init --recursive' first."
    exit 1
fi

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

echo ""
echo "$copied copied, $unchanged already current."

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

if [ "$fail" -ne 0 ]; then
    exit 1
fi

echo "All TelegramCore fork patches verified."
