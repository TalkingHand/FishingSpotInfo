#!/bin/bash
# `pzt run` plus real mouse clicks: starts tests/tools/clicker.ps1 next to the test game and
# turns on the test's real right-click part (ARGS realclick=1). The mouse cursor moves for a
# moment during the clicks. Plain `pzt run` skips the real clicks.
cd "$(dirname "$0")/../.." || exit 1
ENV_WIN=$(cygpath -w "$PWD/pzt-env")
powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tests/tools/clicker.ps1)" -EnvDir "$ENV_WIN" > clicker.log 2>&1 &
CLICKER=$!
bash ../PZTestHarness/pzt run ARGS="realclick=1" "$@"
RESULT=$?
wait $CLICKER 2>/dev/null
echo "--- clicker ---"
cat clicker.log
exit $RESULT
