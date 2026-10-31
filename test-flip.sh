#!/bin/bash
# This tests the flip: a process at ro cannot push, and the same process flipped to rw can.
# It does not check machine setup (that is audit.sh).
# Run this from the process you will flip, a Claude session or a terminal, with the daemon running.
# It commits a timefile to the test repo, and pushes it to GitHub once the process is rw.
# Prints PASS or FAIL per check and no tokens. Exits 1 if anything failed.

dir=$(cd "$(dirname "$0")" && pwd)
bin=$(dirname "$(command -v granular-git || echo "$dir/build/granular-git")")
repo=${GRANULAR_TEST_REPO:-$HOME/src/granular-git-test}
helper=(-c credential.helper= -c "credential.helper=$bin/granular-git")
fails=0

check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $desc"
  else
    echo "FAIL  $desc"
    fails=$((fails + 1))
  fi
}

push_refused() { ! git -C "$repo" "${helper[@]}" push; }
push_works() { git -C "$repo" "${helper[@]}" push; }

echo "flip ($repo)"
git -C "$repo" "${helper[@]}" push --dry-run >/dev/null 2>&1
echo "In the daemon's tab, make sure this process is ro. Then press Enter."
read -r
date >> "$repo/timefile"
git -C "$repo" add timefile
git -C "$repo" commit -q -m "updated time"
check "push is refused at ro" push_refused

echo "In the daemon's tab, flip this process to rw. Then press Enter."
read -r
check "push works at rw" push_works

echo "In the daemon's tab, flip this process back to ro. Then press Enter."
read -r
check "push is refused again at ro" push_refused

echo "If you flipped a terminal's slot to ro for this test, you may want to flip it back to rw."

[ "$fails" -eq 0 ]
