#!/bin/bash
# fenix-build.sh — reliable Debug build with the REAL pass/fail status.
# Why: a plain `xcodebuild ...; echo $?` reports the echo's exit code (always 0),
# NOT xcodebuild's. This script greps the log for "BUILD SUCCEEDED" and returns
# the real result + a clean error list.
#
# Usage:
#   ./fenix-build.sh           build only
#   ./fenix-build.sh run       build, then launch Fenixuz.app on success
#   ./fenix-build.sh timing    build with slow-compile + phase timing diagnostics

set -uo pipefail
cd "$(dirname "$0")"

LOG=/tmp/fenix-build.log
DD=/tmp/tgmac-dd
APP="$DD/Build/Products/Debug/Fenixuz.app"
MODE="${1:-}"

EXTRA=()
if [ "$MODE" = "timing" ]; then
  # Warn about expressions/functions slow to type-check (>200ms) + per-phase timing.
  EXTRA+=( OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -warn-long-function-bodies=200 -Xfrontend -warn-long-expression-type-checking=200' )
  EXTRA+=( -showBuildTimingSummary )
fi

echo "🔨 Building Fenixuz (Debug)… $(date +%H:%M:%S)"
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram \
  -configuration Debug -derivedDataPath "$DD" \
  "${EXTRA[@]}" build CODE_SIGN_STYLE=Automatic > "$LOG" 2>&1

if grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "✅ BUILD SUCCEEDED  ($(date +%H:%M:%S))"
  if [ "$MODE" = "timing" ]; then
    echo "— slowest to type-check —"
    grep -hoE "[0-9]+ms\s+(function body|expression)" "$LOG" | sort -rn | head -15
    echo "— build phase timing —"
    sed -n '/Build Timing Summary/,/^$/p' "$LOG" | head -25
  fi
  if [ "$MODE" = "run" ]; then
    echo "🚀 Launching $APP"
    open -n "$APP"
  fi
  exit 0
else
  echo "❌ BUILD FAILED — Swift errors:"
  grep "error:" "$LOG" | grep "\.swift:" | sort -u | head -25
  echo "(full log: $LOG)"
  exit 1
fi
