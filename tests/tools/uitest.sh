#!/bin/bash
# `pzt live` plus real mouse and keys: starts tests/tools/clicker.ps1 next to the test game and
# turns on the test's real right-click part (ARGS realclick=1). The mouse cursor moves (and left Ctrl is held) for a
# moment during the clicks. Plain `pzt live` skips the real clicks. The game stays open: `pzt stop` at the end.
cd "$(dirname "$0")/../.." || exit 1
ENV_WIN=$(cygpath -w "$PWD/pzt-env")
powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tests/tools/clicker.ps1)" -EnvDir "$ENV_WIN" > clicker.log 2>&1 &
CLICKER=$!
bash ../PZTestHarness/pzt live ARGS="realclick=1" "$@"
RESULT=$?
# pzt live leaves the game open, so stop the clicker here; the test always ends with a
# "release" request, so Ctrl is not held any more
kill $CLICKER 2>/dev/null
echo "--- clicker ---"
cat clicker.log
exit $RESULT
