#!/bin/bash
# Double-fork attack. Run it from a Claude session, inside a repo on the granular-test branch.
# The inner subshell is orphaned, reparents to launchd, and runs granular-test-ro with no claude in its chain.
# test-ro passes: the orphan got ro and the attack is blocked. It fails: the orphan got rw and the attack works.
out=$(mktemp)
( ( sleep 1; granular-trust >"$out" 2>&1; granular-test-ro >>"$out" 2>&1; echo "exit $?" >>"$out" ) & )
sleep 8
cat "$out"
if grep -q "exit 0" "$out"; then
  echo "BLOCKED: the orphan is ro"
else
  echo "ATTACK WORKS: the orphan is not ro"
fi
rm -f "$out"
