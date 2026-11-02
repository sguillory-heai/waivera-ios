#!/usr/bin/env bash
# Usage: stop-at-minutes.sh <minutes> <result bundle name>
# Interrupts the xcodebuild writing <result bundle name> once <minutes> have passed. An interrupted
# xcodebuild still closes its result bundle, so the screenshots and audit reports taken so far can
# be exported; a step that reaches its own time limit is killed with the bundle left unreadable.
# Give each step at least four minutes past <minutes>: one for the interrupt to land, then a
# terminate if xcodebuild is still running, and time to close the bundle.
set -u
pattern="resultBundlePath $2"
sleep $(($1 * 60))
echo "::warning::Tests reached the $1-minute limit; stopping them so the results so far are kept"
pkill -INT -f "$pattern" || exit 0
sleep 60
pkill -TERM -f "$pattern" && echo "::warning::xcodebuild ignored the interrupt; terminated it" || true
