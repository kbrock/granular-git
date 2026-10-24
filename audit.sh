#!/bin/bash
# Read-only audit of the granular-git setup. Run it from your own terminal with the daemon
# running. Each failure prints the command that fixes it. Exits 1 if anything failed.

dir=$(cd "$(dirname "$0")" && pwd)
req='protocol=https\nhost=github.com\n\n'
real_gh=$(type -ap gh | grep -v "^$dir/build/shims/" | head -1)
fails=0

check() {
  local desc=$1 fix=$2
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $desc"
  else
    echo "FAIL  $desc"
    echo "      fix: $fix"
    fails=$((fails + 1))
  fi
}

helper_chain() {
  local helpers
  helpers=$(cd / && git config --get-all credential.helper)
  [ "$(echo "$helpers" | tail -1)" = "$dir/build/granular-git" ] && echo "$helpers" | grep -qx ''
}
daemon_answers() { printf 'get github.com\n' | nc -U -w 60 "$HOME/.granular/sock" | grep -q '^ok '; }
git_fills() { (cd / && printf "$req" | git credential fill) | grep -qx 'username=x-access-token'; }
fails_closed() { ! printf "$req" | HOME=/nonexistent "$dir/build/granular-git" get; }
direct_answers() { printf "$req" | "$dir/build/granular-git" get | grep -q '^password='; }

no_osx_item() { ! security find-internet-password -s github.com; }
osx_returns_nothing() { [ -z "$(printf "$req" | git credential-osxkeychain get 2>/dev/null)" ]; }

no_gh_item() { ! security find-generic-password -s gh:github.com; }
gh_has_no_token() { [ -n "$real_gh" ] && ! env -u GH_TOKEN -u GITHUB_TOKEN "$real_gh" auth token; }
no_token_env() { ! env | grep -qE '^(GH|GITHUB)_TOKEN='; }
no_hosts_token() { ! grep -qs oauth_token "$HOME/.config/gh/hosts.yml"; }
wrapper_first() { [ "$(command -v gh)" = "$dir/build/shims/gh" ]; }
gh_authenticated() { gh auth status; }

echo "git"
check "credential.helper ends with an empty entry, then granular-git" \
  "in ~/.gitconfig: 'helper =' (empty), then 'helper = $dir/build/granular-git'; remove other credential.helper lines" helper_chain
if grep -q '^USE_DAEMON = true' "$dir/granular.rb"; then
  check "daemon answers 'get github.com'""start it: $dir/build/granular-daemon" daemon_answers
  check "git credential fill returns the helper's answer" "fix the checks above first" git_fills
  check "granular-git gives no token when the daemon is unreachable" "granular-git must exit non-zero without a daemon" fails_closed
else
  check "granular-git answers 'get' directly (USE_DAEMON is false)" \
    "make link, then store logins: $dir/build/granular-passwd ro github.com and rw github.com" direct_answers
  check "git credential fill returns the helper's answer" "fix the checks above first" git_fills
fi

echo "osxkeychain"
check "no saved github.com item in the keychain" \
  "printf '$req' | git credential-osxkeychain erase" no_osx_item
check "git credential-osxkeychain returns nothing for github.com" \
  "printf '$req' | git credential-osxkeychain erase" osx_returns_nothing

echo "gh"
check "gh keyring item is gone" "gh auth logout -h github.com" no_gh_item
check "the real gh has no token (gh auth token fails)" "gh auth logout -h github.com" gh_has_no_token
check "GH_TOKEN and GITHUB_TOKEN are not set" "unset them and remove them from your shell profile" no_token_env
check "hosts.yml holds no oauth_token" "gh auth logout -h github.com" no_hosts_token
check "the wrapper is the first gh on PATH" "put $dir/build/shims first on PATH" wrapper_first
check "gh works through the wrapper" "store logins: $dir/build/granular-passwd ro github.com and rw github.com" gh_authenticated

[ "$fails" -eq 0 ]
