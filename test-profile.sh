#!/bin/bash
# This prints the profile this process gets: rw if a push --dry-run to the test repo works, ro if GitHub
# refuses the write. Anything else prints error and the last line git said.
# Run it in a session, flip that session's slot in the daemon's tab, and run it again: the answer changes.
# It needs no input and changes nothing on GitHub. It prints no tokens.

bin=$(dirname "$(command -v granular-git)")
repo=${GRANULAR_TEST_REPO:-$HOME/src/granular-git-test}

if out=$(git -C "$repo" -c credential.helper= -c "credential.helper=$bin/granular-git" push --dry-run 2>&1); then
  echo rw
elif grep -q 'Write access to repository not granted' <<<"$out"; then
  echo ro
else
  echo "error: $(tail -1 <<<"$out")"
  exit 1
fi
