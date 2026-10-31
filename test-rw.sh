#!/bin/bash
# This tests what the rw profile can do: fetch works, push is accepted, the token has repo scope.
# It does not check machine setup (that is audit.sh).
# Run this from your own terminal, or from a Claude session whose slot you flipped to read-write.
# It changes nothing on GitHub: reads, and a push with --dry-run. Prints PASS or FAIL per check and no tokens.
# Exits 1 if anything failed.

dir=$(cd "$(dirname "$0")" && pwd)
bin=$(dirname "$(command -v granular-git || echo "$dir/build/granular-git")")
repo=${GRANULAR_TEST_REPO:-$HOME/src/granular-git-test}
url=$(git -C "$repo" remote get-url origin)
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

fetch_works() { git "${helper[@]}" ls-remote "$url" HEAD | grep -q HEAD; }
push_accepted() { git -C "$repo" "${helper[@]}" push --dry-run; }
push_not_refused() { ! git -C "$repo" "${helper[@]}" push --dry-run 2>&1 | grep -q 'Write access to repository not granted'; }
gh_reads() { gh api -i user | head -1 | grep -q ' 200'; }
gh_token_is_classic() { gh api -i user | grep -qi '^x-oauth-scopes:.*repo'; }

echo "read-write profile ($repo)"
check "fetch works" fetch_works
check "push is accepted" push_accepted
check "push is not refused for write access" push_not_refused
check "gh can read" gh_reads
check "gh holds a token with the repo scope" gh_token_is_classic

[ "$fails" -eq 0 ]
