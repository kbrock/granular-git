#!/bin/bash
# This tests what the ro profile can do: fetch works, push is refused, the token has no repo scope.
# It does not check machine setup (that is audit.sh).
# Run this from a process that should get the read-only profile, for example from inside a Claude session.
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
push_refused() { ! git -C "$repo" "${helper[@]}" push --dry-run; }
push_says_no_access() { git -C "$repo" "${helper[@]}" push --dry-run 2>&1 | grep -q 'Write access to repository not granted'; }
gh_reads() { gh api -i user | head -1 | grep -q ' 200'; }
gh_token_is_not_classic() { ! gh api -i user | grep -qi '^x-oauth-scopes:.*repo'; }

echo "read-only profile ($repo)"
check "fetch works" fetch_works
check "push is refused" push_refused
check "push says write access is not granted" push_says_no_access
check "gh can read" gh_reads
check "gh holds a token without the repo scope" gh_token_is_not_classic

[ "$fails" -eq 0 ]
