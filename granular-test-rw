#!/bin/bash
# This tests what the rw profile can do: push is accepted, and the gh token has the repo scope.
# It does not check machine setup (that is audit.sh).
# Run this from your own terminal, or from a Claude session whose slot you flipped to read-write.
# Run it inside a clone of a repo you can push to, public or private.
# It changes nothing on GitHub: a push with --dry-run, and one read. Prints PASS or FAIL per check and no tokens.
# Exits 1 if anything failed.

dir=$(cd "$(dirname "$0")" && pwd)
bin=$(dirname "$(command -v granular-git || echo "$dir/build/granular-git")")
repo=$(git rev-parse --show-toplevel) || exit 1
git -C "$repo" remote get-url origin >/dev/null || exit 1
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

push_out=$(git -C "$repo" "${helper[@]}" push --dry-run 2>&1)
push_status=$?
gh_out=$(gh api -i user 2>&1)

push_accepted() { [ "$push_status" -eq 0 ]; }
push_not_refused() { ! grep -q 'Write access to repository not granted' <<<"$push_out"; }
gh_reads() { head -1 <<<"$gh_out" | grep -q ' 200'; }
gh_token_is_classic() { grep -qi '^x-oauth-scopes:.*repo' <<<"$gh_out"; }

echo "read-write profile ($repo)"
check "push is accepted" push_accepted
check "push is not refused for write access" push_not_refused
check "gh can read" gh_reads
check "gh holds a token with the repo scope" gh_token_is_classic

[ "$fails" -eq 0 ]
